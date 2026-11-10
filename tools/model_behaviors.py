"""Source-only animation and lifecycle metadata for the model catalog."""
import csv
import hashlib
import json
from pathlib import Path
import re
import struct
import math

try:
    from .original_assets import iw_hash, decode_skeleton, decode_skin, decode_animation
except ImportError:
    from original_assets import iw_hash, decode_skeleton, decode_skin, decode_animation


def environment_for(source):
    name = Path(source).name.lower().removesuffix(".group.bin")
    name = re.sub(r"^(hiend_|loend_)", "", name)
    if name == "fish": return "underwater"
    if name in {"boats", "rafts", "ark", "arkprop", "astariidolbasewater1", "astariidolbasewater2"}: return "water"
    if "dock" in name or "pier" in name or name == "slipway": return "shore"
    return "land"


def decode_locators(data):
    """Observed Locator: type-range table followed by (slot, source X/Z/Y)."""
    candidates = []
    for count in range(3, min(100, len(data) // 4)):
        offsets = struct.unpack_from("<" + "I" * count, data)
        if offsets[0] == 0 and list(offsets) == sorted(offsets) and len(data) == count * 4 + offsets[-1] * 16:
            candidates.append((count, offsets))
    if len(candidates) != 1: raise ValueError("Ambiguous Locator range table")
    count, offsets = candidates[0]
    parts = {}
    # Type 1 is 'part'; even slots 2,4,... identify part01,part02,... .
    for index in range(offsets[1], offsets[2]):
        slot, x, z, y = struct.unpack_from("<I3f", data, count * 4 + index * 16)
        if slot < 2 or slot % 2 or not all(math.isfinite(v) for v in [x, y, z]):
            raise ValueError("Unsupported part locator")
        parts[slot // 2] = [x, y, z]
    return {"type_count": count - 1, "parts": parts}


def embedded_in_complete(base, part, offset):
    """Detect construction chunks already represented by the authored full mesh."""
    tolerance = max(0.02, max(max(v[i] for v in base) - min(v[i] for v in base) for i in range(3)) * 0.015)
    cells = {}
    for point in base:
        key = tuple(math.floor(v / tolerance) for v in point)
        cells.setdefault(key, []).append(point)
    hits = 0
    for point in part:
        point = [point[i] + offset[i] for i in range(3)]
        key = tuple(math.floor(v / tolerance) for v in point)
        found = False
        for x in range(-1, 2):
            for y in range(-1, 2):
                for z in range(-1, 2):
                    for candidate in cells.get((key[0]+x, key[1]+y, key[2]+z), []):
                        if sum((a-b)**2 for a,b in zip(point,candidate)) <= tolerance*tolerance: found = True; break
                    if found: break
                if found: break
            if found: break
        hits += found
    return hits / max(1, len(part)) >= 0.9


class Behaviors:
    def __init__(self, source, output):
        self.source, self.output = source, output
        (output / "motion").mkdir(exist_ok=True)
        self.names = {}
        for path in [source / "GeneratedDataFiles/Anims.csv", *source.glob("GeneratedDataFiles/AnimationMap*.csv")]:
            for row in list(csv.reader(path.open()))[1:]:
                for name in row:
                    name = name.strip()
                    if name and not name.replace(".", "").isdigit(): self.names[iw_hash(name)] = name.lower()
        text = (source / "GeneratedDataFiles/HouseModels.h").read_text()
        self.buildings = {}
        for table, body in re.findall(r'static const char\* (\w+)_filenames\[\] = \{(.*?)\};', text, re.S):
            paths = re.findall(r'"([^"]+\.geo)"', body)
            if not paths: continue
            group = re.sub(r'R\d+L\d+V\d+S\d+$', '', table).lower()
            self.buildings[group, Path(paths[0]).stem] = [Path(p).stem for p in paths]
        self.groups, self.clip_count, self.failures = {}, 0, []
        self.locators = {}

    def write(self, name, value):
        path = "motion/" + name + ".json"
        temporary = (self.output / path).with_suffix(".json.tmp")
        temporary.write_text(json.dumps(value, separators=(",", ":"), allow_nan=False))
        temporary.replace(self.output / path)
        return path

    def group(self, relative, resources):
        for key, raw in resources.get(iw_hash("Locator"), {}).items():
            try: self.locators[relative, key] = decode_locators(raw)
            except ValueError: pass
        skeletons = resources.get(iw_hash("CIwAnimSkel"), {})
        if len(skeletons) != 1: return {}
        sid, raw = next(iter(skeletons.items()))
        bones = decode_skeleton(raw)
        clips, unsupported = [], []
        prefix = hashlib.sha256(relative.encode()).hexdigest()[:18]
        for key, data in resources.get(iw_hash("CIwAnim"), {}).items():
            name = self.names.get(key, f"clip_{key:08x}")
            try:
                clip = decode_animation(data, len(bones), bones)
                path = self.write(prefix + f"_clip_{key:08x}", clip)
                clips.append({"id": f"{key:08x}", "name": name, "path": path,
                              "duration": clip["duration"], "sha256": hashlib.sha256(data).hexdigest()})
                self.clip_count += 1
            except (ValueError, struct.error) as error:
                unsupported.append({"name": name, "reason": str(error)})
        clips.sort(key=lambda c: c["name"])
        result = {"bones": bones, "clips": clips, "unsupported": unsupported, "prefix": prefix}
        self.groups[relative] = result
        return result

    def model(self, relative, resources, key, model, group):
        skin = resources.get(iw_hash("CIwAnimSkin"), {}).get(key)
        if not skin or not group: return {}
        try:
            bindings = decode_skin(skin, model)
        except (ValueError, struct.error) as error:
            self.failures.append({"source": relative, "model": key, "reason": str(error)})
            return {}
        # Seasonal skins can reuse clips only when the actual skeleton matches.
        donor = group
        if not donor["clips"] and "follower" in relative:
            candidate = self.groups.get("follower.group.bin", {})
            if candidate.get("bones") == group["bones"]: donor = candidate
        path = self.write(group["prefix"] + f"_skin_{key:08x}", {"bones": group["bones"], "bindings": bindings})
        return {"skin": path, "clips": donor["clips"], "unsupported": group["unsupported"]}

    def finish(self, records):
        index = {(m["source"], m["name"]): m for m in records}
        assembly_cache = {}
        for model in records:
            model["environment"] = environment_for(model["source"])
            source = re.sub(r'^(hiend_|loend_)', '', Path(model["source"]).name.removesuffix(".group.bin"))
            names = self.buildings.get((source, model["family"]))
            evidence = "HouseModels.h + Locator part anchors"
            if names is None:
                candidate = index.get((model["source"], model["family"]))
                if candidate is None:
                    continue
                anchors = self.locators.get((candidate["source"], candidate["resource_id"]), {}).get("parts", {})
                if not anchors: continue
                names = [candidate["name"]] + sorted(m["name"] for m in records if m["source"] == model["source"] and m["family"] == model["family"] and m["name"] != candidate["name"])
                evidence = "Locator part anchors + matching source resource family"
            available = [index[model["source"], name] for name in names if (model["source"], name) in index
                         and index[model["source"], name]["material_status"] == "source_texture"]
            base = next((m for m in available if m["name"] == model["family"]), None)
            if base is None: continue
            locator = self.locators.get((base["source"], base["resource_id"]), {})
            components, missing = [], []
            for component in available:
                name = component["name"]
                match = re.search(r'_part(\d+)(?:_shadow)?$', name)
                offset = [0, 0, 0]
                placement = "authored source coordinates"
                if match:
                    number = int(match[1])
                    if number not in locator.get("parts", {}):
                        # Some Weyworld chunks are already authored in the full
                        # building's coordinates, byte-for-byte with its mesh.
                        reference = base
                        if name.endswith("_shadow"):
                            reference = next((m for m in available if m["name"] == base["name"] + "_shadow"), base)
                        part_vertices = json.loads((self.output / component["geometry"]).read_text())["vertices"]
                        reference_vertices = json.loads((self.output / reference["geometry"]).read_text())["vertices"]
                        points = {tuple(round(v, 3) for v in p) for p in part_vertices}
                        reference_points = {tuple(round(v, 3) for v in p) for p in reference_vertices}
                        if len(points & reference_points) / max(1, len(points)) < 0.85:
                            missing.append(component["id"])
                            continue
                        placement = "authored coordinates verified by mesh vertex overlap"
                    else:
                        offset = locator["parts"][number]
                        placement = "original Locator part anchor"
                role = "part" if match else ("scaffold" if "_scaffolds" in name else ("shadow" if name.endswith("_shadow") else "complete"))
                if name.endswith("_shadow"):
                    role = "part_shadow" if match else ("scaffold_shadow" if "_scaffolds" in name else "shadow")
                components.append({"model_id": component["id"], "name": name, "role": role,
                                   "offset": offset, "part_number": int(match[1]) if match else 0,
                                   "placement_evidence": placement})
            if base["id"] not in assembly_cache:
                base_vertices = json.loads((self.output / base["geometry"]).read_text())["vertices"]
                for component in components:
                    if component["role"] == "part":
                        record = next(m for m in available if m["id"] == component["model_id"])
                        vertices = json.loads((self.output / record["geometry"]).read_text())["vertices"]
                        component["embedded_in_complete"] = embedded_in_complete(base_vertices, vertices, component["offset"])
                assembly_cache[base["id"]] = {"base_id": base["id"], "components": components, "unresolved": missing,
                    "evidence": evidence, "locator_types": locator.get("type_count", 0)}
            assembly = assembly_cache[base["id"]]
            model["building_assembly"] = assembly
            if model["id"] == base["id"]:
                lows, highs = [list(base["bounds"][0])], [list(base["bounds"][1])]
                for component in assembly["components"]:
                    if component["role"] != "part": continue
                    record = next(m for m in available if m["id"] == component["model_id"])
                    lows.append([record["bounds"][0][i]+component["offset"][i] for i in range(3)])
                    highs.append([record["bounds"][1][i]+component["offset"][i] for i in range(3)])
                model["assembled_bounds"] = [[min(p[i] for p in lows) for i in range(3)], [max(p[i] for p in highs) for i in range(3)]]
            stages = []
            for part in available:
                if part["name"].endswith("_scaffolds"):
                    stages.append({"name": "Scaffolds", "model_id": part["id"]})
            for part in available:
                if re.search(r'_part\d+$', part["name"]) and part["id"] not in missing:
                    stages.append({"name": "Construction component " + part["name"].split("_part")[-1], "model_id": part["id"],
                                   "part_number": int(part["name"].split("_part")[-1])})
            stages.append({"name": "Completed", "model_id": base["id"]})
            upgrades = []
            pattern = re.sub(r'^rank\d+', 'rank[0-9]+', re.escape(base["name"]))
            for candidate in records:
                if candidate["source"] == model["source"] and candidate["material_status"] == "source_texture" and re.fullmatch(pattern, candidate["name"]):
                    upgrades.append({"name": candidate["name"].split("_")[0].capitalize(), "model_id": candidate["id"]})
            upgrades.sort(key=lambda s: s["name"])
            model["lifecycle"] = {"stages": stages if len(stages) > 1 else [], "ranks": upgrades if len(upgrades) > 1 else [],
                                  "evidence": evidence, "authored_animation": False}
        summary = {"clips": self.clip_count, "unsupported": [{"source": k, **u} for k, g in self.groups.items() for u in g["unsupported"]],
                   "skin_failures": self.failures}
        (self.output / "motion_report.json").write_text(json.dumps(summary, indent=2))
        print(f"Source animation clips: {self.clip_count}; unsupported: {len(summary['unsupported'])}")
