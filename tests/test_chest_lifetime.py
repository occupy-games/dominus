import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.storm_chests import extract


class ChestLifetimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_chest_lifetime.json').read_text())
        cls.cases={case['name']:case for case in cls.fixture['cases']}

    def test_complete_native_lifetime_routines_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(set(self.fixture['observation_hooks']),{'0x101521b0','0x10152ae4'})

    def test_strict_thresholds_and_one_reward(self):
        states=self.cases['no_repeated_reward']['states']
        self.assertEqual(states[0]['chests'][0]['core']['source_slots']['60'],1)
        self.assertEqual(states[1]['chests'][0]['core']['source_slots']['60'],2)
        self.assertEqual(sum(e[0]=='grant' for s in states for e in s['events']),1)
        boundary=self.cases['phase_two_exact']['states']
        self.assertEqual(len(boundary[0]['chests']),1)
        self.assertEqual(boundary[1]['chests'],[])
        self.assertEqual([e[0] for e in boundary[1]['events']],['ground','destroy','unregister','release'])
        self.assertEqual(self.cases['multiple_release']['states'][0]['output']['removed'],[0,2])
        self.assertEqual([c['handle'] for c in self.cases['multiple_release']['states'][0]['chests']],[1])

    def test_original_reward_gates_and_fallback(self):
        events=lambda name:self.cases['reward_'+name]['states'][0]['events']
        grants=lambda name:[e[2] for e in events(name) if e[0]=='grant']
        self.assertEqual(grants('fallback_zero')[0][0],'Reward_ChestSticker')
        self.assertEqual(grants('fallback_missing')[0][0],'Reward_ChestSticker')
        self.assertEqual(len(grants('bonus_first')),1)
        self.assertEqual(len(grants('bonus_later')),2)
        self.assertEqual(len(grants('bonus_unlocked_by_grant')),2)
        self.assertEqual(grants('bonus_later')[1][0],'Reward_BonusChestSticker')
        self.assertEqual([g[2] for g in grants('bonus_type_b')],[0,32])
        self.assertEqual(grants('mode1_sentinel'),[])
        self.assertEqual(len(grants('mode1_valid')),1)
        self.assertEqual(sum(e[0]=='mode2_prepare' for e in events('mode2_ready')),4)
        self.assertEqual(grants('mode2_ready'),[])

    def test_source_height_response_and_opening_identity(self):
        lowered=self.cases['follow_lowered_ground']['states']
        self.assertLess(lowered[-1]['chests'][0]['core']['position'][2],6.)
        self.assertEqual(self.cases['stay_buried_after_raise']['states'][-1]['chests'][0]['core']['position'][2],6.)
        for state in self.cases['full_lifetime']['states']:
            if state['chests']:self.assertEqual(state['chests'][0]['source_id'],0)
        self.assertEqual(self.content['lifetime_rules']['count_baseline'],90)


if __name__=='__main__':unittest.main()
