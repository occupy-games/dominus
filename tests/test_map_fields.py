import json
import unittest

from tools.house_environment import extract
from tools.native_scenery_oracle import ROOT, NativeImage


class MapFieldsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = extract()
        cls.fixture = json.loads((ROOT / 'game/tests/fixtures/source_map_fields.json').read_text())

    def test_reads_writes_notifications_and_house_scan_execute_native_code(self):
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        self.assertEqual(self.fixture['executable_sha256'], self.content['executable_sha256'])
        self.assertEqual(self.content['field_scale'], {'encode': 128.0, 'decode': 1 / 128})
        self.assertEqual(self.fixture['native_routines'],
                         self.content['field_routines'] | self.content['surroundings_routines'])
        for address, code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
            self.assertNotIn(address, self.fixture['adapters'])

    def test_values_wrap_at_byte_storage_and_blight_reads_the_greater_layer(self):
        self.assertEqual(len(self.fixture['probes']), 18)
        stages = [stage['expected'] for stage in self.fixture['sequence']]
        self.assertEqual(stages[0]['reads'][:4], [64 / 128, 65 / 128, 255 / 128, 0])
        self.assertEqual(stages[1]['reads'][4:7], [0.25, 1.5, 1.5])
        self.assertEqual(stages[2]['reads'][4:7], [1.75, 1.5, 1.75])
        self.assertEqual(stages[3]['reads'][8:12], [1, 1, 0, 0])
        self.assertEqual(stages[4]['reads'][:2], [0.5, 1.0])
        self.assertEqual(stages[4]['reads'][12], 1)
        self.assertEqual(stages[-1]['serial'], 145)
        self.assertEqual(len(stages[-1]['cells']), 128)

    def test_house_refresh_reads_the_same_storage(self):
        houses = self.fixture['surroundings']['expected']['slots']
        self.assertEqual(houses['3']['beauty_fraction'], 0.1111111119389534)
        self.assertEqual(houses['1']['beauty_fraction'], 0.095238097012043)
        self.assertEqual(houses['4']['beauty_fraction'], 0.5)
