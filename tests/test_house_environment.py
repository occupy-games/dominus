import json
import unittest

from tools.house_environment import extract
from tools.native_scenery_oracle import ROOT, NativeImage


class HouseEnvironmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = extract()
        cls.fixture = json.loads((ROOT / 'game/tests/fixtures/source_house_environment.json').read_text())

    def test_source_table_and_original_stat_getter_provenance(self):
        data = ROOT / 'game/assets/original/campaign/house-environment.json'
        self.assertEqual(json.loads(data.read_text()), self.content)
        for name in ['executable_sha256', 'source_sha256']:
            self.assertEqual(self.fixture[name], self.content[name])
        self.assertEqual(self.content['kinds'], {'tree': 0, 'rock': 1, 'beautify': 2, 'godseed': 3})
        self.assertEqual(len(self.content['records']), 6)
        self.assertTrue(all(row['index'] == 25 for row in self.content['records']))
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        for address, code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
        for address in ['0x100b6750', '0x100b7580', '0x100b7210', '0x100b50f0', '0x1015c130']:
            self.assertIn(address, self.fixture['native_routines'])
            self.assertNotIn(address, self.fixture['adapters'])
        self.assertEqual(len(self.fixture['contributions']), 192)
        self.assertEqual(len(self.fixture['stats']), 102)

    def test_source_count_and_beautification_curves_and_caps(self):
        samples = self.fixture['contributions']

        def contribution(kind, cap, sample):
            return next(item['expected'] for item in samples if item['record']['kind'] == kind
                        and item['record']['operation'] == 1 and item['record']['cap'] == cap
                        and item['record']['value'] > 1 and item['sample'] == sample)

        self.assertEqual(contribution(0, 2, 1000), 2)
        self.assertEqual(contribution(1, 1, 15), 1)
        self.assertGreater(contribution(2, 2, 0.75), contribution(2, 2, 0.25))
        self.assertEqual(contribution(3, 2, 0), 1)

    def test_shrine_application_precedes_environment_and_respects_building_kind(self):
        cases = self.fixture['stats']
        applied_after_shrine = next(case for case in cases if case['records'][0]['field'] == 'capacity'
                                     and case['records'][0]['kind'] == 0 and case['records'][0]['operation'] == 1
                                     and case['records'][0]['cap'] == 2 and case['records'][0]['value'] == 1.25)
        self.assertEqual(applied_after_shrine['expected']['values']['capacity'], 5.859375)
        for house_index, relation in [(6, 'equal'), (12, 'greater'), (50, 'equal')]:
            case = next(case for case in cases if case['house']['house_index'] == house_index
                        and case['house']['nearby'] == [7, 3, 12] and len(case['unlocked']) == 3)
            result = case['expected']['values']['belief modifier']
            if relation == 'equal':
                self.assertEqual(result, 1.25)
            else:
                self.assertGreater(result, 1.25)
