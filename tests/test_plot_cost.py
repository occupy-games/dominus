import json
from pathlib import Path
import unittest

from tools.house_selection import extract as selection
from tools.native_scenery_oracle import NativeImage
from tools.plot_cost import extract

ROOT = Path(__file__).resolve().parents[1]


class PlotCostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'game/assets/original/campaign/plot-cost.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_plot_cost.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_original_cost_column_and_instruction_provenance(self):
        self.assertEqual(self.rules,extract())
        source=selection()
        for key in ['source_sha256','table_sha256','executable_sha256','native_routines']:
            self.assertEqual(self.rules[key],self.fixture[key])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address,code in self.rules['counted_house_evidence'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(self.rules['counted_house_states'],[1,4])
        self.assertEqual(self.rules['field']['name'],'Wheat Consumed')
        self.assertEqual(self.rules['field']['offset'],0x108)
        houses=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
        for cost,row in zip(self.rules['costs'],source['rows']):
            self.assertEqual((cost['index'],cost['id']),(row['index'],row['id']))
            self.assertEqual(cost['food'],houses['records'][row['id']]['values']['wheat consumed'])

    def test_original_waivers_and_center_lookup(self):
        self.assertEqual(self.cases['first']['amount'],3.)
        for name in ['no_counted_houses','disabled','settled','negative_count','locked']:
            self.assertEqual(self.cases[name]['amount'],0.,name)
        self.assertEqual(self.cases['locked']['queries'],[])
        self.assertEqual(self.cases['fractional_center']['queries'],[[160.75,122.625,6.]])
        self.assertEqual(self.cases['negative_cost']['amount'],-3.)

    def test_currency_modes_and_signed_64_bit_resources(self):
        for name in ['short','negative_food','negative_int64','fractional_cost']:
            self.assertFalse(self.cases[name]['allowed'],name)
        for name in ['exact','int64','negative_cost']:
            self.assertTrue(self.cases[name]['allowed'],name)
        self.assertTrue(self.cases['negative_ore']['allowed'])
        self.assertFalse(self.cases['negative_ore']['both'])
        self.assertFalse(self.cases['ore_mode']['allowed'])
        self.assertTrue(self.cases['other_mode']['allowed'])
        self.assertFalse(self.cases['other_mode']['both'])
        self.assertEqual(self.rules['rules']['ore_minimum'],0.)
