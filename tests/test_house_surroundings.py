import json
import unittest

from tools.house_environment import extract
from tools.native_scenery_oracle import ROOT, NativeImage


class HouseSurroundingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = extract()
        cls.fixture = json.loads((ROOT / 'game/tests/fixtures/source_house_surroundings.json').read_text())

    def test_original_refresh_and_query_instructions(self):
        self.assertEqual(self.fixture['executable_sha256'], self.content['executable_sha256'])
        self.assertEqual(self.fixture['native_routines'], self.content['surroundings_routines'])
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        for address, code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
            self.assertNotIn(address, self.fixture['adapters'])
        self.assertEqual(self.content['surroundings']['area_padding'], 2.0)
        self.assertEqual(self.content['surroundings']['beauty_threshold'], 0.5)
        self.assertEqual(len(self.fixture['sequence']['steps']), 12)

    def test_full_pass_queries_base_radius_and_releases_native_order(self):
        full = self.fixture['cases'][0]['expected']
        queries = [event for event in full['events'] if event[0] == 'query']
        self.assertEqual([event[1] for event in queries], [3, 1, 4])
        self.assertEqual(queries[0], ['query', 3, [20, -1.75, 1.25, 2.0, 0, 0, 0, 0, 1, 1], [0, 0, 0]])
        releases = [event[2] for event in full['events'] if event[:2] == ['release', 3]]
        self.assertEqual(releases, [9, 2, 7, 3, 1, 8])
        self.assertEqual(full['pool']['slots']['3']['nearby'], [3, 2, 1])
        self.assertEqual(full['pool']['slots']['1']['nearby'], [0, 0, 0])
        # Negative coordinates truncate toward zero, and the circle is strict.
        samples = [event[1:] for event in full['events'] if event[0] == 'beauty']
        self.assertEqual(samples[:9], [[x, z] for z in [0, 1, 2] for x in [-2, -1, 0]])

    def test_area_refresh_keeps_counts_and_uses_a_strict_boundary(self):
        exact, inside, outside = [self.fixture['cases'][i] for i in [1, 2, 5]]
        self.assertEqual(exact['expected']['pool']['slots']['3']['beauty_fraction'], 0.5)
        self.assertNotEqual(inside['expected']['pool']['slots']['3']['beauty_fraction'], 0.5)
        self.assertEqual(outside['expected']['events'], [])
        for case in [exact, inside, outside]:
            self.assertTrue(all(event[0] in ['beauty', 'blight'] for event in case['expected']['events']))
            for slot, house in case['expected']['pool']['slots'].items():
                self.assertEqual(house['nearby'], case['initial']['slots'][slot]['nearby'])
