from contextlib import closing
import contextlib
import io
import json
from pathlib import Path
import sqlite3
import struct
import tempfile
import unittest

from tools.assets import build_library, digest, extract, identify, inventory, pack_entries


class AssetPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.catalog = self.root / "catalog/catalog.sqlite3"
        self.output = self.root / "output"
        self.selection = self.root / "selection.json"
        # Only the signature matters to inventory; actual decoding is checked in Godot.
        self.image = b"\x89PNG\r\n\x1a\n" + b"sample"
        (self.source / "texture").write_bytes(self.image)
        self.selection.write_text(json.dumps({"assets": [{"path": "texture", "role": "test"}]}))

    def inventory(self):
        with contextlib.redirect_stdout(io.StringIO()):
            inventory(self.source, self.catalog)

    def extract(self):
        with contextlib.redirect_stdout(io.StringIO()):
            extract(self.source, self.catalog, self.output, self.selection)

    def test_extensionless_assets_duplicates_and_repeatability(self):
        (self.source / "duplicate.png").write_bytes(self.image)
        (self.source / "unknown").write_bytes(b"\x00\xff\x00\xff")
        self.inventory()
        first = (self.catalog.parent / "inventory.json").read_bytes()
        self.inventory()
        self.assertEqual(first, (self.catalog.parent / "inventory.json").read_bytes())
        with closing(sqlite3.connect(self.catalog)) as db:
            self.assertEqual(db.execute("SELECT format FROM assets WHERE path='texture'").fetchone()[0], "png")
            self.assertEqual(db.execute("SELECT COUNT(*) FROM assets").fetchone()[0], 3)
        self.extract()
        self.assertEqual(digest(self.output / "texture.png"), digest(self.source / "texture"))
        manifest = (self.output / "manifest.json").read_bytes()
        self.extract()
        self.assertEqual(manifest, (self.output / "manifest.json").read_bytes())

    def test_stale_source_fails_before_extraction(self):
        self.inventory()
        (self.source / "texture").write_bytes(self.image + b"changed")
        with self.assertRaisesRegex(ValueError, "source changed"):
            self.extract()
        self.assertFalse(self.output.exists())

    def test_output_cannot_overwrite_source(self):
        self.inventory()
        self.output = self.source / "extracted"
        with self.assertRaisesRegex(ValueError, "non-nested"):
            self.extract()

    def test_output_symlink_cannot_escape(self):
        self.inventory()
        self.output.mkdir()
        other = self.root / "other.png"
        other.write_bytes(b"keep")
        (self.output / "texture.png").symlink_to(other)
        with self.assertRaisesRegex(ValueError, "unsafe output"):
            self.extract()
        self.assertEqual(other.read_bytes(), b"keep")

    def test_pack_table_and_bounds(self):
        pack = self.root / "test.pack"
        pack.write_bytes(struct.pack("<IIII", 1, 123, 16, 3) + b"abc")
        self.assertEqual(pack_entries(pack)[0]["size"], 3)
        pack.write_bytes(struct.pack("<IIII", 1, 123, 16, 4) + b"abc")
        with self.assertRaisesRegex(ValueError, "outside"):
            pack_entries(pack)
        pack.write_bytes(struct.pack("<I", 2) + struct.pack("<III", 1, 28, 4) + struct.pack("<III", 2, 30, 4) + b"abcdef")
        with self.assertRaisesRegex(ValueError, "overlapping"):
            pack_entries(pack)

    def test_extensions_do_not_override_signatures(self):
        self.assertEqual(identify(b"not a png", ".png")[0], "text")
        self.assertEqual(identify(b"\x00\xff\x00\xff", ".mp3")[0], "unknown")

    def test_library_includes_unsupported_assets_and_bounded_excerpts(self):
        (self.source / "unknown.bin").write_bytes(b"\x00\xff" * 5000)
        (self.source / "rules.csv").write_text("name,value\n" + "x,1\n" * 2000)
        self.inventory()
        with contextlib.redirect_stdout(io.StringIO()):
            build_library(self.source, self.catalog, self.output)
        first = (self.output.parent / "library/catalog.json").read_bytes()
        catalog = json.loads(first)
        records = {r["path"]: r for r in catalog["assets"]}
        self.assertEqual(len(records), 3)
        self.assertEqual(catalog["preview_count"], 1)
        self.assertEqual(records["texture"]["preview"], "texture.png")
        self.assertEqual(records["unknown.bin"]["preview"], "")
        self.assertEqual(len(records["unknown.bin"]["hex_excerpt"].split()), 128)
        self.assertEqual(len(records["rules.csv"]["text_excerpt"]), 4096)
        self.assertTrue(records["rules.csv"]["excerpt_truncated"])
        with contextlib.redirect_stdout(io.StringIO()):
            build_library(self.source, self.catalog, self.output)
        self.assertEqual(first, (self.output.parent / "library/catalog.json").read_bytes())


if __name__ == "__main__":
    unittest.main()
