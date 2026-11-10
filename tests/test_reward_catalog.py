import hashlib
import json
import unittest

from tools.reward_catalog import extract
from tools.native_scenery_oracle import NativeImage,ROOT
from tools.reward_dispatch import key


class RewardCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_reward_catalog.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_source_tables_and_actual_initialization_instructions(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/reward-catalog.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.fixture['adapters'],['0x101a7280'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(self.content['rules']['standard_limit'],99999)

    def test_source_max_collectable_is_both_stock_and_lifetime_limit(self):
        state=self.cases['ordinary']['states'][0]['availability']
        self.assertEqual(state['stock_limits']['@50'],1)
        self.assertEqual(state['acquisition_limits']['@50'],1)
        self.assertEqual(state['stock_limits']['@40'],99999)
        self.assertEqual(state['stock_limits']['@60'],99999)
        self.assertEqual(self.cases['card_limit_-1']['states'][0]['availability']['stock_limits']['@50'],4294967295)
        self.assertEqual(self.cases['card_limit_0']['states'][0]['availability']['stock_limits']['@50'],0)

    def test_duplicate_data_rebinds_but_cannot_reset_existing_capacity(self):
        state=self.cases['duplicate_data']['states'][0]
        self.assertEqual(state['registry']['cards']['@50'],1)
        self.assertEqual(state['availability']['stock_limits']['@50'],1)
        self.assertEqual(state['availability'],self.cases['duplicate_data']['states'][1]['availability'])
        self.assertEqual(self.cases['cross_group_first_capacity_wins']['states'][0]['availability']['stock_limits']['@50'],99999)

    def test_missing_and_repeated_details_keep_original_fallback(self):
        missing=self.cases['missing_details']['states'][0]
        duplicate=self.cases['duplicate_details']['states'][0]
        for group in ['packs','stickers','cards']:
            self.assertEqual(missing['records'][group][0]['detail_index'],-1)
            self.assertEqual(duplicate['records'][group][0]['detail_index'],1)
        zero=self.cases['zero_rows']['states'][0]
        self.assertEqual(zero['availability']['stock_limits'],{})
        self.assertTrue(zero['records']['stickers'][0]['internal'])
        self.assertEqual(zero['records']['cards'][0]['type'],4)

    def test_source_startup_gates_and_every_supported_card_limit(self):
        self.assertTrue(self.content['scopes']['initialworldsetup6']['available'])
        self.assertFalse(self.content['scopes']['initialworldsetup']['available'])
        for scope,source in self.content['scopes'].items():
            limits=self.cases['source_'+scope]['states'][0]['availability']['stock_limits']
            seen=set()
            for row in source['cards']:
                if row['id'] in seen:continue
                seen.add(row['id'])
                self.assertEqual(limits['@'+str(row['id'])],row['max_collectable']&0xffffffff,scope+' '+row['source_id'])

    def test_registered_inventory_continues_through_actual_reward_redemption(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_registered_rewards.json').read_text())
        self.assertEqual(fixture['registry_adapters'],['0x101a7280'])
        for address in ['0x10001360','0x10001870','0x1004de10','0x10027330','0x10028420','0x10050170']:
            self.assertNotIn(address,fixture['reward_adapters'])
        self.assertEqual(len(fixture['cases']),70)
        self.assertEqual(sum(len(c['steps']) for c in fixture['cases']),904)
        advances=[c for c in fixture['cases'] if c['name'].startswith('advance_')]
        self.assertEqual(len(advances),56)
        self.assertEqual(len([c for c in fixture['cases'] if c['name'].startswith('pack_')]),14)
        for case in advances:
            identity=key(case['name'].removeprefix('advance_'))
            row=next(r for r in case['records']['cards'] if r['id']==identity)
            state=case['states'][-1]
            self.assertEqual(state['availability']['acquired']['@'+str(identity)],min(3,row['max_collectable']),case['name'])
            self.assertEqual(state['availability']['acquired']['@'+str(key(row['name']+'_COMPLETED'))],1,case['name'])
            self.assertEqual(state['state']['queue'],[],case['name'])


if __name__=='__main__':unittest.main()
