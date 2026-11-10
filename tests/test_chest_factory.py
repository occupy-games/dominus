import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.storm_chests import extract


class ChestFactoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_chest_factory.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_original_factory_executes_and_matches_current_sources(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(NativeImage(raw).read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])

    def test_source_reward_names_and_story_probability(self):
        self.assertEqual(self.content['factory_rules']['story_odds'],.5)
        for name in ['story','story_below_half']:
            self.assertEqual(self.cases[name]['request']['kind'],4)
            self.assertEqual(self.cases[name]['reward'],'RandomStory')
        for name in ['ordinary','ordinary_above_half','odds_zero','odds_one_endpoint']:
            self.assertEqual(self.cases[name]['reward'],'Reward_RandomStickerOrGem')
        self.assertEqual(self.cases['allocation_failed']['events'],[['allocate']])
        self.assertEqual(self.cases['allocation_failed']['random_calls'],0)
        self.assertEqual(self.cases['constructor_rng']['random_calls'],4)
        self.assertEqual(self.cases['constructed_position']['events'][-1][1][:2],[160.25,120.5])
        self.assertNotEqual(self.cases['constructed_position']['events'][-1][1],self.cases['constructed_position']['request']['position'])

    def test_source_type_thresholds_include_water_boundary(self):
        for level,kind in [(19,3),(25,1),(41,2)]:
            self.assertEqual(self.cases[f'boundary_{float(level)}_0.0']['request']['kind'],kind)
        self.assertEqual(self.cases['boundary_19.0_1e-06']['request']['kind'],0)
        self.assertEqual(self.cases['boundary_25.0_-1e-06']['request']['kind'],0)
        self.assertEqual(self.cases['boundary_41.0_-1e-06']['request']['kind'],1)


if __name__=='__main__':unittest.main()
