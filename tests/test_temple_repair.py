import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_repair import extract


class TempleRepairTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_repair.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_original_start_currency_and_work_instructions_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/temple-repair.json').read_text()))
        self.assertEqual(self.fixture['source_sha256'],self.content['source_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertNotIn('0x10062960',self.fixture['adapters'])
        self.assertNotIn('0x10062bb0',self.fixture['adapters'])
        self.assertEqual(self.content['rules']['exponent'],.35)

    def test_start_order_and_native_working_phase(self):
        expected=self.cases['begin_5_0_True']['expected']
        self.assertEqual([e[0] for e in expected['events']],['hook','spending_enabled','spend_food','spend_ore'])
        self.assertTrue(all(e[2]==5 for e in expected['events']))
        self.assertEqual(expected['state']['phase'],6)
        self.assertEqual(self.cases['begin_hook_updates_cost']['expected']['events'][2][1],[7.])
        self.assertEqual(self.cases['begin_6_0_True']['expected']['events'],[])
        self.assertEqual(self.cases['begin_7_0_True']['expected']['events'],[])

    def test_full_completion_protocol_and_deferred_rewards(self):
        complete=self.cases['work_exact']['expected']
        self.assertEqual(complete['state']['phase'],7)
        self.assertEqual(complete['state']['references'],[])
        self.assertEqual(complete['state']['reward_pending'],1)
        self.assertEqual(self.cases['work_under']['expected']['state']['phase'],6)
        self.assertEqual(self.cases['work_no_reward']['expected']['events'][-1],['unlock',['TEMPLE_COMPLETE_1012'],7])
        self.assertEqual(self.cases['work_visual_clears_reward']['expected']['events'][-1],['unlock',['TEMPLE_COMPLETE_1012'],7])
        ark=self.cases['work_ark']['expected']['events']
        self.assertEqual([e[1][0] for e in ark if e[0]=='transition'],[11,13])
        self.assertEqual([e[1][1] for e in ark if e[0]=='transition'],[118,118])
        self.assertFalse(any(e[0]=='completion_notice' for e in self.cases['work_mode1']['expected']['events']))


if __name__=='__main__':unittest.main()
