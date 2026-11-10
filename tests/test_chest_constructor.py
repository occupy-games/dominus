import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.storm_chests import extract


class ChestConstructorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_chest_constructor.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_original_constructor_and_factory_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(NativeImage(raw).read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
            self.assertNotIn(address,self.fixture['composed_adapters'])
        self.assertEqual(self.fixture['observation_hooks'],['0x101523c0'])
        self.assertIn('0x1012ddd0',self.fixture['adapters'])

    def test_original_burial_clamp_and_timers(self):
        minimum=self.content['core_rules']['minimum_height']
        for case in self.fixture['cases']:
            expected=case['expected']
            record=expected['record']
            self.assertGreaterEqual(record['position'][2],minimum)
            self.assertEqual(record['base_height'],record['position'][2])
            self.assertEqual(expected['source_id'],7)
            self.assertEqual(expected['untouched_reward'],74565)
            self.assertEqual(expected['untouched_depth'],123.25)
            self.assertEqual(expected['random_calls'],1)
        self.assertEqual(self.cases['timer_0']['record']['source_slots']['9c'],4.)
        self.assertEqual(self.cases['timer_32767']['record']['source_slots']['9c'],8.)
        self.assertEqual(self.cases['kind_0_height_0.0_depth_3.0']['record']['position'][2],minimum)

    def test_original_spatial_endpoints_and_composed_rng(self):
        self.assertFalse(self.cases['spatial_-1.0_120.0']['record']['registered'])
        self.assertTrue(self.cases['spatial_-0.5_120.0']['record']['registered'])
        self.assertTrue(self.cases['spatial_1024.0_1024.0']['record']['registered'])
        self.assertTrue(self.cases['spatial_1024.5_120.0']['record']['registered'])
        self.assertFalse(self.cases['spatial_1025.0_120.0']['record']['registered'])
        for case in self.fixture['composed']:
            expected=case['expected']
            if case['name']=='allocation_failed':
                self.assertEqual(expected['events'],[['allocate']])
                self.assertEqual(expected['random_calls'],0)
                continue
            self.assertEqual(expected['random_calls'],2)
            self.assertEqual(expected['source_id'],0)
            self.assertEqual(expected['events'][-1][1],expected['record']['position'])
        ordinary=next(c['expected'] for c in self.fixture['composed'] if c['name']=='ordinary')
        self.assertNotEqual(ordinary['request']['position'],ordinary['record']['position'])

    def test_authored_id_and_opening_phase_have_separate_native_fields(self):
        fields=self.content['field_layout']
        self.assertEqual(fields['source_id']['offset'],4)
        self.assertEqual(fields['source_id']['column'],'ID')
        self.assertEqual(fields['phase']['offset'],0x60)
        self.assertEqual(fields['elapsed']['offset'],0x58)
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        image=NativeImage(raw)
        for name,address in [('source_id','loader'),('phase','opening'),('elapsed','reset')]:
            field=fields[name]
            self.assertEqual(image.read(int(field[address],16),len(field['bytes'])//2).hex(),field['bytes'])
        self.assertEqual(fields['source_id']['bytes'],'8b47f8894604')
        self.assertEqual(fields['phase']['bytes'],'b801000000894660')


if __name__=='__main__':unittest.main()
