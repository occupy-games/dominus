import hashlib
import json
from pathlib import Path
import unittest

from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class ConstructionWorkTests(unittest.TestCase):
    def test_original_work_capture_instruction_provenance(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_construction.json').read_text())
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),fixture['executable_sha256'])
        image=NativeImage(raw)
        for address,code in fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(set(fixture['adapters']),{'0x100b7580','0x10245d30'})
        cases=fixture['cases']
        self.assertEqual(len(cases),12)
        self.assertEqual(cases[0]['result'],0)
        self.assertAlmostEqual(cases[1]['result'],.1,places=7)
        self.assertAlmostEqual(cases[4]['result'],.2,places=7)
        self.assertAlmostEqual(cases[6]['result'],cases[2]['result']*1.5,places=7)
