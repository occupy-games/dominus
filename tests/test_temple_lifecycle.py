import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_terrain import extract
from tools.temple_membership import extract as membership_content


class TempleLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_lifecycle.json').read_text())
        cls.cases={row['name']:row for row in cls.fixture['cases']}

    def test_actual_contiguous_membership_frame_and_work_execute(self):
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        self.assertEqual(self.fixture['executable_sha256'],extract()['executable_sha256'])
        self.assertEqual(self.fixture['source_sha256'],membership_content()['source_sha256'])
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in ['0x10140c0f','0x1013f080','0x10153d80','0x10140d1e','0x1003b550','0x10141204']:
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']),176)
        self.assertEqual(sum(len(s['steps']) for s in self.fixture['sequences']),128)

    def test_membership_order_and_strict_timer_survive_the_later_passes(self):
        for name,owner in [('order_4,7',5),('order_7,4',2),('order_',-1)]:
            result=self.cases[name]['expected']
            self.assertEqual(result['state']['settlement_id'],owner)
            self.assertEqual(result['state']['affiliation_due'],12)
            self.assertEqual((result['clock_calls'],result['random_calls']),(2,1))
        due=self.cases['timed_-1.0_-1_False_True']['expected']
        equal=self.cases['timed_0.0_-1_False_True']['expected']
        self.assertTrue(due['refreshed'])
        self.assertFalse(equal['refreshed'])
        self.assertEqual(due['state']['timer'],equal['state']['timer'])

    def test_modifier_changes_reach_same_tick_height_and_completion(self):
        for name in ['modifier_0.0','modifier_2.0']:
            result=self.cases[name]['expected']
            self.assertEqual(result['state']['phase'],7)
            self.assertEqual(result['state']['height_ceiling'],5.5)
            self.assertEqual(result['events'][0][0],'refresh_modifiers')
            names=[event[0] for event in result['events']]
            self.assertLess(names.index('clock'),names.index('spatial_refresh'))
            self.assertLess(names.index('spatial_refresh'),names.index('completion_visual'))
            self.assertIn('move_vertical',names)


if __name__=='__main__':unittest.main()
