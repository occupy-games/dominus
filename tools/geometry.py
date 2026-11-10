"""Strict reader for the observed single-mesh/single-material Marmalade text subset.

No binary .group.bin interpretation is attempted. Source coordinates/scale are
retained; the viewer applies one common fit transform to an entire assembly.
"""
from pathlib import Path
import math
import re


def read_geo(text):
    text = re.sub(r"//[^\n]*", "", text)
    keys = set(re.findall(r"^\s*([A-Za-z][A-Za-z0-9]*)\b", text, re.M))
    allowed = {"CIwModel", "CMesh", "CVerts", "CVertNorms", "CUVs", "CSurface", "CTris", "CQuads",
               "name", "scale", "numVerts", "numVertNorms", "numUVs", "numTris", "numQuads",
               "material", "setID", "v", "vn", "uv", "t", "q"}
    if keys - allowed or len(re.findall(r"\bCMesh\b", text)) != 1 or len(re.findall(r"\bCSurface\b", text)) != 1:
        raise ValueError("only one mesh and one surface with the observed fields are supported")
    if re.findall(r"\bsetID\s+(\d+)", text) != ["0"]:
        raise ValueError("exactly one UV set (0) is required")
    names = re.findall(r'\bname\s+"([^"]+)"', text)
    material = re.findall(r'\bmaterial\s+"([^"]+)"', text)
    scales = re.findall(r"\bscale\s+([-+\d.eE]+)", text)
    if len(names) != 2 or len(material) != 1 or len(scales) != 1:
        raise ValueError("missing model, mesh, material or scale")
    result = {"name": names[1], "source_scale": float(scales[0]), "material": material[0]}
    for key, tag, count_key, width in [("vertices", "v", "numVerts", 3), ("normals", "vn", "numVertNorms", 3), ("uvs", "uv", "numUVs", 2)]:
        values = [[float(n.strip()) for n in row.split(",")] for row in re.findall(r"^\s*" + tag + r"\s*\{([^}]+)\}", text, re.M)]
        counts = re.findall(r"\b" + count_key + r"\s+(\d+)", text)
        if len(counts) != 1 or len(values) != int(counts[0]) or not values or any(len(v) != width or not all(math.isfinite(x) for x in v) for v in values):
            raise ValueError("invalid " + key + " count or values")
        result[key] = values
    result["triangles"] = []
    for tag, width, count_key in [("t", 3, "numTris"), ("q", 4, "numQuads")]:
        rows = re.findall(r"^\s*" + tag + r"\s+([^\n]+)", text, re.M)
        counts = re.findall(r"\b" + count_key + r"\s+(\d+)", text)
        if rows and (len(counts) != 1 or len(rows) != int(counts[0])):
            raise ValueError("invalid face count")
        if counts and len(rows) != int(counts[0]):
            raise ValueError("missing faces")
        for row in rows:
            corners = [[int(n.strip()) for n in group.split(",")] for group in re.findall(r"\{([^}]+)\}", row)]
            if len(corners) != width or any(len(c) != 5 or c[3:] != [-1, -1] for c in corners):
                raise ValueError("unsupported face attributes")
            for corner in corners:
                for index, key in zip(corner[:3], ["vertices", "normals", "uvs"]):
                    if not 0 <= index < len(result[key]):
                        raise ValueError("face index out of bounds")
            result["triangles"].append([c[:3] for c in corners[:3]])
            if width == 4:
                result["triangles"].append([corners[i][:3] for i in (0, 2, 3)])
    if not result["triangles"] or not math.isfinite(result["source_scale"]) or result["source_scale"] <= 0:
        raise ValueError("empty mesh or invalid scale")
    return result


def assemblies_from_records(source, records):
    """Group proven sibling parts by model stem and shared Maya source reference."""
    by_path = {r["path"].casefold(): r for r in records}
    groups, failures = {}, []
    for record in records:
        if record["format"] != "marmalade_geo_text":
            continue
        relative = Path(record["path"])
        try:
            text = (source / relative).read_text()
            part = read_geo(text)
            material_record = by_path.get(relative.with_suffix(".mtl").as_posix().casefold())
            if material_record is None:
                raise ValueError("material file missing")
            material_text = (source / material_record["path"]).read_text()
            texture_names = re.findall(r'\btexture0\s+"([^"]+)"', material_text)
            if len(texture_names) != 1 or Path(texture_names[0]).name != texture_names[0]:
                raise ValueError("unsupported texture reference")
            material_names = re.findall(r'\bname\s+"([^"]+)"', material_text)
            if len(material_names) != 1 or material_names[0].split("/")[-1] != part["material"]:
                raise ValueError("material name mismatch")
            texture_record = None
            for parent in [relative.parent, relative.parent / "textures"]:
                texture_record = by_path.get((parent / texture_names[0]).as_posix().casefold())
                if texture_record:
                    break
            if not texture_record or not texture_record.get("preview"):
                raise ValueError("texture missing or not extracted")
            base = re.sub(r"_(?:part\d+|shadow)$", "", relative.stem)
            origin = re.findall(r"// Source file:\s*([^\r\n]+)", text)
            if len(origin) != 1:
                raise ValueError("source model identity missing")
            key = (relative.parent.as_posix(), base, origin[0])
            part.update({"source": record["path"], "material_source": material_record["path"],
                         "texture_source": texture_record["path"], "texture": texture_record["preview"]})
            groups.setdefault(key, []).append(part)
        except (ValueError, OSError) as error:
            failures.append({"source": record["path"], "reason": str(error)})
    assemblies = []
    for (directory, base, origin), parts in sorted(groups.items()):
        # Different per-mesh scale semantics have not been established yet.
        if len({p["source_scale"] for p in parts}) != 1:
            failures.append({"source": directory + "/" + base, "reason": "mixed source scales are unsupported"})
            continue
        assemblies.append({"id": directory + "/" + base, "name": Path(origin.replace("\\", "/")).stem,
                           "origin": origin, "parts": sorted(parts, key=lambda p: p["source"]),
                           "assembly_evidence": "shared source model reference and matching sibling model stems"})
    return assemblies, failures
