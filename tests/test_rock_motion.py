import hashlib
import json
from pathlib import Path
import unittest

from tools.rock_motion import extract
from tools.native_scenery_oracle import NativeImage

ROOT=Path(__file__).resolve().parents[1]


class RockMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_rock_motion.json').read_text())

    def test_native_configuration_and_instruction_provenance(self):
        data=extract()
        self.assertEqual(data,self.fixture['configuration'])
        self.assertEqual(data,json.loads((ROOT/'game/assets/original/campaign/rock-motion.json').read_text()))
        self.assertEqual(data['duration'],1.)
        self.assertEqual(data['duration_evidence']['data'],'0x105da89c')
        self.assertEqual(data['capacity'],12)
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),data['executable_sha256'])
        image=NativeImage(raw)
        for address,code in data['native_routines'].items(): self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(self.fixture['adapters'],['0x10144780','0x10144790','0x101450b0','0x1035f830'])

    def test_native_motion_boundaries_and_full_pool_behavior(self):
        cases={c['name']:c for c in self.fixture['cases']}
        self.assertEqual(len(cases),8)
        self.assertEqual(cases['raise']['states'][0]['heights'],[6.090000152587891])
        self.assertEqual(len(cases['exact_duration']['states'][3]['queue']),1)
        self.assertEqual(cases['exact_duration']['states'][4]['queue'],[])
        self.assertEqual(len(cases['capacity']['states'][0]['queue']),12)
        # The original full-pool path reuses record zero in-place. Its previous
        # object remains at its last height; the thirteenth object takes over.
        queue=cases['capacity']['states'][0]['queue']
        self.assertEqual([r['object'] for r in queue],list(range(11,0,-1))+[12])
        self.assertEqual(cases['capacity']['states'][-1]['heights'][0],6.)
        self.assertEqual(len(cases['tile_boundary']['tiles']),4)
        self.assertEqual(len(cases['tile_boundary']['states'][0]['queue']),1)
