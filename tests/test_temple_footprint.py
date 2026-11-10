import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_terrain import extract


class TempleFootprintTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_footprint.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_actual_scan_and_decay_instructions_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.fixture['native_routines'],self.content['native_routines'])
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x1003b550','0x10140ded','0x10357040','0x1035f840']:self.assertNotIn(address,self.fixture['adapters'])
        self.assertIn('0x101450b0',self.fixture['adapters'])

    def test_height_tolerance_and_source_footprint_rounding(self):
        self.assertEqual(self.cases['threshold_20.099998474121094']['expected']['count'],0)
        self.assertEqual(self.cases['threshold_20.100000381469727']['expected']['count'],2)
        self.assertEqual(self.cases['grid_0_-0.75_21']['expected']['queries'],[])
        samples=self.cases['grid_4_0_21']['expected']['queries']
        self.assertEqual(samples[0][:2],[8,10])
        self.assertEqual(samples[-1][:2],[11,13])
        self.assertEqual(len(samples),16)

    def test_composed_sequences_use_recomputed_obstruction(self):
        self.assertEqual(len(self.fixture['cases']),162)
        self.assertEqual(len(self.fixture['composed']),56)
        for sequence in self.fixture['sequences']:
            blocked=sequence['steps'][0]['expected']['state']
            restored=sequence['steps'][3]['expected']['state']
            self.assertEqual((blocked['phase'],blocked['obstruction']),(8,1))
            self.assertEqual((restored['phase'],restored['obstruction']),(6,0))
            self.assertLess(restored['progress'],blocked['progress'])
            self.assertEqual(len(sequence['steps']),24)


if __name__=='__main__':unittest.main()
