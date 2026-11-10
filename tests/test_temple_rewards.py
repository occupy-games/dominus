import hashlib
import json
import unittest

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


class TempleRewardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_rewards.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_original_marker_wrapper_and_deferred_branch_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        for address in ['0x1015cd60','0x10140b9c','0x1015c7f0','0x1015c640']:
            self.assertIn(address,self.fixture['native_routines'])
            self.assertNotIn(address,self.fixture['adapters'])
        for address in ['0x10001870','0x100016e0','0x10001360']:
            self.assertNotIn(address,self.fixture['adapters'])
            self.assertTrue(any(int(a,16)<=int(address,16)<int(a,16)+len(code)//2 for a,code in self.fixture['native_routines'].items()))
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)

    def test_markers_keep_one_count_but_repeat_original_notifications(self):
        case=self.cases['marker_1012'];identity='@'+str(key('TEMPLE_COMPLETE_1012'))
        for state in case['states']:
            self.assertEqual(state['availability']['acquired'][identity],1)
            self.assertEqual(state['unlock_state']['first_seen'][identity],123)
        self.assertEqual([e for e in case['states'][0]['events'] if e[0]=='notify'],[e for e in case['states'][1]['events'] if e[0]=='notify'])
        sites=json.loads((ROOT/'game/assets/original/campaign/temple-sites.json').read_text())['scopes']['initialworldsetup6']
        for site in sites:self.assertIn('marker_'+site['id'],self.cases)

    def test_original_gate_is_not_an_unknown_key_rejection(self):
        case=self.cases['gate_True_False']
        self.assertFalse(case['states'][0]['value'])
        self.assertEqual(case['states'][0]['events'],[])
        self.assertEqual(case['states'][0]['availability'],case['availability'])
        self.assertTrue(self.cases['gate_False_False']['states'][0]['value'])
        self.assertTrue(self.cases['gate_True_True']['states'][0]['value'])

    def test_failed_credit_does_not_reverse_the_claim_or_wrapper_result(self):
        case=self.cases['capacity_0_0'];identity='@'+str(key('TEMPLE_COMPLETE_1012'))
        self.assertTrue(case['states'][0]['value'])
        self.assertEqual(case['states'][0]['availability']['acquired'][identity],0)
        self.assertEqual(case['states'][0]['availability']['stock_limits'][identity],0)
        self.assertIn(identity,case['states'][0]['unlock_state']['received'])

    def test_all_original_packs_deliver_only_once_from_pending_flags(self):
        cases=[c for c in self.fixture['cases'] if c['name'].startswith('pending_Pack_')]
        self.assertEqual(len(cases),14)
        for case in cases:
            first,again=case['states'][1:3]
            self.assertTrue(first['value'])
            self.assertFalse(first['temple']['reward_ready'])
            self.assertEqual(first['temple']['reward_pending'],0)
            self.assertFalse(again['value'])
            self.assertEqual(first['availability'],again['availability'])
            self.assertEqual(first['state'],again['state'])
            self.assertEqual(first['random_calls'],again['random_calls'])
        self.assertFalse(self.cases['not_discovery']['states'][0]['value'])
        self.assertTrue(self.cases['zero_reward']['states'][0]['value'])
        self.assertTrue(self.cases['blocked_phase']['states'][0]['value'])


if __name__=='__main__':unittest.main()
