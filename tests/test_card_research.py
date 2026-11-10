import hashlib
import json
import unittest

from tools.card_research import extract,pair_key
from tools.native_scenery_oracle import NativeImage,ROOT
from tools.reward_dispatch import key


class CardResearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_card_research.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_source_tables_and_instruction_provenance(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/card-research.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address in ['0x10001360','0x100015b0','0x10001870','0x10027330','0x10027410','0x10028420']:
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(self.content['unavailable']['initialworldsetup6'],[])
        self.assertEqual(self.content['types'],['BASE','POWER','ADVANCE','SHOP'])

    def test_real_research_consumes_stickers_then_card(self):
        case=self.cases['ordinary_research']
        final=case['states'][-1]['availability']
        self.assertEqual(final['spent']['@60'],3)
        self.assertEqual(final['spent']['@50'],1)
        self.assertEqual(final['spent']['@'+str(key('Card_Research_Test_RES_WAR'))],5)
        self.assertEqual(final['acquired']['@'+str(key('Card_Research_Test_COMPLETED'))],1)
        self.assertEqual(final['acquired']['@'+str(pair_key(50,60))],3)
        self.assertFalse(case['states'][-1]['cache_valid'])

    def test_eligibility_and_credit_are_distinct(self):
        case=self.cases['unowned_sticker']
        self.assertTrue(case['states'][4]['value'])
        self.assertFalse(case['states'][5]['value'])
        self.assertFalse(self.cases['spent_card']['states'][5]['value'])
        self.assertTrue(self.cases['internal_True']['states'][1]['value'])
        self.assertFalse(self.cases['internal_False']['states'][1]['value'])

    def test_failure_keeps_prior_consumption(self):
        case=self.cases['limit_research_0']['states'][5]
        self.assertFalse(case['value'])
        self.assertEqual(case['availability']['spent']['@60'],1)
        self.assertEqual(case['availability']['acquired']['@'+str(pair_key(50,60))],1)
        case=self.cases['limit_completion_0']['states'][10]
        self.assertFalse(case['value'])
        self.assertEqual(case['availability']['spent']['@50'],1)
        self.assertEqual(case['availability']['spent']['@'+str(key('Card_Research_Test_RES_WAR'))],5)

    def test_every_recovered_advance_executes_original_completion(self):
        for scope,cards in self.content['scopes'].items():
            for card in cards:
                if card['type']!=2:continue
                case=self.cases['source_'+scope+'_'+card['source_id']]
                self.assertTrue(case['states'][-1]['value'],case['name'])

    def test_original_queue_composes_research_without_predicate_or_storage_stubs(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_researched_rewards.json').read_text())
        for address in ['0x10001360','0x10027330','0x100273d0','0x10027410','0x10028420']:
            self.assertNotIn(address,fixture['adapters'])
        cases={c['name']:c for c in fixture['cases']}
        case=cases['auto_3_3']
        self.assertEqual(case['states'][1]['availability']['spent']['@50'],1)
        self.assertEqual(case['states'][1]['availability']['acquired']['@'+str(key('Card_Research_Test_COMPLETED'))],1)
        self.assertFalse(case['states'][1]['research_context']['cache_valid'])
        for card in self.content['scopes']['initialworldsetup6']:
            if card['type']!=2:continue
            case=cases['source_'+card['source_id']]
            self.assertEqual(case['states'][-1]['availability']['acquired']['@'+str(key(card['name']+'_COMPLETED'))],1,case['name'])


if __name__=='__main__':unittest.main()
