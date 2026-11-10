import hashlib
import json
import unittest

from tools.current_cards import ROOT,decode_archive
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key
from tools.unlock_dispatch import extract


class UnlockDispatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_unlock_dispatch.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_source_dependencies_and_routines_are_reproducible(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/unlock-dispatch.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        files=decode_archive((ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes())
        for path,digest in self.content['tables_sha256'].items():self.assertEqual(hashlib.sha256(files[path]).hexdigest(),digest)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(sum(len(s['dependencies']) for s in self.content['scopes'].values()),1182)
        for scope,source in self.content['scopes'].items():
            for dependency,binding in zip(source['dependencies'],source['bindings']):
                self.assertEqual(dependency,dict(unlock=key(binding['unlock']),condition=key(binding['condition']),phase=1))
                self.assertIn(len(binding['achievement']),(0,2))
            self.assertTrue(self.cases['authored_'+scope]['prepared']['rows'])

    def test_depth_first_repeat_and_compound_activation(self):
        states=self.cases['depth_first_repeated']['states']
        order=[['notify',[30]],['notify',[20]],['notify',[30]],['notify',[40]]]
        self.assertEqual(states[0]['events'][1:],order)
        self.assertEqual(states[1]['events'],order)
        self.assertEqual(states[1]['state']['first_seen']['@10'],1)
        states=self.cases['compound_condition_first']['states']
        self.assertFalse(states[0]['state']['unlocked'])
        self.assertEqual(states[1]['events'][-3:],[['notify',[30]],['notify',[20]],['notify',[10]]])
        self.assertEqual(states[1]['state']['rows'][0]['phase'],2)
        for old in (0,1,2,3,0xffffffff):
            for new in (0,1,2,3,0xffffffff):
                case=self.cases[f'register_{old}_{new}']
                self.assertEqual(case['states'][0]['state']['rows'][0]['phase'],new if old==1 else old)

    def test_zero_duration_is_dynamic_and_deadlines_use_unsigned_words(self):
        self.assertEqual(self.content['rules']['ordinary_duration'],-1)
        states=self.cases['duration_0']['states']
        self.assertFalse(states[0]['state']['received'])
        self.assertFalse(states[0]['state']['first_seen'])
        self.assertEqual(states[0]['state']['timers']['@10'],[4294967280,4294967295])
        self.assertTrue(self.cases['duration_-1']['states'][0]['state']['received'])
        self.assertEqual(self.cases['remaining_[1000, 0]']['states'][0]['value'],0)
        # The original unsigned subtraction wraps on expiry; retain it rather
        # than treating this kernel as an already-ported expiry controller.
        self.assertEqual(self.cases['remaining_[1001, 0]']['states'][0]['value'],1271310319)
        self.assertEqual(self.cases['remaining_sse2_[1001, 0]']['states'][0]['value'],-2147483648)
        self.assertEqual(self.cases['overflow_[4294967295, 499]_True']['states'][0]['value'],2147483647)
        self.assertEqual(self.cases['overflow_[1000, 500]_False']['states'][0]['value'],-2147483647)
        self.assertEqual(self.cases['overflow_[1000, 500]_True']['states'][0]['value'],-2147483648)
        case=self.cases['authored_dynamic_claims']
        self.assertEqual(len(case['states'][9]['state']['timers']),10)
        self.assertFalse(case['states'][9]['state']['received'])
        self.assertFalse(case['states'][9]['state']['first_seen'])
        self.assertEqual(case['states'][-1]['value'],604800)
        self.assertEqual(self.cases['remaining_[4294967295, 4294967295]']['states'][0]['value'],1)

    def test_full_sets_do_not_stop_dependency_callbacks(self):
        case=self.cases['unlock_capacity_still_recurses']
        self.assertEqual(case['states'][0]['events'][-2:],[['notify',[30]],['notify',[20]]])
        self.assertEqual(len(case['states'][0]['state']['unlocked']),16384)
        self.assertFalse(case['states'][1]['value'])
        case=self.cases['received_capacity']
        self.assertNotIn('@10',case['states'][0]['state']['received'])
        self.assertNotIn('@10',case['states'][0]['state']['first_seen'])
        self.assertEqual(case['states'][1]['state']['rows'][0]['phase'],1)

    def test_actual_acquisition_generates_era_and_power_unlocks(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_unlocked_rewards.json').read_text())
        for address in ['0x1015cc90','0x1015c7f0','0x1015c640','0x1015c710','0x1015c0d0','0x10027410','0x100f5c30']:
            self.assertTrue(any(int(start,16)<=int(address,16)<int(start,16)+len(code)//2 for start,code in fixture['native_routines'].items()),address)
            self.assertNotIn(address,fixture['adapters'])
        cases={c['name']:c for c in fixture['cases']}
        case=cases['sequential_eras_initialworldsetup6']
        self.assertEqual([s['value'] for step,s in zip(case['steps'],case['states']) if step['action']=='query_era'],[1,2,3])
        case=cases['sequential_eras_initialworldsetup7']
        self.assertEqual([s['value'] for step,s in zip(case['steps'],case['states']) if step['action']=='query_era'],[1,4])
        for case in fixture['cases']:
            self.assertNotIn('acquisition_unlocks',case)
            for step,state in zip(case['steps'],case['states']):
                if step['action']=='consume' and state['availability']['acquired']:
                    self.assertTrue(state['unlock_state']['received'])


if __name__=='__main__':unittest.main()
