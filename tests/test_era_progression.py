import hashlib
import json
import unittest

from tools.era_progression import extract
from tools.native_scenery_oracle import NativeImage,ROOT


class EraProgressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_era.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_original_refresh_hashes_and_membership_execute(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/era-progression.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertNotIn('0x1015c1e0',self.fixture['adapters'])

    def test_cache_and_highest_unlock_are_distinct_from_period(self):
        case=self.cases['levels_3_2']
        self.assertEqual(case['states'][0]['state'],dict(cache_valid=True,period=3,era=2))
        self.assertEqual(case['states'][1]['events'],[])
        self.assertEqual(self.cases['higher_wins']['states'][0]['state']['era'],12)
        self.assertEqual(self.cases['out_of_range']['states'][0]['state']['era'],0)
        self.assertEqual(self.cases['already_valid']['states'][0]['value'],9)

    def test_invalidation_and_decrease_follow_source_queries(self):
        case=self.cases['changes_require_invalidation']
        self.assertEqual([s['value'] for s in case['states']],[1,1,4,4])
        self.assertEqual(self.cases['decrease']['states'][0]['state'],dict(cache_valid=True,period=2,era=1))
        self.assertFalse(self.cases['notification_invalidation']['states'][0]['state']['cache_valid'])

    def test_global_refresh_precedes_period_notification(self):
        case=self.cases['local_reenters_dirty_global']['states'][0]
        self.assertEqual(case['global_state']['period'],3)
        self.assertEqual([e for e in case['events'] if e[0]=='period_changed'],[['period_changed',[3]],['period_changed',[3]]])
        case=self.cases['local_uses_valid_global_period']['states'][0]
        self.assertEqual(case['state']['period'],3)
        self.assertEqual(case['events'][-1],['period_changed',[8]])

    def test_reward_selection_runs_actual_cache_after_card_completion(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_era_rewards.json').read_text())
        for address in ['0x100f62b0','0x100f5c30','0x1015c1e0','0x1004de10','0x10027410']:
            self.assertNotIn(address,fixture['adapters'])
        cases={c['name']:c for c in fixture['cases']}
        for name,era in [('Bronze',2),('Iron',3)]:
            case=cases['completed_Card_Stickers_'+name+'_COMPLETED']
            self.assertEqual(case['states'][0]['value'],1)
            self.assertFalse(case['states'][5]['research_context']['cache_valid'])
            self.assertEqual(case['states'][6]['value'],era)
        case=cases['completed_Card_Stickers_Imperial_COMPLETED']
        self.assertEqual(case['states'][6]['value'],1) # This card has no Homeworld6 source definition.
        case=cases['scope7_imperial_with_prior_unlocks']
        self.assertEqual(case['states'][0]['value'],3)
        self.assertFalse(case['states'][5]['research_context']['cache_valid'])
        self.assertEqual(case['states'][6]['value'],4)


if __name__=='__main__':unittest.main()
