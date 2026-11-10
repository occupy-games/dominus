import hashlib
import itertools
import json
from pathlib import Path
import struct
import unittest

from tools.native_scenery_oracle import NativeImage

ROOT=Path(__file__).resolve().parents[1]


class SourceTerrainTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_terrain_samples.json').read_text())

    def test_native_code_and_terrain_provenance(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        image=NativeImage(raw)
        fixture=self.fixture
        self.assertEqual(hashlib.sha256(raw).hexdigest(),fixture['executable_sha256'])
        self.assertEqual(hashlib.sha256((ROOT/'game/assets/original/campaign/homeworld6-terrain.bin').read_bytes()).hexdigest(),fixture['terrain_sha256'])
        for address,code in fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(fixture['adapters'],['0x101450b0','0x10338ead','0x1033904e'])
        registration=fixture['script_registration']
        self.assertEqual(image.read(int(registration['address'],16),8).hex(),registration['bytes'])
        name,callback=struct.unpack('<II',bytes.fromhex(registration['bytes']))
        self.assertEqual(image.read(name,15),b'GetStepAtPoint\0')
        self.assertEqual(callback,0x1023f530)
        self.assertEqual(struct.unpack('<d',image.read(0x104a0c78,8))[0],fixture['height_scale'])

    def test_all_corner_patterns_and_independent_native_observations(self):
        fixture=self.fixture
        self.assertEqual({tuple(row['corners']) for row in fixture['cases']},set(itertools.product([0,19,20,25],repeat=4)))
        self.assertEqual(sum(len(bytes.fromhex(c['values'])) for c in fixture['cases']),30976)
        by_corners={tuple(row['corners']):bytes.fromhex(row['values']) for row in fixture['cases']}
        point_index={tuple(point):i for i,point in enumerate(fixture['points'])}
        saddle=by_corners[(0,19,19,0)]
        self.assertEqual(saddle[point_index[(100.125,100.125)]],0)
        self.assertEqual(saddle[point_index[(100.25,100.25)]],19) # Exact diamond boundary belongs to the center.
        self.assertEqual(by_corners[(25,0,0,0)][point_index[(100.25,100.25)]],0)
        self.assertEqual(len(fixture['source_samples']),192)
        self.assertEqual(len(fixture['script_samples']),192)
        for raw,script in zip(fixture['source_samples'],fixture['script_samples']):
            self.assertEqual(raw[:2],script[:2])
            self.assertAlmostEqual(raw[2],script[2],places=4)
        # Native float32 storage/division is observable, not rounded away.
        self.assertIn(29.000001907348633,{s[2] for s in fixture['script_samples']})

    def test_original_map_boundary_observations(self):
        samples={tuple(s[:2]):s[2] for s in self.fixture['edge_samples']}
        self.assertEqual(samples[(-1.25,100)],0)
        self.assertEqual(samples[(-.25,100)],20)
        self.assertEqual(samples[(1022.9999,100)],20)
        self.assertEqual(samples[(1023,100)],0)
