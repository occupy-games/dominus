#!/usr/bin/env python3
"""Decode the observed original 2.4 follower resource layout and Wwise bank audio.

Format research/provenance is recorded in docs/ORIGINAL_ASSETS.md. Source files
are read only. No third-party implementation is embedded in these decoders.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import wave
import zlib

ROOT = Path(__file__).resolve().parents[1]


def iw_hash(name):
    result = 5381
    for value in name.lower().encode():
        result = (result * 33 + value) & 0xFFFFFFFF
    return result


def resource_group(data):
    if data[:1] != b"=":
        raise ValueError("Not a Marmalade resource group")
    cursor, result = 6, {}
    while cursor + 4 <= len(data):
        section, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        if section == 0:
            return result
        size, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        if size < 4 or cursor + size - 4 > len(data):
            raise ValueError("Invalid resource section bounds")
        payload = data[cursor:cursor + size - 4]
        cursor += size - 4
        if section != iw_hash("ResGroupResources"):
            continue
        types, = struct.unpack_from("<I", payload)
        offset = 4
        for _ in range(types):
            kind, count, omitted, sized = struct.unpack_from("<IIBB", payload, offset)
            offset += 10
            if not sized:
                raise ValueError("Unsized resources are unsupported")
            resources = result.setdefault(kind, {})
            for _ in range(count):
                start = offset
                length, = struct.unpack_from("<I", payload, offset)
                offset += 4
                name = None
                if not omitted:
                    name, = struct.unpack_from("<I", payload, offset)
                    offset += 4
                group, = struct.unpack_from("<I", payload, offset)
                offset += 4
                if length < offset - start or start + length > len(payload):
                    raise ValueError("Invalid resource bounds")
                resources[group if name is None else name] = payload[offset:start + length]
                offset = start + length
        if offset != len(payload):
            raise ValueError("Unconsumed resource payload")
    raise ValueError("Missing group terminator")


def decode_skeleton(data):
    count, = struct.unpack_from("<I", data)
    if len(data) != 4 + count * 44:
        raise ValueError("Unsupported skeleton record size")
    bones, names = [], {}
    for index in range(count):
        kind, name, parent, *values = struct.unpack_from("<III7fHH", data, 4 + index * 44)
        if kind != iw_hash("CIwAnimBone") or values[7] != index or (parent and parent not in names):
            raise ValueError("Invalid bone hierarchy")
        bones.append({"name": f"bone_{name:08x}", "parent": names.get(parent, -1),
                      "rotation": values[:4], "position": values[4:7]})
        names[name] = index
    return bones


def block(data, name):
    marker = struct.pack("<II", iw_hash(name), iw_hash(name))
    offset = data.find(marker)
    if offset < 0:
        raise ValueError("Missing " + name)
    return offset


def decode_model(data):
    v = block(data, "CIwModelBlockVerts")
    total, = struct.unpack_from("<I", data, v + 12)
    unique, = struct.unpack_from("<H", data, v + 18)
    if not 0 < unique <= total <= 16384:
        raise ValueError("Invalid vertex count")
    values = struct.unpack_from("<" + "f" * (unique * 3), data, v + 20)
    vertices = list(zip(values[:unique], values[unique:unique * 2], values[unique * 2:]))
    remap = list(struct.unpack_from("<" + "H" * (total - unique), data, v + 20 + unique * 12))
    if any(i >= unique for i in remap):
        raise ValueError("Invalid duplicate vertex mapping")
    vertices += [vertices[i] for i in remap]
    uv = block(data, "CIwModelBlockGLUVs")
    normal = block(data, "CIwModelBlockNorms")
    for offset in [uv, normal]:
        if struct.unpack_from("<I", data, offset + 12)[0] != total:
            raise ValueError("Attribute counts disagree")
    uvs = list(struct.iter_unpack("<ff", data[uv + 18:uv + 18 + total * 8]))
    normals = list(struct.iter_unpack("<fff", data[normal + 18:normal + 18 + total * 12]))
    tri = block(data, "CIwModelBlockGLTriList")
    count, = struct.unpack_from("<I", data, tri + 12)
    indices = list(struct.unpack_from("<" + "H" * count, data, tri + 22))
    if count % 3 or any(i >= total for i in indices):
        raise ValueError("Invalid triangle indices")
    if tri + 22 + count * 2 + 12 != len(data):
        raise ValueError("Unsupported model footer")
    material, = struct.unpack_from("<I", data, len(data) - 4)
    return {"vertices": vertices, "normals": normals, "uvs": uvs, "indices": indices,
            "remap": remap, "unique": unique, "material": material}


def decode_skin(data, model):
    version, model_id, skeleton_id, groups = struct.unpack_from("<4I", data)
    if version != 1:
        raise ValueError("Unsupported skin version")
    offset, bindings = 16, {}
    for group in range(groups):
        kind, number, count, influences, flags = struct.unpack_from("<IIIBB", data, offset)
        if kind != iw_hash("CIwAnimSkinSet") or number != 0 or not 1 <= influences <= 4 or flags != 1:
            raise ValueError("Unsupported skin set")
        bones = list(data[offset + 14:offset + 14 + influences])
        offset += 14 + influences
        ids = struct.unpack_from("<" + "H" * count, data, offset)
        offset += count * 2
        local = struct.unpack_from("<" + "f" * (count * influences * 3), data, offset)
        offset += count * influences * 12
        weights = struct.unpack_from("<" + "f" * (count * influences), data, offset)
        offset += count * influences * 4
        for i, encoded in enumerate(ids):
            index = encoded & 0x3FFF
            blend = list(weights[i * influences:(i + 1) * influences])
            if index >= model["unique"] or abs(sum(blend) - 1) > 0.001 or min(blend) < 0:
                raise ValueError("Invalid skin weights")
            bindings[index] = {"bones": bones, "weights": blend,
                               "local": [local[(i * influences + b) * 3:(i * influences + b + 1) * 3] for b in range(influences)]}
    if offset != len(data) or len(bindings) != model["unique"]:
        raise ValueError("Skin coverage mismatch")
    result = [bindings[i] for i in range(model["unique"])]
    result += [bindings[i] for i in model["remap"]]
    return result


def decode_animation(data, bone_count, bones=None):
    skeleton, count, flags, frames = struct.unpack_from("<4I", data)
    if count != bone_count:
        raise ValueError("Unsupported animation encoding")
    keys, start = [], 16
    for frame in range(frames):
        if struct.unpack_from("<I", data, start)[0] != iw_hash("CIwAnimKeyFrame"):
            raise ValueError("Invalid animation keyframe")
        time, = struct.unpack_from("<f", data, start + 8)
        kind, stored, mode = data[start + 12], struct.unpack_from("<I", data, start + 30)[0], data[start + 34]
        if kind not in (2, 3) or mode not in (0, 1) or stored not in (count, count + 1):
            raise ValueError("Unsupported keyframe transform encoding")
        stride = 35 + stored * (28 if kind == 2 else 16)
        values = list(struct.iter_unpack("<7f" if kind == 2 else "<4f", data[start + 35:start + stride]))
        if stored == count + 1:
            identity = (0, 0, 0, 1, 0, 0, 0) if kind == 2 else (1, 0, 0, 0)
            if any(abs(a - b) > 0.0001 for a, b in zip(values[-1], identity)):
                raise ValueError("Unrecognized extra animation transform")
            values.pop()
        if kind == 3 and bones is None:
            raise ValueError("Rotation-only keys require source skeleton translations")
        poses = values if kind == 2 else [tuple(bones[i]["position"]) + tuple(q) for i, q in enumerate(values)]
        if any(not math.isfinite(v) for pose in poses for v in pose):
            raise ValueError("Invalid animation transforms")
        keys.append({"time": time, "poses": poses})
        start += stride
    if start + 8 != len(data):
        raise ValueError("Unconsumed animation payload")
    if len(keys) < 2 or any(keys[i]["time"] >= keys[i + 1]["time"] for i in range(len(keys) - 1)):
        raise ValueError("Animation must have increasing timestamps")
    return {"duration": keys[-1]["time"], "frames": keys}


def png(path, width, height, channels, pixels):
    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    if channels not in (3, 4) or len(pixels) != width * height * channels:
        raise ValueError("Unsupported texture pixels")
    filtered = b"".join(b"\0" + pixels[y * width * channels:(y + 1) * width * channels] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2 if channels == 3 else 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(filtered)) + chunk(b"IEND", b""))


def extract_texture(data, path):
    width, height, pitch = struct.unpack_from("<HHH", data, 17)
    channels = pitch // width
    if len(data) != 28 + pitch * height or data[-1] != 0 or channels not in (2, 3, 4):
        raise ValueError("Unsupported source texture layout")
    pixels = data[27:27 + pitch * height]
    if channels == 2:  # IwImage RGB565
        rgb = bytearray()
        for value, in struct.iter_unpack("<H", pixels):
            rgb.extend((((value >> 11) & 31) * 255 // 31, ((value >> 5) & 63) * 255 // 63, (value & 31) * 255 // 31))
        channels, pixels = 3, bytes(rgb)
    png(path, width, height, channels, pixels)


def model_with_texture(resources, key, name, output, prefix):
    model = decode_model(resources[iw_hash("CIwModel")][key])
    material = resources[iw_hash("CIwMaterial")][model["material"]]
    if len(material) != 9:
        raise ValueError("Unsupported source material")
    texture_id, = struct.unpack_from("<I", material, 5)
    texture_name = prefix + f"_{texture_id:08x}.png"
    extract_texture(resources[iw_hash("CIwTexture")][texture_id], output / texture_name)
    model.update({"name": name, "resource_id": key, "texture": texture_name})
    return model


def extract_sheep(source, output):
    path = source / "sheep.group.bin"
    resources = resource_group(path.read_bytes())
    bones = decode_skeleton(next(iter(resources[iw_hash("CIwAnimSkel")].values())))
    clips = {state: decode_animation(resources[iw_hash("CIwAnim")][iw_hash(name)], len(bones))
             for state, name in [("idle", "default_stand"), ("walking", "default_walk"), ("resting", "default_graze")]}
    models = []
    for key in resources[iw_hash("CIwModel")]:
        model = model_with_texture(resources, key, f"sheep_{key:08x}", output, "sheep")
        model["bindings"] = decode_skin(resources[iw_hash("CIwAnimSkin")][key], model)
        models.append(model)
    result = {"source": path.name, "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "bones": bones, "clips": clips, "models": models}
    (output / "sheep.json").write_text(json.dumps(result, separators=(",", ":"), allow_nan=False))
    print(f"Original sheep: {len(models)} meshes, {len(bones)} bones, {len(clips)} clips")
    return {"source": path.name, "sha256": result["source_sha256"], "models": len(models)}


def extract_scenery(source, output):
    result = {}
    for name in ["trees", "tents"]:
        path = source / (name + ".group.bin")
        resources = resource_group(path.read_bytes())
        models = [model_with_texture(resources, key, f"{key:08x}", output, name)
                  for key in resources[iw_hash("CIwModel")]]
        # Full standing trees have their base at ground level. Detached parts
        # and flat shadow meshes remain in the library, not assembled by guesswork.
        standing = [i for i, m in enumerate(models)
                    if min(v[1] for v in m["vertices"]) >= -1 and max(v[1] for v in m["vertices"]) > 300]
        result[name] = {"source": path.name, "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "models": models, "standing": standing,
                        "base": next((i for i, m in enumerate(models) if m["resource_id"] == iw_hash("rank1_loc1_var1_storey1")), 0)}
        print(f"Original {name}: {len(models)} source components")
    (output / "scenery.json").write_text(json.dumps(result, separators=(",", ":"), allow_nan=False))
    return {name: {"source": d["source"], "sha256": d["source_sha256"], "models": len(d["models"])} for name, d in result.items()}


FOLLOWER_CLIPS = {
    "idle": "default_stand_1", "walking": "default_walk_1", "building": "default_hammer_ground_1",
    "sacrifice_1": "default_sacrifice_1", "sacrifice_2": "default_sacrifice_2",
    "swamp_stand": "swamp_stand_1", "swamp_struggle": "swamp_stand_1_struggle_1",
    "swamp_die": "swamp_die_1", "swamp_sink": "swamp_sink",
}


def extract_followers(source, output):
    path = source / "follower.group.bin"
    resources = resource_group(path.read_bytes())
    skeletons = resources[iw_hash("CIwAnimSkel")]
    if len(skeletons) != 1:
        raise ValueError("Expected a shared follower skeleton")
    bones = decode_skeleton(next(iter(skeletons.values())))
    clips = {state: decode_animation(resources[iw_hash("CIwAnim")][iw_hash(name)], len(bones))
             for state, name in FOLLOWER_CLIPS.items()}
    models = []
    for name in ["male_lod1", "female_lod1"]:
        model = decode_model(resources[iw_hash("CIwModel")][iw_hash(name)])
        model["bindings"] = decode_skin(resources[iw_hash("CIwAnimSkin")][iw_hash(name)], model)
        material = resources[iw_hash("CIwMaterial")][model["material"]]
        if len(material) != 9:
            raise ValueError("Unsupported follower material")
        texture_id, = struct.unpack_from("<I", material, 5)
        texture = resources[iw_hash("CIwTexture")][texture_id]
        width, height, pitch = struct.unpack_from("<HHH", texture, 17)
        texture_name = name + ".png"
        # These texture records contain a 27-byte header and one trailing flag.
        # Including that final flag shifts every RGB channel by one byte.
        extract_texture(texture, output / texture_name)
        model.update({"name": name, "texture": texture_name})
        models.append(model)
    result = {"source": "follower.group.bin", "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "bones": bones, "clips": clips, "models": models,
              "clip_names": FOLLOWER_CLIPS}
    (output / "followers.json").write_text(json.dumps(result, separators=(",", ":"), allow_nan=False))
    print(f"Original followers: {len(models)} meshes, {len(bones)} bones, {len(clips)} animation clips")
    return {"source": result["source"], "sha256": result["source_sha256"], "models": [m["name"] for m in models], "clips": result["clip_names"]}


def chunks(data, offset=0, padded=False):
    result = {}
    while offset + 8 <= len(data):
        tag, size = struct.unpack_from("<4sI", data, offset)
        if offset + 8 + size > len(data):
            raise ValueError("Truncated chunk " + str(tag))
        result[tag] = data[offset + 8:offset + 8 + size]
        offset += 8 + size + (size % 2 if padded else 0)
    return result


def package_media(data):
    if data[:4] != b"AKPK":
        raise ValueError("Not a Wwise package")
    header, flag, languages, banks, sounds, external = struct.unpack_from("<6I", data, 4)
    cursor, media, objects = 28 + languages, {}, []
    for is_bank, size in [(True, banks), (False, sounds), (False, external)]:
        if not size:
            continue
        count, = struct.unpack_from("<I", data, cursor)
        if size != 4 + count * 20:
            raise ValueError("Unsupported package table")
        for i in range(count):
            key, block_size, length, block_offset, language = struct.unpack_from("<5I", data, cursor + 4 + i * 20)
            offset = block_offset * (block_size or 1)
            if offset + length > len(data):
                raise ValueError("Package entry outside source")
            payload = data[offset:offset + length]
            if not is_bank:
                media[key] = payload  # full streamed media supersedes embedded prefetch
                continue
            bank = chunks(payload)
            for index in range(0, len(bank.get(b"DIDX", b"")), 12):
                media_id, start, length = struct.unpack_from("<III", bank[b"DIDX"], index)
                media[media_id] = bank[b"DATA"][start:start + length]
            if b"HIRC" in bank:
                count, = struct.unpack_from("<I", bank[b"HIRC"])
                pointer = 4
                for _ in range(count):
                    kind, length, object_id = struct.unpack_from("<BII", bank[b"HIRC"], pointer)
                    body = bank[b"HIRC"][pointer + 9:pointer + 5 + length]
                    objects.append((kind, object_id, body))
                    pointer += 5 + length
        cursor += size
    return media, objects


def extract_audio(source, output, ww2ogg, codebooks, revorb):
    target = output / "audio"
    target.mkdir(exist_ok=True)
    records, failed = [], []
    for package in ["GodusMain", "BubbleTunes"]:
        path = source / "SoundBanks/Mac" / (package + ".pck")
        media, objects = package_media(path.read_bytes())
        music_ids = set()
        for kind, key, body in objects:
            if kind == 11:  # AkMusicTrack, Wwise v88
                for identifier in media:
                    if struct.pack("<I", identifier) in body:
                        music_ids.add(identifier)
        for key, data in sorted(media.items()):
            if data[:4] != b"RIFF":
                continue
            try:
                riff = chunks(data, 12, True)
                codec, channels, rate, average, alignment, bits = struct.unpack_from("<HHIIHH", riff[b"fmt "])
                name = package + "_" + str(key)
                filename = name + (".wav" if codec == 0xFFFE else ".ogg")
                destination = target / filename
                if codec == 0xFFFE and bits == 16 and alignment == channels * 2 and average == rate * alignment:
                    with wave.open(str(destination), "wb") as stream:
                        stream.setnchannels(channels)
                        stream.setsampwidth(2)
                        stream.setframerate(rate)
                        stream.writeframes(riff[b"data"])
                    duration = len(riff[b"data"]) / average
                elif codec == 0xFFFF and ww2ogg.is_file() and codebooks.is_file():
                    temporary = target / (name + ".wem")
                    temporary.write_bytes(data)
                    run = subprocess.run([str(ww2ogg), str(temporary), "-o", str(destination), "--pcb", str(codebooks)], capture_output=True, text=True)
                    temporary.unlink()
                    if run.returncode:
                        raise ValueError(run.stdout[-250:] + run.stderr[-250:])
                    # ww2ogg emits zero granule positions. Remux without
                    # transcoding so Godot gets correct length/seek/loop data.
                    remuxed = target / (name + ".timed.ogg")
                    run = subprocess.run([str(revorb), str(destination), str(remuxed)], capture_output=True, text=True)
                    if run.returncode:
                        raise ValueError("Ogg timing repair failed: " + run.stderr[-250:])
                    remuxed.replace(destination)
                    duration = len(riff[b"data"]) / max(average, 1)
                else:
                    raise ValueError(f"Unsupported codec {codec:04x} or missing ww2ogg")
                records.append({"id": key, "package": package, "path": "audio/" + filename,
                                "music_track": key in music_ids, "duration_estimate": duration, "channels": channels,
                                "source": path.relative_to(source).as_posix(), "source_media_sha256": hashlib.sha256(data).hexdigest()})
            except (ValueError, KeyError, struct.error) as error:
                failed.append({"package": package, "id": key, "reason": str(error)})
    (output / "audio_catalog.json").write_text(json.dumps({"assets": records, "failures": failed}, indent=2))
    print(f"Original audio: {len(records)} media, {sum(r['music_track'] for r in records)} music sources, {len(failed)} failures")
    return {"media": len(records), "failures": failed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "data/godus2_4")
    parser.add_argument("--output", type=Path, default=ROOT / "game/assets/original")
    parser.add_argument("--ww2ogg", type=Path, default=ROOT / "build/reference/ww2ogg-master/ww2ogg")
    parser.add_argument("--codebooks", type=Path, default=ROOT / "build/reference/ww2ogg-master/packed_codebooks_aoTuV_603.bin")
    parser.add_argument("--revorb", type=Path, default=ROOT / "build/reference/revorb")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if source == output or source in output.parents or output in source.parents:
        parser.error("Source and output must be separate directories")
    output.mkdir(parents=True, exist_ok=True)
    if not args.revorb.is_file():
        parser.error("revorb is required to repair Ogg timing without transcoding; pass --revorb")
    result = {"followers": extract_followers(source, output), "sheep": extract_sheep(source, output),
              "scenery": extract_scenery(source, output),
              "audio": extract_audio(source, output, args.ww2ogg, args.codebooks, args.revorb)}
    from audio_events import extract as extract_events
    extract_events(source, output)
    from campaign import extract as extract_campaign
    extract_campaign(source, output)
    from ui_assets import extract as extract_ui
    extract_ui(source, output)
    (output / "provenance.json").write_text(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
