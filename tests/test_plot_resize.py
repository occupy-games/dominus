import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.native_scenery_oracle import NativeImage
from tools.plot_resize import extract

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'game/assets/original/campaign'


class PlotResizeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata=json.loads((DIRECTORY/'plot-resize-rules.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_plot_resize.json').read_text())

    def test_source_tables_and_instruction_provenance(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        image=NativeImage(raw)
        for record in [self.metadata,self.fixture]:
            self.assertEqual(hashlib.sha256(raw).hexdigest(),record['executable_sha256'])
            for address,code in record['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for name,count in [('growth',768),('repair',4096)]:
            info=self.metadata[name]
            payload=(ROOT/'game/assets/original'/info['path']).read_bytes()
            self.assertEqual(len(payload),count)
            self.assertEqual(hashlib.sha256(payload).hexdigest(),info['sha256'])
            self.assertTrue(all(code<64 and code&3!=3 and (code>>2)&3!=3 for code in payload))
        # No original eligibility, resize-choice or footprint-register loop is
        # replaced by an adapter in the complete-iteration observations.
        for address in [0x10236510,0x10236610,0x10236720,0x10237580,0x10237660]:
            self.assertNotIn(hex(address),self.fixture['adapters'])

    def test_native_growth_repair_and_claimed_plot_observations(self):
        cases={case['name']:case['expected'] for case in self.fixture['cases']}
        self.assertEqual(len(cases),64)
        self.assertEqual([cases['flat']['plots'][0][key] for key in ['x','z','size']],[159.,119.,6])
        self.assertEqual([cases['one_size_available']['plots'][0][key] for key in ['x','z','size']],[159.,120.,5])
        self.assertEqual(cases['valid_claimed']['plots'][0]['size'],4)
        self.assertTrue(cases['valid_claimed']['plots'][0]['claimed'])
        self.assertEqual([cases['border_lost']['plots'][0][key] for key in ['x','z','size']],[160.,121.,4])
        self.assertEqual(cases['interior_lost']['plots'][0]['size'],0)
        self.assertEqual(cases['interior_lost']['owners'],{})
        self.assertEqual(cases['flat']['revisit'],[0])
        self.assertEqual(cases['at_maximum']['revisit'],[])

    def test_setup_regenerates_every_native_branch_result(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            metadata = extract(output=output)
            for kind, digest in [
                ('growth', '2e929dbbd7351d512a5377ddaa9ee048019266679bdd5c8d251750349942d07c'),
                ('repair', '5a3954dfac913d7e25cea52b45bf559c758bffd04044f20a84f1091e5c8868dd'),
            ]:
                filename = f'plot-{kind}-decisions.bin'
                payload = (output / filename).read_bytes()
                self.assertEqual(payload, (DIRECTORY / filename).read_bytes())
                self.assertEqual(hashlib.sha256(payload).hexdigest(), digest)
                self.assertEqual(metadata[kind]['sha256'], digest)
