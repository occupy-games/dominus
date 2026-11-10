#!/usr/bin/env python3
"""Recover every observed the original source CIwModel, with source IDs and dependency reports."""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path
import struct
import shutil

from original_assets import ROOT, resource_group, iw_hash, decode_model, extract_texture
from model_behaviors import Behaviors


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, separators=(",", ":"), allow_nan=False))
    temporary.replace(path)


def category_for(source):
    name = Path(source).name.lower()
    if any(s in name for s in ["follower", "god_finger", "god_hand"]): return "People and equipment"
    if any(s in name for s in ["sheep", "wolf", "birds", "pigeon", "fish"]): return "Animals"
    if any(s in name for s in ["tree", "seed", "swamp"]): return "Vegetation"
    if any(s in name for s in ["boulder", "granite", "gem", "landscape"]): return "Geology"
    if any(s in name for s in ["boat", "ark", "raft", "dock", "pier", "slipway"]): return "Boats and harbors"
    if any(s in name for s in ["farm", "mining", "settlement", "town", "rampart", "setblock"]): return "Settlements and industry"
    if any(s in name for s in ["rural", "tent", "hut", "abode", "bronze", "iron", "primitive", "monastery"]): return "Dwellings"
    if any(s in name for s in ["temple", "shrine", "idol", "statue", "obelisk", "portal", "archway", "sacrifice", "fountain", "future", "rocket"]): return "Monuments and powers"
    if any(s in name for s in ["vfx", "flicker", "background", "symbol", "flag", "card"]): return "Effects and scene elements"
    return "Props and treasures"


def extract(source, output):
    output.mkdir(parents=True, exist_ok=True)
    (output / "geometry").mkdir(exist_ok=True)
    (output / "textures").mkdir(exist_ok=True)
    names = {}
    with (source / "GeneratedDataFiles/Models.csv").open(newline="") as stream:
        for row in list(csv.reader(stream))[1:]:
            if row and row[0]: names[iw_hash(row[0])] = row[0]
    # Dynamic models use the same names in many groups; preserve per-group IDs.
    for rank in range(1, 8):
        for location in range(1, 8):
            for variant in range(1, 8):
                for storey in range(1, 4):
                    base = f"rank{rank}_loc{location}_var{variant}_storey{storey}"
                    for suffix in ["", "_shadow", "_scaffolds"] + [f"_part{i:02d}" for i in range(1, 9)]:
                        name = base + suffix
                        names.setdefault(iw_hash(name), name)
    records, failures, textures = [], [], {}
    behaviors = Behaviors(source, output)
    for path in sorted(source.rglob("*.group.bin"), key=lambda p: (p.name != "follower.group.bin", str(p))):
        relative = path.relative_to(source).as_posix()
        raw = path.read_bytes()
        group_hash = hashlib.sha256(raw).hexdigest()
        resources = resource_group(raw)
        motion_group = behaviors.group(relative, resources)
        for key, body in resources.get(iw_hash("CIwModel"), {}).items():
            identifier = relative + ":" + f"{key:08x}"
            record = {"id": identifier, "source": relative, "resource_id": key,
                      "name": names.get(key, f"model_{key:08x}"), "source_sha256": group_hash,
                      "category": category_for(relative)}
            record["family"] = re.sub(r"_(?:(?:part\d+|scaffolds)(?:_shadow)?|shadow)$", "", record["name"])
            try:
                model = decode_model(body)
                motion = behaviors.model(relative, resources, key, model, motion_group)
                if motion: record["motion"] = motion
                texture_name, material_status = "", "unresolved"
                material = resources.get(iw_hash("CIwMaterial"), {}).get(model["material"])
                if material and len(material) == 9:
                    texture_id, = struct.unpack_from("<I", material, 5)
                    texture = resources.get(iw_hash("CIwTexture"), {}).get(texture_id)
                    if texture:
                        digest = hashlib.sha256(texture).hexdigest()
                        texture_name = "textures/" + digest + ".png"
                        if digest not in textures:
                            extract_texture(texture, output / texture_name)
                            textures[digest] = True
                        material_status = "source_texture"
                model.pop("remap")
                model.pop("unique")
                model.update({"resource_id": key, "texture": texture_name, "source": relative,
                              "material_status": material_status,
                              "source_shader": "shdrTree" if "trees" in path.name else ""})
                geometry_hash = hashlib.sha256(body + relative.encode()).hexdigest()
                geometry = "geometry/" + geometry_hash + ".json"
                write_json(output / geometry, model)
                low = [min(v[i] for v in model["vertices"]) for i in range(3)]
                high = [max(v[i] for v in model["vertices"]) for i in range(3)]
                record.update({"geometry": geometry, "texture": texture_name, "bounds": [low, high],
                               "vertices": len(model["vertices"]), "triangles": len(model["indices"]) // 3,
                               "material_status": material_status})
                records.append(record)
            except (ValueError, KeyError, struct.error) as error:
                record["reason"] = str(error)
                failures.append(record)
    # Also include every recovered text .geo component, not only binary groups.
    library = output.parents[1] / "library"
    library_catalog = library / "catalog.json"
    if library_catalog.is_file():
        for assembly in json.loads(library_catalog.read_text()).get("assemblies", []):
            data = json.loads((library / assembly["model"]).read_text())
            for part in data["parts"]:
                relative = part["source"]
                body = (source / relative).read_bytes()
                digest = hashlib.sha256(body).hexdigest()
                texture_source = output.parents[1] / "extracted" / part["texture"]
                texture_name = "textures/" + hashlib.sha256(texture_source.read_bytes()).hexdigest() + texture_source.suffix
                shutil.copyfile(texture_source, output / texture_name)
                vertices, normals, uvs = [], [], []
                for triangle in part["triangles"]:
                    for v, n, uv in triangle:
                        vertices.append(part["vertices"][v])
                        normals.append(part["normals"][n])
                        uvs.append(part["uvs"][uv])
                model = {"vertices": vertices, "normals": normals, "uvs": uvs,
                         "indices": list(range(len(vertices))), "resource_id": iw_hash(part["name"]),
                         "texture": texture_name, "source": relative, "material_status": "source_texture"}
                geometry = "geometry/" + digest + ".json"
                write_json(output / geometry, model)
                bounds = [[f(v[i] for v in vertices) for i in range(3)] for f in [min, max]]
                records.append({"id": relative, "source": str(Path(relative).parent), "resource_id": model["resource_id"],
                                "name": Path(relative).stem, "family": "ChristmasTree", "category": "Monuments and powers",
                                "source_sha256": digest, "geometry": geometry, "texture": texture_name,
                                "bounds": bounds, "vertices": len(vertices), "triangles": len(vertices) // 3,
                                "material_status": "source_texture", "assembly_id": assembly["id"]})
    behaviors.finish(records)
    catalog = {"version": 1, "models": records, "unsupported": failures,
               "source_model_count": len(records) + len(failures), "textures": len(textures)}
    write_json(output / "catalog.json", catalog)
    print(f"3D model extraction: {len(records)} recovered, {len(failures)} unsupported, {len(textures)} original textures")
    print(f"Unresolved materials: {sum(m['material_status'] != 'source_texture' for m in records)}")
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "data/godus2_4")
    parser.add_argument("--output", type=Path, default=ROOT / "game/assets/original/models")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if source == output or source in output.parents or output in source.parents:
        parser.error("Source and output must be separate")
    extract(source, output)


if __name__ == "__main__":
    main()
