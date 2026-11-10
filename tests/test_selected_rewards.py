import hashlib
import json
import unittest

from tools.card_research import extract
from tools.native_scenery_oracle import NativeImage,ROOT
from tools.reward_dispatch import key


class SelectedRewardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_selected_rewards.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_actual_dispatch_selection_research_and_inventory_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x1004de10','0x10026f40','0x10027330','0x10001360','0x10050170','0x10051080','0x10050930']:
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']),432)
        self.assertEqual(sum(len(c['steps']) for c in self.fixture['cases']),2451)

    def test_source_selection_fields_have_loader_and_fallback_provenance(self):
        content=extract()
        self.assertEqual(content['native_routines']['0x101ab4d0'],'8b33c74308a492d910')
        self.assertIn('895814',content['native_routines']['0x101ab6b0']) # Original registry value is overwritten by each row.
        for scope,cards in content['scopes'].items():
            self.assertTrue(all(isinstance(c['slot_20'],int) for c in cards),scope)
        for sticker in content['stickers']:
            self.assertEqual(sticker['slot_08'],1)
            self.assertEqual(sticker['category'],sticker['categories'][0])
            self.assertEqual(sticker['count'],sticker['counts'][0])

    def test_overrides_and_shared_random_continuation(self):
        for case in self.fixture['cases']:
            if case['name'].startswith('Reward_') and case['steps'][0]['override']:
                self.assertEqual(case['states'][-1]['random_calls'],0,case['name'])
        self.assertGreater(self.cases['Reward_ChestSticker_1_0']['states'][-1]['random_calls'],0)
        self.assertEqual(self.cases['configuration_empty']['states'][-1]['random_calls'],0)

    def test_full_source_scopes_and_all_shared_packs_are_compared(self):
        content=extract()
        for scope in content['scopes']:
            for stage in range(3):self.assertIn('source_'+scope+'_'+str(stage),self.cases)
        packs=[c for c in self.fixture['cases'] if c['name'].startswith('pack_')]
        self.assertEqual(len(packs),14)
        for case in packs:
            self.assertEqual(case['states'][-1]['state']['queue'],[],case['name'])

    def test_research_completion_changes_the_subsequent_reward_state(self):
        case=self.cases['research_changes_next_reward']
        complete=case['states'][5]
        self.assertTrue(complete['value'])
        self.assertEqual(complete['availability']['acquired']['@'+str(key('Card_Research_Test_COMPLETED'))],1)
        self.assertFalse(complete['research_context']['cache_valid'])
        self.assertGreater(case['states'][-1]['random_calls'],complete['random_calls'])

    def test_source_duplicate_registries_resolve_the_last_row(self):
        case=self.cases['duplicate_card_registry']
        self.assertEqual(case['states'][-1]['availability']['acquired']['@'+str(key('Card_Last_Registered_COMPLETED'))],1)
        case=self.cases['duplicate_sticker_registry']
        self.assertTrue(case['states'][-1]['value'])
        self.assertEqual(case['states'][-1]['availability']['acquired']['@'+str(key('Card_Research_Test_COMPLETED'))],1)


if __name__=='__main__':unittest.main()
