import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_membership import extract


class TempleMembershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_membership.json').read_text())
        cls.geometry={row['name']:row for row in cls.fixture['geometry']}
        cls.cases={row['name']:row for row in cls.fixture['cases']}

    def test_source_radii_and_instruction_captures_are_reproducible(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/temple-membership.json').read_text()))
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
        self.assertEqual(self.fixture['executable_sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(self.content['native_routines'],self.fixture['native_routines'])
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x10140c0f','0x1013f080','0x10153d80']:self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(self.content['radii']['Settlement_Builder'],12)
        self.assertEqual(self.content['radii']['Settlement_Farming'],12)
        self.assertEqual(self.content['radius_binding']['record_offset'],0x10)

    def test_settlement_circle_and_inherited_sphere_keep_their_distinct_boundaries(self):
        self.assertTrue(self.geometry['boundary_True_True_12.0_22_12_6']['expected'])
        self.assertFalse(self.geometry['boundary_False_True_12.0_22_12_6']['expected'])
        self.assertTrue(self.geometry['boundary_True_False_12.0_10_12_100']['expected'])
        self.assertFalse(self.geometry['boundary_False_True_12.0_10_12_100']['expected'])
        self.assertFalse(self.geometry['missing_owner']['expected'])

    def test_last_matching_active_settlement_wins_but_existing_owners_are_kept(self):
        self.assertEqual(self.cases['order_4,7']['expected']['state']['settlement_id'],5)
        self.assertEqual(self.cases['order_7,4']['expected']['state']['settlement_id'],2)
        self.assertEqual(self.cases['gate_2_False_-1.0_0']['expected']['state']['settlement_id'],2)

    def test_not_due_and_modifier_changed_deadlines_do_not_draw_randomness(self):
        for name in ['gate_-1_False_1.0_32767','gate_-1_False_0.0_32767','modifier_delays_refresh']:
            result=self.cases[name]['expected']
            self.assertEqual((result['random_calls'],result['clock_calls']),(0,1))
        low=self.cases['gate_-1_False_-1.0_0']['expected']['state']['affiliation_due']
        high=self.cases['gate_-1_False_-1.0_32767']['expected']['state']['affiliation_due']
        self.assertEqual((low,high),(10,15))
        self.assertEqual(self.cases['order_4,7']['expected']['state']['affiliation_due'],26)


if __name__=='__main__':unittest.main()
