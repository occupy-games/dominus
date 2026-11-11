import json
import struct
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_effects import extract


def number(word):return struct.unpack('<f',struct.pack('<I',word))[0]


class TempleEffectsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_effects.json').read_text())
        cls.cases={row['name']:row for row in cls.fixture['cases']}

    def test_source_bindings_do_not_assume_csv_column_order(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/temple-effects.json').read_text()))
        self.assertEqual(self.content['bindings']['race']['RouteSpeed']['index'],2)
        self.assertEqual(self.content['bindings']['race']['StaminaDecay']['index'],21)
        self.assertEqual(self.content['bindings']['jobs']['StaminaDecay']['index'],10)
        self.assertEqual(self.content['bindings']['House Values']['Capacity']['index'],16)
        for record,parsed in zip(self.content['records'],self.fixture['parsed'][:8],strict=True):
            self.assertEqual(record['effect'],parsed['effect'])
            self.assertEqual({key:record[key] for key in ['index','value','operation']},parsed['expected'])
        self.assertEqual([p['expected']['operation'] for p in self.fixture['parsed'][8:]],[1,1,0,0,0])
        self.assertEqual(self.fixture['parsed'][-1]['expected']['value'],-.125)

    def test_original_parser_containment_masks_getters_and_refresh_execute(self):
        self.assertEqual(self.fixture['executable_sha256'],self.content['executable_sha256'])
        self.assertEqual(self.fixture['source_sha256'],self.content['source_sha256'])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x10171610','0x100340d0','0x100342a0','0x100343b0','0x100b6d60','0x100b6e90','0x100b7580','0x1013efa0','0x1013f080','0x10153d80','0x1013dd90','0x1015c130']:
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']),179)

    def test_original_effect_order_and_building_eligibility(self):
        race=self.cases['point_race_0_0_0']['expected']['values']
        jobs=self.cases['point_jobs_0_0_0']['expected']['values']
        self.assertEqual(number(race[2]),4.5)
        self.assertEqual(number(race[21]),0)
        self.assertEqual(number(jobs[10]),0)
        self.assertEqual(number(self.cases['house_0_False_False']['expected']['values'][16]),4)
        for name in ['house_0_False_True','house_1_True_False','house_2_True_False']:
            self.assertEqual(number(self.cases[name]['expected']['values'][16]),3)
        for entry in self.content['monastery_types'][1:]:
            self.assertEqual(number(self.cases['monastery_'+entry['name']]['expected']['values'][16]),3)
        self.assertEqual(self.cases['overlap_race']['expected'],self.cases['point_race_0_0_0']['expected'])
        self.assertEqual(number(self.cases['overlap_House Values']['expected']['values'][16]),4)

    def test_inherited_geometry_and_missing_owners_bound_actual_stat_effects(self):
        for table,index in [('race',2),('jobs',10),('House Values',16)]:
            direct=self.cases['point_'+table+'_1_0_0'] if table!='House Values' else None
            if direct:self.assertNotEqual(direct['expected']['values'][index],direct['base'][index])
            boundary=self.cases['inherited_False_22.0_6.0_'+table]
            missing=self.cases['inherited_True_10.0_6.0_'+table]
            for case in [boundary,missing]:
                self.assertEqual(case['expected']['mask'],[0,0])
                self.assertEqual(case['expected']['values'],case['base'])

    def test_refresh_is_composed_with_eligibility_and_stat_application(self):
        before=self.cases['refresh_House Values_0']
        after=self.cases['refresh_House Values_1']
        self.assertEqual(before['expected']['mask'],[0,0])
        self.assertEqual(number(before['expected']['values'][16]),3)
        self.assertEqual(after['expected']['mask'],[3,0])
        self.assertEqual(number(after['expected']['values'][16]),4)
        self.assertEqual(sum(len(sequence['steps']) for sequence in self.fixture['sequences']),48)


if __name__=='__main__':unittest.main()
