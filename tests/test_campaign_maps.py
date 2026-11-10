import hashlib
import json
from pathlib import Path
import unittest

from tools.campaign import decode_chunk, packed_map, player_starts, stream_hash

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/godus2_4'
OUTPUT = ROOT / 'game/assets/original'


class CampaignMapsTests(unittest.TestCase):
    def test_case_sensitive_stream_names_match_original_pack_keys(self):
        self.assertEqual(stream_hash('terrain_0000'), 0xa3ac09e5)
        self.assertEqual(stream_hash('p1Start'), 0x98fc8bcf)
        self.assertNotEqual(stream_hash('p1Start'), stream_hash('p1start'))
        fields, starts, _, _ = packed_map(SOURCE / 'stream/Homeworld.pack')
        stored = (OUTPUT / 'campaign/homeworld-heights.bin').read_bytes()
        self.assertEqual(fields['terrain'], stored)
        self.assertEqual(player_starts(starts), [{'x': 175, 'z': 166}, {'x': 176, 'z': 162}])
        with self.assertRaises(ValueError):
            player_starts(b'\x01\0\0\0')
        with self.assertRaises(ValueError):
            decode_chunk(b'\x42')

    def test_large_map_inventory_and_all_playable_provenance(self):
        maps = json.loads((OUTPUT / 'campaign/maps.json').read_text())['maps']
        self.assertEqual(maps[0]['id'], 'homeworld')
        available = [m for m in maps if m['available']]
        self.assertEqual([m['name'] for m in available], [
            'Homeworld', 'Homeworld2', 'Homeworld3', 'Homeworld4',
            'Homeworld5', 'Homeworld7', 'Hubworld_01', 'Hubworld_02'])
        fingerprints = set()
        for entry in maps:
            pack = SOURCE / entry['pack_source']
            self.assertEqual(hashlib.sha256(pack.read_bytes()).hexdigest(), entry['pack_sha256'])
            if not entry['available']:
                self.assertTrue(entry['unavailable_reason'])
                continue
            data = json.loads((OUTPUT / entry['definition']).read_text())
            raw = (OUTPUT / data['height_data']).read_bytes()
            self.assertEqual(len(raw), 1024 * 1024)
            self.assertEqual(hashlib.sha256(raw).hexdigest(), entry['height_sha256'])
            self.assertEqual(data['height_sha256'], entry['height_sha256'])
            self.assertNotIn(entry['height_sha256'], fingerprints)
            fingerprints.add(entry['height_sha256'])
            self.assertTrue(data['followers'])
            for start in data['followers']:
                self.assertGreater(raw[start['z'] * 1024 + start['x']], data['sea_level'])
        self.assertFalse(next(m for m in maps if m['name'] == 'Homeworld6')['available'])
        self.assertGreaterEqual(len([m for m in maps if m['family'] == 'Event maps']), 10)
