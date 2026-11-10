#!/usr/bin/env python3
"""SQLite save adapter used by the local Godot prototype (no third-party modules)."""
import hashlib
import base64
import json
from pathlib import Path
import sqlite3
import sys
from contextlib import closing


def save(path, payload):
    if payload.get("schema_version") != 1 or not isinstance(payload.get("state"), dict):
        raise ValueError("Unsupported save version or missing world state")
    encoded = json.dumps(payload, separators=(",", ":"), allow_nan=False)
    checksum = hashlib.sha256(encoded.encode()).hexdigest()
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(path)) as db, db:
        db.execute("CREATE TABLE IF NOT EXISTS saves (slot INTEGER PRIMARY KEY, version INTEGER NOT NULL, payload TEXT NOT NULL, sha256 TEXT NOT NULL)")
        db.execute("INSERT OR REPLACE INTO saves VALUES (1,1,?,?)", (encoded, checksum))
    return {"ok": True}


def load(path):
    path = Path(path).resolve()
    if not path.is_file():
        raise ValueError("No saved world yet")
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as db:
        row = db.execute("SELECT version,payload,sha256 FROM saves WHERE slot=1").fetchone()
    if not row or row[0] != 1 or hashlib.sha256(row[1].encode()).hexdigest() != row[2]:
        raise ValueError("Saved world is missing, incompatible, or damaged")
    return {"ok": True, "data": json.loads(row[1])}


if __name__ == "__main__":
    try:
        if len(sys.argv) < 3 or sys.argv[1] not in ("save", "load"):
            raise ValueError("Expected save <database> <base64-json> or load <database>")
        if sys.argv[1] == 'save':
            payload = json.loads(Path(sys.argv[4]).read_text()) if sys.argv[3] == '--json-file' else json.loads(base64.b64decode(sys.argv[3], validate=True))
            result = save(sys.argv[2], payload)
        else: result = load(sys.argv[2])
        print(json.dumps(result, allow_nan=False))
    except (ValueError, OSError, sqlite3.Error, IndexError) as error:
        print(json.dumps({"ok": False, "message": str(error)}))
        raise SystemExit(1)
