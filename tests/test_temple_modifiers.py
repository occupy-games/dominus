import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_modifiers import extract
from tools.reward_dispatch import key


class TempleModifiersTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_modifiers.json').read_text())
        cls.lifecycle=json.loads((ROOT/'game/tests/fixtures/source_temple_modified_lifecycle.json').read_text())
        cls.cases={row['name']:row for row in cls.fixture['cases']}

    def test_original_metadata_and_native_instructions_are_reproducible(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/temple-modifiers.json').read_text()))
        self.assertEqual(len(self.content['records']),8)
        self.assertEqual([row['family'] for row in self.content['records']],[0]*6+[1]*2)
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for fixture in [self.fixture,self.lifecycle]:
            self.assertEqual(fixture['executable_sha256'],self.content['executable_sha256'])
            self.assertEqual(fixture['source_sha256'],self.content['source_sha256'])
            for address,code in fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            for address in ['0x1013dd90','0x1013d580','0x1015c130']:self.assertNotIn(address,fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']),90)
        self.assertEqual(len(self.lifecycle['cases']),174)

    def test_mask_slots_preserve_global_family_order_and_both_word_boundaries(self):
        for family in ['follower_modifiers','house_modifiers']:
            self.assertEqual(self.cases['bit_31_456']['expected']['state'][family],[0x80000000,0])
            self.assertEqual(self.cases['bit_32_123']['expected']['state'][family],[0,1])
            self.assertEqual(self.cases['bit_63_456']['expected']['state'][family],[0,0x80000000])
        cases=self.fixture['cases']
        cooking=next(c for c in cases if c['state']['generic_type']==key('Monument_Cooking') and len(c['unlocked'])==3 and c['state']['follower_modifiers']==[0,0])
        self.assertEqual(cooking['expected']['state']['follower_modifiers'],[0b111100,0])
        self.assertEqual(cooking['expected']['state']['house_modifiers'],[0,0])
        family=next(c for c in cases if c['state']['generic_type']==key('Monument_Family') and len(c['unlocked'])==3 and c['state']['follower_modifiers']==[0,0])
        self.assertEqual(family['expected']['state']['house_modifiers'],[3,0])

    def test_invalidation_is_only_the_empty_to_nonempty_edge(self):
        for case in self.fixture['cases']:
            old=any(case['state'][field][index] for field in ['follower_modifiers','house_modifiers'] for index in range(2))
            new=any(case['expected']['state'][field][index] for field in ['follower_modifiers','house_modifiers'] for index in range(2))
            notifications=[event for event in case['expected']['events'] if event[0]=='invalidate_modifiers_at']
            self.assertEqual(len(notifications),int(not old and new))
            for event in notifications:self.assertEqual(event[1],[10,-12])

    def test_native_refresh_precedes_affiliation_and_actual_repair(self):
        saw_active=False
        for case in self.lifecycle['cases']:
            events=case['expected']['events'];names=[event[0] for event in events]
            self.assertEqual(names[0],'refresh_modifiers')
            self.assertLess(names.index('refresh_modifiers'),names.index('clock'))
            self.assertLess(names.index('clock'),names.index('spatial_refresh'))
            if 'unlocked' in names:
                self.assertLess(names.index('unlocked'),names.index('clock'));saw_active=True
        self.assertTrue(saw_active)
        self.assertEqual(sum(len(s['steps']) for s in self.lifecycle['sequences']),128)


if __name__=='__main__':unittest.main()
