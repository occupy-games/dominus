import json
from pathlib import Path
import unittest

from tools.native_scenery_oracle import NativeImage
from tools.target_references import extract

ROOT = Path(__file__).resolve().parents[1]


class TargetReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'game/assets/original/campaign/target-references.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_target_references.json').read_text())
        cls.cases={case['name']:case['states'] for case in cls.fixture['cases']}

    def test_native_reference_and_counter_instruction_provenance(self):
        self.assertEqual(self.rules,extract())
        self.assertEqual(self.rules['executable_sha256'],self.fixture['executable_sha256'])
        self.assertEqual(self.rules['native_routines'],self.fixture['native_routines'])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(image.read(0x10124b74,len(self.rules['settlement_membership_evidence'])//2).hex(),self.rules['settlement_membership_evidence'])
        self.assertEqual(self.rules['counter_offsets'],dict(houses=dict(assigned=4,workers=0x4004,skill=0x8004),plots=dict(assigned=4,workers=0x1004,skill=0x2004)))
        self.assertEqual(self.fixture['adapters'],['0x10034650','0x10354450'])

    def test_native_target_lifecycle_and_distinct_worker_counter(self):
        assigned,cleared,again=self.cases['house_clear']
        self.assertEqual(assigned['counters']['houses'],{'0':[0,1,1.]})
        self.assertEqual(cleared['counters']['houses'],{})
        self.assertEqual(cleared['target'],dict(identity=0x1f000000,entity=-1,position=[-1.,-1.],flag=True))
        self.assertEqual(again,cleared)
        self.assertEqual(self.cases['reserved_count'][0]['counters']['houses'],{'0':[5,1,1.]})
        self.assertEqual(self.cases['repeated_assignment'][-1]['counters']['houses'],{'0':[0,1,1.]})
        self.assertEqual(self.cases['retain_home_action'][-1]['home'],0)
        self.assertEqual(self.cases['retain_home_action'][-1]['counters']['houses'],{})
        self.assertEqual(self.cases['same_home'][0]['home'],-1)
        self.assertEqual(self.cases['clear_unregistered'][0]['counters']['houses'],{'0':[0,0xffffffff,-1.]})

    def test_plot_validation_and_no_implicit_claim(self):
        self.assertEqual(self.cases['plot'][0]['counters']['plots'],{'0':[0,1,1.]})
        self.assertEqual(self.cases['plot'][0]['plot_claimed'],[False])
        self.assertEqual(self.cases['plot_claimed'][0]['plot_claimed'],[True])
        self.assertEqual(self.cases['plot_distance_equal'][0]['skill_calls'],1)
        self.assertEqual(self.cases['plot_distance_outside'][0]['skill_calls'],0)
        for name in ['moved_plot','null_plot','removed_plot','stale_house','null_house','zero_house_identity','invalid_clear']:
            self.assertEqual(self.cases[name][0]['skill_calls'],0,name)
        self.assertFalse(self.cases['flag_false'][0]['target']['flag'])

    def test_settlement_and_owner_conditions_and_null_bookkeeping(self):
        self.assertEqual(self.cases['new_settlement'][0]['counters']['settlements'],{'3':[1,1]})
        self.assertEqual(self.cases['enter_settlement'][0]['settlement_index'],3)
        self.assertEqual(self.cases['change_settlement'][0]['settlement_index'],3)
        self.assertEqual(self.cases['already_settled'][0]['counters']['settlements'],{})
        self.assertEqual(self.cases['settlement_clear'][-1]['counters']['settlements'],{'3':[1,1]})
        self.assertEqual(self.cases['local_profession_eight'][0]['house_professions'],[8])
        self.assertEqual(self.cases['other_owner_profession_eight'][0]['house_professions'],[0])
        self.assertEqual(self.cases['local_owner_one'][0]['house_professions'],[8])
        for state in self.cases['no_actor']+self.cases['no_actor_clear']:
            self.assertEqual(state['skill_calls'],0)
            self.assertEqual(state['counters'],dict(houses={},plots={},settlements={}))
        self.assertLess(self.cases['changed_skill'][-1]['counters']['houses']['0'][2],0)
