import hashlib
import json
from pathlib import Path
import unittest

from tools.build_candidates import extract
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class BuildCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'game/assets/original/campaign/build-candidates.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_build_candidates.json').read_text())

    def test_source_inheritance_and_instruction_provenance(self):
        self.assertEqual(self.rules,extract())
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        image=NativeImage(raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        for field in ['source_sha256','table_sha256','executable_sha256','native_routines']:
            self.assertEqual(self.rules[field],self.fixture[field])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        for address in [0x100cd790,0x100b72c0,0x100791e0,0x100ca310,0x1016adb0,0x102d5a70]:
            self.assertNotIn(hex(address),self.fixture['adapters'])
        self.assertEqual(self.rules['fields']['build capacity']['offset'],0x44)
        self.assertEqual(self.rules['fields']['buildplotpriority']['offset'],0xdc)
        # The native frame receives the power/max flag, distinct from the
        # fresh-plot construction gate. Both are explicit oracle inputs.
        self.assertEqual(image.read(0x100cd8de,2).hex(),'6a01')

    def test_native_capacity_ties_and_nonmutating_selected_flag(self):
        cases={c['name']:c['expected'] for c in self.fixture['cases']}
        self.assertEqual(cases['full']['action'],250)
        self.assertEqual(cases['reserved_only'],cases['first_plot'])
        self.assertEqual(cases['selected_plot_flag'],cases['first_plot'])
        self.assertEqual(cases['equal_first_wins']['plot'],0)
        self.assertEqual(cases['equal_reversed']['plot'],1)
        for name in ['disabled','actor_mode_six','locked','outside_influence']:
            self.assertEqual(cases[name],dict(action=250,plot=-1,center=[],score=0.))

    def test_all_values_are_original_resolved_house_inputs(self):
        houses=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
        self.assertEqual(set(houses['records']),set(self.rules['values']))
        for key,values in self.rules['values'].items():
            self.assertEqual(values,{field:houses['records'][key]['values'][field]
                                     for field in ['build capacity','buildplotpriority']})
        self.assertEqual(self.rules['values']['AbodeType_0_Rank_1'],
                         {'build capacity':1.,'buildplotpriority':0.08250000327825546})
