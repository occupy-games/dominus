import json
from pathlib import Path
import unittest

from tools.tree_response import extract
from tools.native_scenery_oracle import NativeImage

ROOT=Path(__file__).resolve().parents[1]


class TreeResponseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_tree_response.json').read_text())

    def test_native_configuration_and_instruction_provenance(self):
        data=extract()
        self.assertEqual(data,self.fixture['configuration'])
        self.assertEqual(data,json.loads((ROOT/'game/assets/original/campaign/tree-response.json').read_text()))
        self.assertAlmostEqual(data['duration'],.6)
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in data['native_routines'].items(): self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(self.fixture['adapters'],['0x10144780','0x10144790','0x101450b0','0x1035f830'])

    def test_native_occupancy_and_identity_are_distinct(self):
        cases={c['name']:c for c in self.fixture['cases']}
        self.assertEqual(len(cases),7)
        restored=cases['raise_restore']['states']
        self.assertEqual([s[0]['enabled'] for s in restored],[False,False,True,True])
        self.assertEqual([s[0]['changed_ms'] for s in restored],[10000.,10000.,10200.,10200.])
        self.assertEqual([s[0]['enabled'] for s in cases['zero_reenable']['states']],[False,True,True,True])
        for case in cases.values():
            for states in case['states']:
                for i,entry in enumerate(states):
                    self.assertEqual(entry['occupied'],entry['enabled'])
                    self.assertEqual(entry['identity'],i)
                    self.assertEqual(entry['height'],6.)
        self.assertEqual(len(self.fixture['scale_cases']),162)
        self.assertTrue(all(s['scale']==0 for s in self.fixture['scale_cases'] if not s['enabled']))
