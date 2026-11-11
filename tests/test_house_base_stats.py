import json
import unittest

from tools.house_base_stats import extract
from tools.native_scenery_oracle import ROOT, NativeImage


class HouseBaseStatsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = extract()
        cls.fixture = json.loads((ROOT / 'game/tests/fixtures/source_house_base_stats.json').read_text())

    def test_executed_selector_and_settlement_initialization_provenance(self):
        generated = ROOT / 'game/assets/original/campaign/house-base-stats.json'
        self.assertEqual(json.loads(generated.read_text()), self.content)
        self.assertEqual(self.fixture['executable_sha256'], self.content['executable_sha256'])
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        for address, code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
        for address in ['0x100b6750', '0x1013caa0', '0x10026cf0', '0x10407a70',
                        '0x10120ec2', '0x100b7580', '0x100b7e80', '0x1003b690']:
            self.assertIn(address, self.fixture['native_routines'])
            self.assertNotIn(address, self.fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']), 90)
        self.assertEqual(len(self.fixture['frames']), 36)

    def test_attached_rows_overlay_only_five_live_fields(self):
        rules = self.content['rules']
        standalone = {row['index']: row['expected']['values'] for row in self.fixture['cases']
                      if row['attachment'] is None}
        for case in self.fixture['cases']:
            attachment = case['attachment']
            if attachment is None:
                continue
            expected = case['expected']
            kind = attachment['kind']
            slot = rules['kind_slots'][kind] if kind < 10 else rules['default_slot']
            self.assertEqual(expected['slot'], slot)
            self.assertEqual(expected['index'], rules['settlement_rows'][slot])
            if slot == 5:
                self.assertEqual(expected['values'], {})
            else:
                base = standalone[expected['index']]
                self.assertEqual(expected['values'], dict(base, **attachment['values']))
                self.assertEqual(case['index'], 63)

    def test_resolved_rows_feed_source_completion_and_damage(self):
        for frame in self.fixture['frames']:
            original = frame['expected']
            if frame['state']['reference_attached']:
                self.assertEqual(original['target'], 5.5)
            self.assertNotIn('house_stats', [event[0] for event in original['events']])
        homes = [frame for frame in self.fixture['frames'] if frame['state']['house_index'] == 18
                 and not frame['state']['reference_attached'] and not frame['unlocked']]
        self.assertEqual([frame['expected']['target'] for frame in homes], [7.5] * 3)
        self.assertEqual([frame['expected']['state']['state'] for frame in homes], [1, 2, 0])
