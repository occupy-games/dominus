import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.sticker_selection import extract


class StickerSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_sticker_selection.json').read_text())
        cls.cases={case['name']:case for case in cls.fixture['cases']}

    def test_source_metadata_is_reproducible(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/sticker-selection.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(set(self.fixture['adapters']),{'0x100f62b0','0x10026f40','0x10027330','0x10001360','0x1035f7f0'})

    def test_source_pools_and_boundaries(self):
        rules=self.content['rules']
        self.assertEqual(rules['chance_scale'],1000.)
        self.assertEqual(rules['rare_threshold'],999)
        self.assertEqual(rules['gem_reward'],'Sticker_Gem_1')
        self.assertEqual(len(set(rules['rare_rewards'])),5)
        self.assertEqual(self.cases['zero_era_weights']['expected']['random_calls'],0)
        for name in ['rare_excluded','internal_excluded','zero_gate','zero_key','category_zero','no_stickers']:
            self.assertEqual(self.cases[name]['expected']['value'],0)
        self.assertNotEqual(self.cases['rare_boundary']['expected']['value'],0)

    def test_full_table_tail_and_missing_final_gate(self):
        case=self.cases['last_slots']
        self.assertEqual(len(case['cards']),256)
        self.assertEqual(len(case['stickers']),256)
        self.assertEqual(case['expected']['value'],10001)
        self.assertIn(['card_complete',255,[]],case['expected']['events'])
        self.assertEqual(self.cases['final_pass_keeps_zero_gate']['expected']['value'],10002)
        self.assertEqual(sum(event[0]=='card_remaining' for event in self.cases['repeat_remaining']['expected']['events']),2)


if __name__=='__main__':unittest.main()
