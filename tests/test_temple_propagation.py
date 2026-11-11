import json
import unittest

from tools.native_scenery_oracle import ROOT,NativeImage
from tools.temple_effects import extract


class TemplePropagationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_propagation.json').read_text())
        cls.cases={row['name']:row for row in cls.fixture['cases']}
        cls.houses=json.loads((ROOT/'game/tests/fixtures/source_temple_house_propagation.json').read_text())

    def test_actual_active_loops_containment_release_and_getters_execute(self):
        self.assertEqual(self.fixture['executable_sha256'],self.content['executable_sha256'])
        self.assertEqual(self.fixture['source_sha256'],self.content['source_sha256'])
        self.assertEqual(self.fixture['rules'],self.content['propagation_rules'])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x1006d050','0x1013f080','0x10153d80','0x100342a0','0x100343b0']:
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertIn('0x1012ec90',self.fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']),75)

    def test_referenced_masks_clear_but_permanent_and_unreferenced_state_remain(self):
        case=self.cases['no_sites'];result=case['expected']['state']
        for identity in ['0','1','2']:
            self.assertEqual(result['actors'][identity]['mask'],[0,0])
            self.assertEqual(result['actors'][identity]['extra_mask'],case['state']['actors'][identity]['extra_mask'])
        self.assertEqual(result['actors']['9'],case['state']['actors']['9'])
        self.assertEqual(self.cases['no_attached_actors']['expected']['state'],self.cases['no_attached_actors']['state'])

    def test_candidate_service_order_and_releases_are_not_replaced_by_full_scan(self):
        case=self.cases['ordinary'];events=case['expected']['events']
        self.assertEqual(events[0][0:2],['query',[4096,10,12,12,0,0,0,0,1,1]])
        self.assertEqual(events[0][2]['0']['mask'],[0,0])
        self.assertEqual([event[1][0] for event in events if event[0]=='release_candidate'],[0,1,2,3,4,5,10,11,12,13])
        self.assertEqual(self.cases['query_omits_contained']['expected']['state']['actors']['0']['mask'],[0,0])
        self.assertEqual(self.cases['ordinary']['expected']['state']['actors']['0']['mask'],[3,0x80000000])
        self.assertFalse(self.cases['zero_masks']['expected']['events'])

    def test_broad_phase_uses_local_geometry_then_actual_containment_inherits(self):
        case=self.cases['inherited_False'];result=case['expected']
        self.assertEqual(result['events'][0][1][1:4],[10,12,12])
        self.assertEqual(case['state']['followers'][0]['position'],[100,12,6])
        self.assertEqual(result['state']['actors']['0']['mask'],[3,0x80000000])
        self.assertEqual(result['state']['actors']['1']['mask'],[0,0])
        self.assertEqual(self.cases['inherited_True']['expected']['state']['actors']['0']['mask'],[0,0])
        self.assertEqual(sum(len(sequence['steps']) for sequence in self.fixture['sequences']),64)

    def test_house_wrapper_refreshes_masks_before_the_reference_gated_callback(self):
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        self.assertEqual(self.houses['executable_sha256'],self.content['executable_sha256'])
        self.assertEqual(self.houses['source_sha256'],self.content['source_sha256'])
        for address,code in self.houses['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x100b6e10','0x100b6d60','0x1013f080','0x100b7580']:self.assertNotIn(address,self.houses['adapters'])
        for case in self.houses['cases']:
            expected=case['expected']
            self.assertEqual(len(expected['events']),int(not case['state']['reference_attached']))
            for event in expected['events']:
                self.assertEqual(event[0],'refresh_house_geometry')
                self.assertEqual(event[2],expected['state']['mask'])
        self.assertEqual(len(self.houses['cases']),118)
        self.assertEqual(sum(len(sequence['steps']) for sequence in self.houses['sequences']),32)


if __name__=='__main__':unittest.main()
