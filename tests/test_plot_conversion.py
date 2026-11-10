import hashlib
import json
from pathlib import Path
import struct
import unittest

from tools.house_selection import extract as selection
from tools.native_scenery_oracle import NativeImage
from tools.plot_conversion import extract

ROOT = Path(__file__).resolve().parents[1]


class PlotConversionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'game/assets/original/campaign/plot-conversion.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_plot_conversion.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_native_instructions_constants_and_input_provenance(self):
        self.assertEqual(self.rules,extract())
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        image=NativeImage(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        inputs=selection()
        for key in ['source_sha256','table_sha256','executable_sha256']:
            self.assertEqual(self.fixture[key],inputs[key])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for key,constant in self.rules['constants'].items():
            address=constant['address']
            self.assertEqual(self.fixture['constants'][address]['bytes'],constant['bytes'])
            self.assertEqual(struct.unpack('<d',bytes.fromhex(constant['bytes']))[0],self.rules['rules'][key])
        # Selection, placement, matching-house scan, footprint removal, dirty
        # marking and pool release all execute; the house itself is not ported
        # by this constructor-request comparison.
        for address in [0x100b72c0,0x102358e0,0x1025e0d0,0x1035f830]:
            self.assertNotIn(hex(address),self.fixture['adapters'])
        for address in [0x100bc660,0x100441c0]:
            self.assertIn(hex(address),self.fixture['adapters'])
        self.assertEqual(image.read(0x1035f830,10).hex(),'3b0d984362107502f3c3')

    def test_success_failure_and_reuse_keep_native_pool_semantics(self):
        for name,expected in self.cases.items():
            self.assertEqual(expected['created'],name!='allocation_failed',name)
            if name=='allocation_failed':
                self.assertIsNone(expected['request'])
                self.assertEqual(expected['ground_queries'],[])
                self.assertEqual(expected['random_calls'],0)
            retained=name in ['allocation_failed','reuse']
            self.assertEqual([p['id'] for p in expected['registry']['plots']],[0] if retained else [],name)
            self.assertEqual(expected['dirty'],[] if retained else [67,68,69,99,100,101,131,132,133],name)
            self.assertEqual(expected['registry']['free'][0],1 if retained else 0,name)
        self.assertEqual(self.cases['first']['request']['index'],18)
        # Index zero remains an unsupported raw native request, never a
        # fabricated fallback house or art asset.
        self.assertEqual(self.cases['height_boundary']['request']['index'],0)

    def test_matching_house_rotation_and_exact_random_consumption(self):
        angles=[]
        for word in [0,8191,8192,16383,16384,24575,24576,32767]:
            expected=self.cases[f'matching_3_{word}']
            self.assertEqual(expected['random_calls'],1)
            quarter=((word&0x7fff)*4)>>15
            angle=struct.unpack('<f',struct.pack('<f',quarter*self.rules['rules']['pi']*.5))[0]
            self.assertEqual(expected['request']['position'][3],angle)
            angles.append(angle)
        self.assertEqual(len(set(angles)),4)
        for name in ['first','matching_1_16384','matching_2_16384','other_owner','different_types']:
            self.assertEqual(self.cases[name]['random_calls'],0,name)
        self.assertEqual(self.cases['matching_4_16384']['random_calls'],1)
        self.assertEqual(self.cases['offset']['ground_queries'],[[160.25,121.625]])
