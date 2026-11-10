import json
from pathlib import Path
import unittest

from tools.build_start import extract
from tools.house_selection import extract as selection
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class BuildStartTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'game/assets/original/campaign/build-start.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_build_start.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_native_start_and_reference_helpers_execute_unchanged(self):
        self.assertEqual(self.rules,extract())
        source=selection()
        for key in ['source_sha256','table_sha256','executable_sha256']:
            self.assertEqual(source[key],self.fixture[key])
        self.assertEqual(self.rules['native_routines'],self.fixture['native_routines'])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address in [0x10044cb0,0x100b72c0,0x10237660,0x10044110]:
            self.assertNotIn(hex(address),self.fixture['adapters'])
        # The complete constructor, cost evaluator and action/path transition
        # remain explicit dependencies; these are not full-job observations.
        for address in [0x100bc660,0x10235bd0,0x1006b2e0,0x10033d20]:
            self.assertIn(hex(address),self.fixture['adapters'])
        self.assertEqual(self.rules['rules'],dict(builder_action=103,farmer_action=108,miner_action=111,target_action=250,half=.5))

    def test_source_charges_before_failed_allocation_without_refund(self):
        failed=self.cases['paid_failure']
        self.assertFalse(failed['started'])
        self.assertEqual(failed['operations'],['settlement','food_enabled','cost',['spend',3.75],'allocate'])
        self.assertEqual(len(failed['registry']['plots']),1)
        for key in ['targets','transitions','effects','rectangles','dirty']:
            self.assertEqual(failed[key],[])
        self.assertIn(['spend',0.],self.cases['free']['operations'])
        self.assertNotIn('payment_effect_finish',self.cases['free']['operations'])
        self.assertIn(['spend',-1.],self.cases['negative_cost']['operations'])

    def test_specialization_actions_settlement_and_biome_gates(self):
        for name,action,settlement in [('farm',108,9),('mine',111,13),('special_abode',103,5)]:
            case=self.cases[name]
            self.assertEqual(case['transitions'],[action])
            self.assertEqual(case['attachments'],[[0,settlement]])
            self.assertEqual(case['operations'][0],'food_enabled')
            self.assertNotIn('settlement',case['operations'])
            self.assertNotIn('cost',case['operations'])
            self.assertEqual(case['request']['index'],0)
        self.assertEqual(self.cases['farm_biome_unlocked']['request']['index'],6)
        self.assertEqual(self.cases['mine_biome_unlocked']['request']['index'],12)
        self.assertEqual(self.cases['settlement']['attachments'],[[0,7]])
        self.assertEqual(self.cases['first']['targets'][0]['position'],[-1.,-1.])
        self.assertEqual(self.cases['first']['effects'],[[4294967295,5,1]])
