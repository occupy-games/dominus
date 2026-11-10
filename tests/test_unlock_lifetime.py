import hashlib
import json
import unittest

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


class UnlockLifetimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_unlock_lifetime.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_actual_rebuild_expiry_and_map_traversal_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        for address in ['0x1015cdb0','0x1015cf20','0x1015c640','0x1015c7f0']:
            self.assertIn(address,self.fixture['native_routines'])
            self.assertNotIn(address,self.fixture['adapters'])
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertIn('0x1015bd70',self.fixture['adapters']) # Numeric effect restoration is a distinct service.
        self.assertIn('0x10172220',self.fixture['adapters'])
        self.assertNotIn('0x10352ed0',self.fixture['adapters']) # Actual tree successor executes.

    def test_rebuild_restores_before_replay_and_preserves_first_seen(self):
        case=self.cases['bucket_chain_replay_order']
        for state in case['states']:
            self.assertEqual(state['events'],[['reset_modifiers',[]],['reset_configuration',[]],['notify',[103]],['notify',[102]],['notify',[101]],['notify',[100]]])
            self.assertEqual(state['state']['first_seen'],case['state']['first_seen'])
            self.assertEqual(state['state']['first_seen_order'],case['state']['first_seen_order'])
            self.assertFalse(state['state']['registered'])
            self.assertTrue(all(r['phase']==1 for r in state['state']['rows']))
        case=self.cases['reset_phase_0']
        self.assertFalse(case['states'][0]['state']['unlocked'])
        self.assertEqual(case['states'][1]['events'][-2:],[['notify',[30]],['notify',[20]]])

    def test_one_expiry_per_call_uses_key_order_and_unsigned_deadlines(self):
        states=self.cases['one_expiry_per_call_in_key_order']['states']
        self.assertEqual([sorted(s['state']['timers']) for s in states],[['@20','@30'],['@30'],[],[]])
        self.assertIn('@31',states[0]['state']['unlocked']) # A due but not yet removed timer is reapplied.
        self.assertEqual(states[-1]['events'],[])
        self.assertTrue(self.cases['boundary_[1001, 0]']['states'][0]['state']['timers'])
        self.assertFalse(self.cases['boundary_[1000, 0]']['states'][0]['state']['timers'])
        self.assertTrue(self.cases['boundary_[0, 2147483648]']['states'][0]['state']['timers'])
        case=self.cases['persistent_replay_can_recreate_dynamic_timer']
        self.assertEqual([s['state']['timers']['@10'] for s in case['states']],[[4000,0],[7000,0],[11000,0]])

    def test_shared_reward_state_survives_real_expiry_and_rebuild(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_lifetime_rewards.json').read_text())
        self.assertNotIn('0x1015cdb0',fixture['adapters'])
        self.assertNotIn('0x1015cf20',fixture['adapters'])
        cases={c['name']:c for c in fixture['cases']}
        for scope,era in [('initialworldsetup6',2),('initialworldsetup7',4)]:
            case=cases['research_and_rebuild_'+scope]
            self.assertEqual([s['value'] for step,s in zip(case['steps'],case['states']) if step['action']=='query_era'],[era,era,era])
            case=cases['ten_temporary_claims_'+scope]
            expired=[s for step,s in zip(case['steps'],case['states']) if step['action']=='expire']
            self.assertEqual([len(s['unlock_state']['timers']) for s in expired],list(range(9,-1,-1))+[0])
            last=expired[-1]['unlock_state']
            self.assertIn('@'+str(key('always')),last['received'])
            self.assertNotIn('@'+str(key('Xmas_All')),last['unlocked'])
            self.assertIn('@'+str(key('ERA_STICKER_1')),last['unlocked'])


if __name__=='__main__':unittest.main()
