from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest

from tools.save_game import load, save


class WorldStoreTests(unittest.TestCase):
    def test_sqlite_round_trip_and_corruption_detection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "world.sqlite3"
            payload = {"schema_version": 1, "state": {"tick": 123}, "rng_state": "9223372036854775800"}
            self.assertTrue(save(path, payload)["ok"])
            self.assertEqual(load(path)["data"], payload)
            with closing(sqlite3.connect(path)) as db, db:
                db.execute("UPDATE saves SET payload='{}' WHERE slot=1")
            with self.assertRaisesRegex(ValueError, "damaged"):
                load(path)

    def test_missing_save_does_not_create_an_empty_database(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "missing.sqlite3"
            with self.assertRaisesRegex(ValueError, "No saved world"):
                load(path)
            self.assertFalse(path.exists())
