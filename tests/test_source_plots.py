import hashlib
import json
from pathlib import Path
import struct
import unittest

from tools.native_scenery_oracle import NativeImage
from tools.native_plot_oracle import scenery_cells

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT/'game/assets/original/campaign'


class SourcePlotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_plot_masks.json').read_text())

    def test_native_comparison_inputs_and_instruction_provenance(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for kind in ['terrain','scenery']:
            self.assertEqual(hashlib.sha256((DIRECTORY/('homeworld6-'+kind+'.bin')).read_bytes()).hexdigest(),self.fixture[kind+'_sha256'])
        self.assertEqual(struct.unpack('<f',image.read(0x104acfb8,4))[0],self.fixture['minimum_raw_height'])
        self.assertEqual(self.fixture['minimum_raw_height'],19)
        self.assertEqual(self.fixture['max_size'],16)
        self.assertEqual(image.read(0x1025e9f3,3),b'\x83\xf8\x10')

    def test_independent_original_clearing_and_sculpting_observations(self):
        by_name={case['name']:case for case in self.fixture['cases']}
        self.assertEqual(set(by_name),{'initial','cleared','sculpted'})
        values={name:bytes.fromhex(case['capacities']) for name,case in by_name.items()}
        for data in values.values():
            self.assertEqual(len(data),4096)
            self.assertLessEqual(max(data),16)
        def at(name,x,z): return values[name][(z-96)*64+x-128]
        self.assertEqual([at(name,159,121) for name in ['initial','cleared','sculpted']],[1,3,3])
        self.assertEqual([at(name,158,120) for name in ['initial','cleared','sculpted']],[2,2,4])
        self.assertEqual(by_name['sculpted']['terrain_edits'],[[161,120,20]])
        # Native spatial lookup includes the registered plot radius, including
        # exact tangency. It is not a nearest-center-only search.
        self.assertEqual([query['intersects'] for query in self.fixture['queries']],
                         [True,True,False,True,False,True])

    def test_masks_use_whole_original_objects(self):
        payload=(DIRECTORY/'homeworld6-scenery.bin').read_bytes()
        initial=set(scenery_cells(payload))
        cleared=set(scenery_cells(payload,True))
        self.assertEqual(initial-cleared,{z*1024+x for z in [122,123] for x in [160,161]})
        self.assertEqual(len(initial),8001)
        self.assertEqual(len(cleared),7997)
        with self.assertRaisesRegex(ValueError,'Truncated'): scenery_cells(payload[:-1])
