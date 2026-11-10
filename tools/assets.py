#!/usr/bin/env python3
"""Local, dependency-free inventory and extraction of the supplied the original source assets."""
import argparse
from contextlib import closing
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import struct

try:
    from .geometry import assemblies_from_records
except ImportError:
    from geometry import assemblies_from_records

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/godus2_4"
CATALOG = ROOT / "build/assets/catalog.sqlite3"
OUTPUT = ROOT / "game/assets/extracted"
DIRECT = {"png": ".png", "jpeg": ".jpg", "tga": ".tga", "dds": ".dds", "mp3": ".mp3",
          "ogg": ".ogg", "wav": ".wav", "ttf": ".ttf", "otf": ".otf"}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def identify(head, suffix):
    """Return format, category, and evidence; weak classifications stay explicit."""
    signatures = [
        (b"\x89PNG\r\n\x1a\n", "png", "texture"), (b"\xff\xd8\xff", "jpeg", "texture"),
        (b"DDS ", "dds", "texture"), (b"OggS", "ogg", "audio"),
        (b"ID3", "mp3", "audio"), (b"\x00\x01\x00\x00", "ttf", "font"),
        (b"OTTO", "otf", "font"), (b"BKHD", "wwise_bank", "audio"),
        (b"AKPK", "wwise_package", "audio"), (b"FWS", "swf", "ui"),
        (b"CWS", "swf_zlib", "ui"), (b"GFX", "scaleform", "ui"),
        (b"\x3d\x03\x07\x01", "marmalade_group", "mesh_container"),
    ]
    for magic, fmt, category in signatures:
        if head.startswith(magic):
            return fmt, category, "signature"
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return "wav", "audio", "signature"
    # Check MPEG audio frame sync, version, layer, bitrate, and sampling rate.
    if len(head) >= 4 and head[0] == 255 and head[1] & 224 == 224:
        if (head[1] >> 3) & 3 != 1 and (head[1] >> 1) & 3 == 1 and 0 < head[2] >> 4 < 15 and (head[2] >> 2) & 3 != 3:
            return "mp3", "audio", "frame_header"
    # TGA has no leading magic: accept only .tga with a supported header.
    if suffix == ".tga" and len(head) >= 18:
        w, h = struct.unpack_from("<HH", head, 12)
        if head[1] == 0 and head[2] in (2, 3, 10, 11) and w and h and head[16] in (8, 16, 24, 32):
            return "tga", "texture", "header_and_extension"
    if b"CIwModel" in head:
        return "marmalade_geo_text", "mesh", "text_marker"
    if b"CIwMaterial" in head:
        return "marmalade_material_text", "material", "text_marker"
    if head and b"\x00" not in head:
        try:
            head.decode("utf-8")
            fmt, category = {".csv": ("csv", "configuration"), ".lua": ("lua", "script"),
                             ".strings": ("strings", "localization")}.get(suffix, ("text", "text"))
            return fmt, category, "utf8_sample"
        except UnicodeDecodeError:
            pass
    return "unknown", "unknown", "unresolved"


def pack_entries(path):
    """Observed stream .pack layout: LE count, then (hash, offset, size) triples.

    No interpretation of payloads or hash-to-name mapping is implied.
    Reject tables whose extents do not fit the file or overlap.
    """
    size = path.stat().st_size
    with path.open("rb") as stream:
        head = stream.read(4)
        if len(head) != 4:
            raise ValueError("truncated pack count")
        count, = struct.unpack("<I", head)
        if not 0 < count <= (size - 4) // 12:
            raise ValueError("invalid pack count")
        table_end = 4 + count * 12
        entries = []
        for i in range(count):
            key, offset, length = struct.unpack("<III", stream.read(12))
            if offset < table_end or offset + length > size:
                raise ValueError(f"entry {i} outside payload region")
            entries.append({"index": i, "key": f"{key:08x}", "offset": offset, "size": length})
        end = table_end
        for entry in sorted(entries, key=lambda e: e["offset"]):
            if entry["offset"] < end:
                raise ValueError("overlapping pack entries")
            end = entry["offset"] + entry["size"]
        return entries


def check_separate(source, destination):
    source, destination = source.resolve(), destination.resolve()
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError("source and output must be separate, non-nested directories")


def inventory(source, catalog):
    if not source.is_dir():
        raise ValueError(f"source directory missing: {source}")
    check_separate(source, catalog.parent)
    catalog.parent.mkdir(parents=True, exist_ok=True)
    rows, packs = [], []
    for path in sorted(source.rglob("*")):
        if not path.is_file() or path.is_symlink() or path.name == ".DS_Store":
            continue
        with path.open("rb") as stream:
            head = stream.read(4096)
        fmt, category, evidence = identify(head, path.suffix.lower())
        name = path.relative_to(source).as_posix()
        rows.append((name, path.stat().st_size, digest(path), "".join(path.suffixes).lower(),
                     head[:16].hex(), fmt, category, evidence))
        if path.suffix == ".pack":
            try:
                entries = pack_entries(path)
                packs.append({"path": name, "status": "validated_table", "entries": entries})
            except ValueError as error:
                packs.append({"path": name, "status": "unsupported", "reason": str(error)})
    with closing(sqlite3.connect(catalog)) as db, db:
        db.executescript("""
            DROP TABLE IF EXISTS assets;
            DROP TABLE IF EXISTS metadata;
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE assets (
                path TEXT PRIMARY KEY, size INTEGER NOT NULL, sha256 TEXT NOT NULL,
                extension TEXT NOT NULL, signature TEXT NOT NULL, format TEXT NOT NULL,
                category TEXT NOT NULL, evidence TEXT NOT NULL);
            CREATE INDEX assets_hash ON assets(sha256);
            CREATE INDEX assets_format ON assets(format);
        """)
        db.executemany("INSERT INTO assets VALUES (?,?,?,?,?,?,?,?)", rows)
        db.executemany("INSERT INTO metadata VALUES (?,?)", [("schema_version", "1"), ("source_root", str(source.resolve()))])
    hashes = defaultdict(list)
    for row in rows:
        hashes[row[2]].append(row[0])
    summary = {"schema_version": 1, "files": len(rows), "bytes": sum(r[1] for r in rows),
               "formats": dict(sorted(Counter(r[5] for r in rows).items())),
               "categories": dict(sorted(Counter(r[6] for r in rows).items())),
               "duplicate_groups": [v for v in hashes.values() if len(v) > 1],
               "packs": packs}
    (catalog.parent / "inventory.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Cataloged {len(rows)} files ({summary['bytes']:,} bytes) into {catalog}")
    print(f"Formats: {summary['formats']}")


def extract(source, catalog, output, selection, all_direct=False):
    check_separate(source, output)
    check_separate(catalog.parent, output)
    if not catalog.is_file():
        raise ValueError("catalog missing; run inventory first")
    with closing(sqlite3.connect(catalog)) as db, db:
        db.row_factory = sqlite3.Row
        root = db.execute("SELECT value FROM metadata WHERE key='source_root'").fetchone()
        if not root or root[0] != str(source.resolve()):
            raise ValueError("catalog belongs to another source root; rerun inventory")
        assets = {r["path"]: dict(r) for r in db.execute("SELECT * FROM assets ORDER BY path")}
    requested = ([{"path": p, "role": "unassigned"} for p, r in assets.items() if r["format"] in DIRECT]
                 if all_direct else json.loads(selection.read_text())["assets"])
    staged = []
    # Validate every source before writing anything, including catalog staleness.
    for item in requested:
        name = item["path"]
        row = assets.get(name)
        if row is None or row["format"] not in DIRECT:
            raise ValueError(f"missing or unsupported direct asset: {name}")
        original = source / name
        if not original.resolve().is_relative_to(source.resolve()) or original.is_symlink():
            raise ValueError(f"unsafe source path: {name}")
        if digest(original) != row["sha256"]:
            raise ValueError(f"source changed since inventory: {name}")
        target_name = name if Path(name).suffix.lower() == DIRECT[row["format"]] else name + DIRECT[row["format"]]
        target = output / target_name
        if not target.resolve().is_relative_to(output.resolve()):
            raise ValueError(f"unsafe output path: {target_name}")
        staged.append((original, target, {"source": name, "output": target_name, "role": item["role"],
                                        "format": row["format"], "sha256": row["sha256"],
                                        "operation": "copy", "settings": {},
                                        "dependencies": item.get("dependencies", [])}))
    for original, target, record in staged:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
        if digest(target) != record["sha256"]:
            raise ValueError(f"copy verification failed: {target}")
    output.mkdir(parents=True, exist_ok=True)
    (output / "manifest.json").write_text(json.dumps({"schema_version": 1, "assets": [r for _, _, r in staged]}, indent=2) + "\n")
    print(f"Extracted and verified {len(staged)} assets into {output}")


def build_library(source, catalog, output):
    """Stage supported resources and export every catalog entry for the viewer."""
    library = output.parent / "library"
    check_separate(source, library)
    check_separate(output, library)
    extract(source, catalog, output, None, all_direct=True)
    manifest = json.loads((output / "manifest.json").read_text())
    previews = {a["source"]: a["output"] for a in manifest["assets"]}
    with closing(sqlite3.connect(catalog)) as db, db:
        db.row_factory = sqlite3.Row
        records = [dict(row) for row in db.execute("SELECT * FROM assets ORDER BY path")]
    text_formats = {"text", "csv", "lua", "strings", "marmalade_geo_text", "marmalade_material_text"}
    for record in records:
        path = source / record["path"]
        if not path.resolve().is_relative_to(source.resolve()) or path.is_symlink():
            raise ValueError(f"unsafe library source: {record['path']}")
        if digest(path) != record["sha256"]:
            raise ValueError(f"source changed since inventory: {record['path']}")
        with path.open("rb") as stream:
            head = stream.read(4096)
        record["preview"] = previews.get(record["path"], "")
        record["hex_excerpt"] = head[:128].hex(" ")
        record["text_excerpt"] = head.decode("utf-8", errors="replace") if record["format"] in text_formats else ""
        record["excerpt_truncated"] = record["size"] > len(head)
    library.mkdir(parents=True, exist_ok=True)
    assemblies, assembly_failures = assemblies_from_records(source, records)
    model_dir = library / "models"
    model_dir.mkdir(exist_ok=True)
    descriptors = []
    for assembly in assemblies:
        filename = hashlib.sha256(assembly["id"].encode()).hexdigest()[:24] + ".json"
        (model_dir / filename).write_text(json.dumps(assembly, indent=2) + "\n")
        descriptors.append({"id": assembly["id"], "name": assembly["name"], "model": "models/" + filename,
                            "parts": [{k: p[k] for k in ("name", "source", "material_source", "texture_source")} for p in assembly["parts"]]})
        sources = {p["source"] for p in assembly["parts"]}
        for record in records:
            if record["path"] in sources:
                record["assembly"] = assembly["id"]
    payload = {"schema_version": 1, "assets": records, "preview_count": len(previews),
               "assemblies": descriptors, "assembly_failures": assembly_failures}
    (library / "catalog.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(f"Library: {len(records)} entries, {len(previews)} media, {len(assemblies)} assembled objects")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["inventory", "extract", "library"])
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--selection", type=Path, default=ROOT / "assets/selection.json")
    parser.add_argument("--all-direct", action="store_true", help="copy all recognized image/audio/font assets")
    args = parser.parse_args()
    try:
        if args.command == "inventory":
            inventory(args.source.resolve(), args.catalog.resolve())
        elif args.command == "extract":
            extract(args.source.resolve(), args.catalog.resolve(), args.output.resolve(), args.selection, args.all_direct)
        else:
            build_library(args.source.resolve(), args.catalog.resolve(), args.output.resolve())
    except (OSError, ValueError, sqlite3.Error, KeyError) as error:
        parser.exit(1, f"Asset pipeline failed: {error}\n")


if __name__ == "__main__":
    main()
