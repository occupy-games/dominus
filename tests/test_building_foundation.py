import json
import unittest

from tools.native_scenery_oracle import ROOT,NativeImage
from tools.building_foundation import extract


class BuildingFoundationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_building_foundation.json').read_text())
        cls.composed=json.loads((ROOT/'game/tests/fixtures/source_temple_house_foundation.json').read_text())
        cls.cases={row['name']:row for row in cls.fixture['cases']}

    def test_native_constants_and_actual_scan_rounding_fabs_and_wrapper_execute(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/building-foundation.json').read_text()))
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for fixture in [self.fixture,self.composed]:
            self.assertEqual(fixture['executable_sha256'],self.content['executable_sha256'])
            for address,code in fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            for address in ['0x1003b690','0x10357040','0x102d5a80']:self.assertNotIn(address,fixture['adapters'])
        for address in ['0x100b6e10','0x100b6d60','0x100b7580']:self.assertNotIn(address,self.composed['adapters'])
        self.assertEqual(len(self.fixture['cases']),276)
        self.assertEqual(len(self.composed['cases']),118)

    def test_inclusive_rounding_and_empty_intervals_preserve_source_sample_order(self):
        self.assertEqual(self.cases['grid_0_0_20.0']['expected']['bounds'],[10,12,1,1])
        empty=self.cases['grid_0_0.5_20.0']['expected']
        self.assertEqual(empty['bounds'],[11,12,0,0])
        self.assertEqual(empty['events'],[['terrain_overlay',[],0]])
        row=self.cases['grid_2_0.25_20.0']['expected']
        self.assertEqual(row['bounds'],[10,11,2,3])
        self.assertEqual([event[1] for event in row['events'] if event[0]=='ground'],[[10,11],[11,11],[10,12],[11,12],[10,13],[11,13]])

    def test_absolute_mismatch_threshold_is_strict_and_large_anchor_stores_float32(self):
        for raw in ['-0.10000000149011612','0.10000000149011612']:
            self.assertEqual(self.cases['tolerance_'+raw]['expected']['state']['uneven_count'],0)
        for raw in ['-0.10000000894069672','0.10000000894069672']:
            self.assertEqual(self.cases['tolerance_'+raw]['expected']['state']['uneven_count'],1)
        for raw in ['19.0','21.0']:
            self.assertEqual(self.cases['grid_2_0_'+raw]['expected']['state']['uneven_count'],9)
        for anchor in [16777217,2147483647,-2147483648]:
            self.assertEqual(self.cases['anchor_'+str(anchor)]['expected']['state']['uneven_count'],0)

    def test_overlay_success_skips_ground_failure_falls_back_and_counters_reset_first(self):
        for case in self.fixture['cases']:
            events=case['expected']['events']
            self.assertEqual(events[0],['terrain_overlay',[],0])
        success=self.cases['override_True_True_19.0']['expected']
        self.assertNotIn('ground',[event[0] for event in success['events']])
        fallback=self.cases['override_True_False_19.0']['expected']
        self.assertEqual(fallback['state']['uneven_count'],0)
        self.assertIn('ground',[event[0] for event in fallback['events']])
        self.assertEqual(self.cases['mixed_overrides']['expected']['state']['uneven_count'],3)

    def test_attached_reference_suppresses_only_scan_not_mask_refresh(self):
        for case in self.composed['cases']:
            expected=case['expected']
            if case['state']['reference_attached']:
                self.assertFalse(expected['events'])
                self.assertFalse(expected['bounds'])
                self.assertEqual(expected['state']['uneven_count'],case['state']['uneven_count'])
            else:
                self.assertEqual(expected['events'][0][0],'terrain_overlay')
                self.assertEqual(expected['events'][0][2],expected['state']['mask'])
                self.assertEqual(expected['events'][0][3],0)
        self.assertEqual(sum(len(s['steps']) for s in self.fixture['sequences']),48)
        self.assertEqual(sum(len(s['steps']) for s in self.composed['sequences']),48)


if __name__=='__main__':unittest.main()
