import json
from pathlib import Path
import unittest

from tools.house_selection import extract
from tools.house_pool import extract as pool_configuration
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class HouseFactoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_house_factory.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_allocator_factory_and_constructor_all_execute(self):
        source=extract()
        for key in ['source_sha256','table_sha256','executable_sha256']:
            self.assertEqual(self.fixture[key],source[key])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address in [0x100441c0,0x10044250,0x10044cb0,0x100bc660,0x1003f610,0x1003e400,0x10044c30,0x100b72c0,0x10237660,0x10044110]:
            self.assertNotIn(hex(address),self.fixture['adapters'])
        # This hook reads constructor inputs without replacing instructions.
        self.assertEqual(self.fixture['observers'],['0x100bc660'])
        for address in [0x100b7580,0x100bb560,0x10124cc0]:
            self.assertIn(hex(address),self.fixture['adapters'])

    def test_original_world_allocation_and_full_initial_free_list(self):
        pool=pool_configuration()
        self.assertEqual(pool,self.fixture['pool_configuration'])
        self.assertEqual(pool,json.loads((ROOT/'game/assets/original/campaign/house-pool.json').read_text()))
        self.assertEqual(pool['header'],'0x10fcd474')
        self.assertEqual(int(pool['world_root'],16)+pool['header_offset'],int(pool['header'],16))
        self.assertEqual(pool['stride'],728)
        self.assertEqual(pool['rules']['capacity'],4096)
        self.assertEqual(pool['allocation_bytes'],4096*728+4)
        self.assertEqual(self.fixture['pool_initialization'],dict(count=0,active=[],free=list(range(4096))))
        self.assertNotIn('0x1019fbc0',self.fixture['adapters'])

    def test_stale_allocated_body_participates_before_reset(self):
        self.assertEqual(self.cases['two_matching']['random_calls'],0)
        self.assertEqual(self.cases['rotation']['random_calls'],1)
        self.assertEqual(self.cases['stale_matching_slot']['random_calls'],1)
        self.assertEqual(self.cases['freed_matching_slot']['random_calls'],1)
        self.assertEqual(self.cases['freed_matching_slot']['house_id'],1)
        self.assertEqual(self.cases['free_head_order']['house_id'],3)
        self.assertEqual(self.cases['free_head_order']['pool'],dict(count=3,active=[3,2,0],free=[1,4,5,6,7]))
        self.assertEqual(self.cases['stale_matching_slot']['request']['position'][3],self.cases['rotation']['request']['position'][3])

    def test_exhaustion_reconstruction_and_initialized_footprint(self):
        failed=self.cases['full']
        self.assertFalse(failed['created'])
        self.assertIsNone(failed['request'])
        self.assertIsNone(failed['core'])
        self.assertEqual(failed['ground_queries'],[])
        self.assertEqual(failed['pool'],dict(count=2,active=[1,0],free=[]))
        self.assertEqual(len(failed['registry']['plots']),1)
        reuse=self.cases['reuse']
        self.assertTrue(reuse['created'])
        self.assertEqual(reuse['pool']['active'],[0])
        self.assertEqual(len(reuse['registry']['plots']),1)
        self.assertEqual(reuse['core']['occupied'],[])
        self.assertEqual(reuse['dirty'],[])
        for name in ['first','farm','mine']:
            case=self.cases[name]
            self.assertEqual(case['registry']['plots'],[])
            self.assertEqual(len(case['core']['occupied']),16)
            self.assertEqual(case['core']['next_identity'],1)
        self.assertEqual(self.cases['farm']['request']['index'],6)
        self.assertEqual(self.cases['mine']['request']['index'],12)
