import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_terrain import extract


class TempleFrameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.frame=json.loads((ROOT/'game/tests/fixtures/source_temple_frame.json').read_text())
        cls.repair=json.loads((ROOT/'game/tests/fixtures/source_temple_frame_repair.json').read_text())
        cls.frames={row['name']:row for row in cls.frame['cases']}
        cls.repairs={row['name']:row for row in cls.repair['cases']}

    def test_captures_execute_the_frame_scan_and_repair_instructions(self):
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for fixture in [self.frame,self.repair]:
            self.assertEqual(fixture['executable_sha256'],self.content['executable_sha256'])
            for address,code in fixture['native_routines'].items():
                self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            for address in ['0x10140d1e','0x1003b550','0x10141204']:
                self.assertNotIn(address,fixture['adapters'])
        self.assertEqual(len(self.frame['cases']),276)
        self.assertEqual(len(self.repair['cases']),99)

    def test_forced_decay_does_not_require_a_terrain_obstruction(self):
        result=self.frames['phase_8_True_1_19']['expected']['state']
        self.assertEqual(result['obstruction'],0)
        self.assertEqual(result['timer'],.5)
        self.assertEqual(self.content['frame_rules']['forced_decay_rate'],5)

    def test_passive_work_and_restoration_feed_actual_same_frame_completion(self):
        complete=self.repairs['passive_only_59.0']['expected']['state']
        waiting=self.repairs['no_passive_59.0']['expected']['state']
        self.assertEqual((complete['phase'],complete['progress'],complete['reward_pending']),(7,60,1))
        self.assertEqual((waiting['phase'],waiting['progress'],waiting['reward_pending']),(6,59,0))
        restored=self.repairs['work_8_19_False_0']['expected']['state']
        self.assertEqual(restored['phase'],7)
        self.assertEqual(restored['reward_pending'],1)

    def test_completion_sound_uses_the_height_after_native_rise(self):
        row=self.repairs['no_passive_60.0']
        result=row['expected']
        self.assertGreater(result['state']['height'],row['state']['height'])
        sound=next(event for event in result['events'] if event[0]=='sound')
        self.assertEqual(sound[1][1],[result['state'][axis] for axis in ['x','z','height']])
        self.assertLess([e[0] for e in result['events']].index('spatial_refresh'),[e[0] for e in result['events']].index('sound'))


if __name__=='__main__':unittest.main()
