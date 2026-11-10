import hashlib
import json
from pathlib import Path
import unittest

from tools.native_scenery_oracle import NativeImage

ROOT=Path(__file__).resolve().parents[1]


class ExistingPlotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_existing_plots.json').read_text())

    def test_native_instruction_provenance(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items(): self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertNotIn('0x102363c0',self.fixture['adapters'])
        self.assertNotIn('0x10236370',self.fixture['adapters'])
        self.assertNotIn('0x101454a0',self.fixture['adapters'])

    def test_native_claim_and_rotation_boundaries(self):
        def find(**values):
            return next(c['expected'] for c in self.fixture['cases'] if all(c[k]==v for k,v in values.items()))
        baseline=dict(flat=True,scenery=False,blocked=False,origin_byte=0,cell_byte=0,blight=0.,biome_mask=1)
        self.assertEqual(find(cell=[161,121],owner='self',**baseline),{'cell':True,'whole':True,'interior':True})
        # An unclaimed neighbor may qualify for expansion, but ownership of
        # this plot's existing whole/interior footprint is a different test.
        self.assertEqual(find(cell=[161,121],owner='unclaimed',**baseline),{'cell':True,'whole':False,'interior':False})
        self.assertFalse(find(cell=[161,121],owner='claimed',**baseline)['cell'])
        self.assertEqual(find(cell=[160,120],owner='none',**baseline),{'cell':True,'whole':False,'interior':True})
        common=dict(cell=[161,121],owner='self',flat=True,scenery=False,blocked=False,origin_byte=0,blight=1.,biome_mask=1)
        self.assertTrue(find(cell_byte=18,**common)['cell'])
        for byte in [19,20,21]: self.assertFalse(find(cell_byte=byte,**common)['cell'])
        self.assertTrue(find(cell_byte=22,**common)['cell'])
