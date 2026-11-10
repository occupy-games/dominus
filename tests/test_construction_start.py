import json
from pathlib import Path
import struct
import unittest

from tools.house_selection import extract
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class ConstructionStartTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_construction_start.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_whole_start_factory_constructor_and_target_execute(self):
        source=extract()
        for key in ['source_sha256','table_sha256','executable_sha256']:
            self.assertEqual(self.fixture[key],source[key])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(self.fixture['observers'],['0x100bc660','0x10033d20'])
        for address in ['0x10034650','0x1006b2e0','0x100b7580','0x100bb560','0x10124cc0']:
            self.assertIn(address,self.fixture['adapters'])

    def test_payment_failure_and_real_worker_reservation(self):
        for name in ['full','paid_full']:
            case=self.cases[name]
            self.assertFalse(case['started'])
            self.assertIsNone(case['core'])
            self.assertEqual(case['counters'],dict(houses={},plots={},settlements={}))
            self.assertEqual(case['skill_calls'],0)
            self.assertEqual(case['transitions'],[])
            self.assertEqual(len(case['registry']['plots']),1)
        self.assertEqual(self.cases['paid_full']['spending'],[3.75])
        self.assertEqual(self.cases['paid_full']['payment_effects'],[])
        self.assertEqual(self.cases['paid']['payment_effects'],[[1.,1,1]])
        self.assertEqual(self.cases['first']['counters']['houses'],{'0':[0,1,1.]})
        self.assertEqual(self.cases['zero_skill']['counters']['houses'],{'0':[0,1,0.]})
        self.assertEqual(self.cases['freed_slot']['target']['entity'],1)
        self.assertEqual(self.cases['freed_slot']['counters']['houses'],{'1':[0,1,1.]})

    def test_settlement_profession_and_specialized_actions(self):
        self.assertEqual(self.cases['settlement']['counters']['settlements'],{'7':[1,1]})
        self.assertEqual(self.cases['settled']['counters']['settlements'],{})
        self.assertEqual(self.cases['settlement']['core']['fields']['0xec'],'07000000')
        self.assertEqual(self.cases['profession']['core']['fields']['0x20'],'08000000')
        self.assertEqual(self.cases['foreign_profession']['core']['fields']['0x20'],'00000000')
        for name,action,index in [('first',103,18),('farm',108,6),('mine',111,12)]:
            case=self.cases[name]
            self.assertEqual(case['transitions'],[action])
            self.assertEqual(case['request']['index'],index)
            self.assertEqual(case['targets'][0]['action'],250)
            self.assertEqual(case['registry']['plots'],[])

    def test_identity_wrap_and_prior_target_are_not_rewritten(self):
        for name,next_identity in [('identity_high',0x2000000),('identity_wrap',0)]:
            case=self.cases[name]
            self.assertEqual(case['core']['next_identity'],next_identity)
            self.assertEqual(case['target']['identity'],0x01000000)
            self.assertEqual(struct.unpack('<I',bytes.fromhex(case['core']['fields']['0x88']))[0],case['target']['identity'])
        prior=self.cases['prior_plot_target']
        self.assertEqual(prior['skill_calls'],1)
        # The raw start/assignment does not clear the previous reservation.
        # Earlier action lifetime code is responsible for that operation.
        self.assertEqual(prior['counters']['plots'],{'0':[0,1,struct.unpack('<f',struct.pack('<f',.3))[0]]})
        self.assertEqual(prior['target']['identity']>>24,1)

    def test_actual_cost_evaluator_composes_with_full_native_start(self):
        for case in self.fixture['cases']:
            if case.get('native_cost',False):
                self.assertNotIn('0x10235bd0',case['adapters'])
                for address in ['0x1006b4d0','0x10044cb0','0x100bc660','0x10033d20']:
                    self.assertNotIn(address,case['adapters'])
        self.assertEqual(self.cases['source_food']['spending'],[3.])
        self.assertEqual(self.cases['source_first_free']['spending'],[0.])
        self.assertEqual(self.cases['source_settlement_free']['spending'],[0.])
        self.assertEqual(self.cases['source_paid_full']['spending'],[3.])
        self.assertFalse(self.cases['source_paid_full']['started'])
