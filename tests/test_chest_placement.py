import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.storm_chests import extract


class ChestPlacementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_chest_placement.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_native_predicate_and_geometry_are_executed(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address in ['0x101521e0','0x101455f0','0x10145670','0x100b64b0','0x1013d3c0','0x1013ca10','0x10357040','0x102d5a90','0x10356f40']:
            self.assertNotIn(address,self.fixture['adapters'])

    def test_original_gates_are_distinct(self):
        self.assertTrue(self.cases['clear']['ok'])
        for name in ['low','high','low_override_cannot_bypass','custom_blocked']:
            self.assertFalse(self.cases[name]['ok'],name)
        for name in ['low_unlocked','high_unlocked','high_override','custom_clear']:
            self.assertTrue(self.cases[name]['ok'],name)
        for category in [0,1,63,64,65,127]:
            self.assertTrue(self.cases[f'restriction_{category}_0.0']['ok'])
            self.assertFalse(self.cases[f'restriction_{category}_0.1']['ok'])
        for category in [128,129,255]:
            self.assertTrue(self.cases[f'restriction_{category}_0.1']['ok'])
        self.assertEqual(self.cases['high_gate_before_objects']['queries'][-1],['unlock','HighMountainSculpt'])
        self.assertEqual(self.cases['custom_order']['queries'][-2:],[['custom',0,160,120],['custom',1,160,120]])

    def test_original_building_corner_and_circular_boundaries(self):
        self.assertTrue(self.cases['building_False_4_157.0_117.0']['ok'])
        self.assertFalse(self.cases['building_True_4_157.0_117.0']['ok'])
        self.assertFalse(self.cases['special_radius_163.99998474121094']['ok'])
        self.assertTrue(self.cases['special_radius_164.0']['ok'])
        self.assertTrue(self.cases['special_radius_164.00001525878906']['ok'])
        self.assertFalse(self.cases['minimum_half']['ok'])


if __name__=='__main__':unittest.main()
