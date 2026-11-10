import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.reward_dispatch import key
from tools.reward_queue import extract


class RewardQueueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_reward_queue.json').read_text())
        cls.cases={case['name']:case for case in cls.fixture['cases']}

    def test_native_admission_collection_consumption_and_inventory_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/reward-queue.json').read_text()))
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address in ['0x10050170','0x10051080','0x10001670','0x100016e0','0x10001800','0x100242f0','0x10033c90']:
            self.assertIn(address,self.fixture['native_routines'])
        self.assertEqual(len(self.fixture['cases']),327)
        self.assertEqual(sum(len(case['steps']) for case in self.fixture['cases']),1147)

    def test_queued_copies_count_toward_limits_before_collection(self):
        states=self.cases['capacity_stock']['states']
        self.assertTrue(states[0]['value'])
        self.assertFalse(states[1]['value'])
        self.assertEqual(states[0]['availability']['acquired']['@50'],0)
        self.assertEqual(states[2]['availability']['acquired']['@50'],1)
        self.assertEqual(states[2]['state']['queue'],[])
        self.assertFalse(states[3]['value'])
        for name in ['flags_4','flags_8']:
            final=self.cases[name]['states'][-1]
            self.assertEqual(final['state']['queue'],[])
            self.assertEqual(final['availability']['acquired']['@50'],1 if name=='flags_4' else 0)
        for kind in [0,1]:
            self.assertEqual(self.cases['double_spend_'+str(kind)]['states'][-1]['availability']['spent']['@50'],2)

    def test_actual_source_packs_reach_actual_inventory_without_mock_grants(self):
        packs=[case for name,case in self.cases.items() if name.startswith('pipeline_Pack_')]
        self.assertEqual(len(packs),14)
        for case in packs:
            final=case['states'][-1]
            self.assertEqual(final['state']['queue'],[])
            self.assertEqual(final['dispatch']['pack_count'],0)
            self.assertEqual(final['dispatch']['pack_index'],0)
        treasure=self.cases['pipeline_Pack_BigTreasure1']['states'][-1]
        self.assertEqual(treasure['state']['gems'],15)
        gem='@'+str(key('Sticker_Gem_1'))
        self.assertEqual(treasure['availability']['acquired'][gem],15)
        self.assertEqual(treasure['availability']['spent'][gem],15)
        self.assertEqual(treasure['availability']['acquired']['@60'],8)

    def test_dynamic_claims_signed_carry_and_original_spawn_seed(self):
        self.assertIn(0,self.content['rules']['exempt'])
        for identity in self.content['rules']['exempt']:
            for state in self.cases['exempt_'+str(identity)]['states']:
                self.assertTrue(state['value'])
                self.assertEqual(state['availability']['acquired'],{})
                self.assertEqual(state['availability']['spent'],{})
        state=self.cases['signed_resource_carry']['states'][0]['state']
        self.assertEqual(state['gems'],1)
        self.assertEqual(state['deferred']['belief'],[0,2147483648])
        self.assertEqual(state['deferred']['wheat'],[4294967295,2147483647])
        self.assertEqual(state['deferred']['ore'],[1,0])
        for action in self.content['rules']['actions']:
            for word,seed in [(0,0),(16383,0),(16384,32768),(32767,32768)]:
                state=self.cases[f'extra_{action}_{word}']['states'][1]
                spawn=next(event for event in state['events'] if event[0]=='spawn_followers')
                self.assertEqual(spawn[1][2],seed)
                self.assertEqual(state['random_calls'],1)


if __name__=='__main__':unittest.main()
