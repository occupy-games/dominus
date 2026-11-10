import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.storm_chests import extract


class StormChestsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_storm_chests.json').read_text())

    def test_source_tables_and_native_routines_are_current(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/storm-chests.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x10168d00','0x10257530','0x1019f2c0','0x10356f60','0x10357000','0x1035f180']:
            self.assertNotIn(address,self.fixture['adapters'])
        for address in ['0x10153030','0x1019f2c0','0x10357040','0x10356f60','0x10357000']:
            self.assertNotIn(address,self.fixture['generation_adapters'])

    def test_real_area_limits_remain_distinct_and_unavailable_defaults_are_explicit(self):
        scopes=self.content['scopes']
        self.assertFalse(scopes['initialworldsetup']['available'])
        self.assertTrue(scopes['initialworldsetup6']['available'])
        self.assertTrue(scopes['initialworldsetup7']['available'])
        self.assertEqual(scopes['initialworldsetup6']['areas'][0],dict(unlock='Pre',x=155.,z=85.,radius=50.,force=True,max_spawn=1,max_depth=0,max_total=1))
        self.assertNotEqual(scopes['initialworldsetup6']['areas'],scopes['initialworldsetup7']['areas'])
        self.assertEqual(self.content['rules']['attempts'],100)
        self.assertEqual(self.content['rules']['influence_padding'],3)

    def test_native_caps_authored_ids_and_opening_phases(self):
        cases={case['name']:case['expected'] for case in self.fixture['cases']}
        self.assertEqual(cases['authored_id']['counts'],[0])
        self.assertEqual(cases['another_authored_id']['counts'],[0])
        self.assertEqual(cases['opening_generated']['counts'],[1])
        self.assertEqual(cases['opened_generated']['counts'],[1])
        self.assertEqual(cases['full']['requests'][0]['count'],0)
        self.assertEqual(cases['overfull']['requests'][0]['count'],0)
        self.assertEqual(cases['last_slot']['requests'][0]['count'],1)
        self.assertEqual(cases['boundary']['counts'],[0]) # Original strict interior.
        self.assertEqual(cases['overlap']['counts'],[1,1])
        self.assertEqual(cases['disabled']['random_calls'],0)
        self.assertEqual(cases['locked']['requests'],[])
        self.assertEqual(cases['placement_rng']['random_calls'],9)

    def test_original_burial_rounding_and_failed_placement(self):
        batches={case['name']:case['expected'] for case in self.fixture['batches']}
        self.assertEqual([batches[f'depth_{word}']['created'][0]['depth'] for word in [0,5461,5462,16383,16384,27305,27306,32767]],[0,0,1,1,2,2,3,3])
        self.assertEqual(batches['reject']['created'],[])
        self.assertEqual(batches['reject']['random_calls'],18)
        for name in ['zero','negative']:
            self.assertEqual(batches[name]['created'],[])
            self.assertEqual(batches[name]['random_calls'],0)
            self.assertEqual([q['kind'] for q in batches[name]['queries']],[2,1])
            self.assertEqual(batches[name]['released'],[2,1])


if __name__=='__main__':unittest.main()
