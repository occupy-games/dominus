import json
import unittest

from tools.house_terrain_frame import extract
from tools.native_scenery_oracle import ROOT, NativeImage


class HouseTerrainFrameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = extract()
        cls.fixture = json.loads((ROOT / 'game/tests/fixtures/source_house_terrain_frame.json').read_text())
        cls.composed = json.loads((ROOT / 'game/tests/fixtures/source_house_build_time.json').read_text())
        cls.cases = {row['name']: row['expected'] for row in cls.fixture['cases']}

    def test_metadata_and_executed_routines_match_source(self):
        path = ROOT / 'game/assets/original/campaign/house-terrain-frame.json'
        self.assertEqual(json.loads(path.read_text()), self.content)
        self.assertEqual(self.fixture['executable_sha256'], self.content['executable_sha256'])
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        for address, code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
        for address in ['0x100bb96b', '0x1003b690', '0x10357040', '0x102d5a80', '0x10356fd0']:
            self.assertIn(address, self.fixture['native_routines'])
            self.assertNotIn(address, self.fixture['adapters'])
        self.assertEqual(len(self.fixture['cases']), 244)
        self.assertEqual(sum(len(s['steps']) for s in self.fixture['sequences']), 64)

    def test_damage_waits_past_limit_and_removes_only_one_variant(self):
        for attached, limit in [(False, 1.0), (True, 0.5)]:
            exact = self.cases[f'threshold_{attached}_{limit}_0_1']
            self.assertEqual(exact['events'], [])
            self.assertEqual(exact['state']['damage_timer'], limit)
            over = self.cases[f'threshold_{attached}_{limit + 0.125}_0_1']
            self.assertEqual([event[0] for event in over['events']], ['destruction_economy', 'stop_damage_effect'])
        loss = self.cases['one_variant_per_frame']
        self.assertEqual(loss['state']['variant'], 6)
        self.assertEqual(loss['state']['damage_timer'], 0.0)
        self.assertEqual([event[0] for event in loss['events']], ['refresh_variant'])

    def test_terrain_override_and_conversion_order(self):
        for name, phase, count in [('overlay_prevents_damage', 0, 0), ('lowered_override_starts_damage', 2, 4)]:
            case = self.cases[name]
            self.assertEqual(case['state']['state'], phase)
            self.assertEqual(case['state']['uneven_count'], count)
            self.assertNotIn('ground', [event[0] for event in case['events']])
        damaged = self.cases['damage_uses_saved_progress']
        self.assertEqual(damaged['state']['progress'], 0.0)
        self.assertEqual(damaged['state']['damage_timer'], 0.3999999761581421)
        restored = self.cases['recovery_reads_new_timer']
        self.assertEqual(restored['state']['progress'], 3.75)
        self.assertEqual(restored['state']['restore_requested'], 1)
        self.assertEqual([event[0] for event in restored['events']], ['stop_damage_effect', 'construction_target'])

    def test_completion_uses_saved_work_and_emits_original_callbacks_once(self):
        self.assertEqual(self.cases['work_5.0_0']['state']['state'], 0)
        completed = self.cases['completion_uses_saved_progress']
        self.assertEqual(completed['state']['progress'], 0.0)
        self.assertEqual(completed['state']['state'], 1)
        self.assertEqual(completed['state']['post_complete_timer'], 0.0)
        self.assertEqual([event[:2] for event in completed['events']], [
            ['construction_target', []],
            ['sound', [0x33cbd896, [10.25, 12.5, 6.0], 0, 7, 0]],
            ['hook', ['abodecomplete', 0x04000003]],
            ['clock', [0]],
        ])
        for sequence in self.fixture['sequences']:
            hooks = [event for step in sequence['steps'] for event in step['expected']['events'] if event[0] == 'hook']
            self.assertEqual(len(hooks), 1)
            self.assertEqual(sequence['steps'][-1]['expected']['state']['state'], 1)

    def test_native_modifier_order_and_target_lookup_execute(self):
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        self.assertEqual(self.composed['executable_sha256'], self.content['executable_sha256'])
        for address, code in self.composed['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
        for address in ['0x100b7e80', '0x101b3181', '0x10437ec0', '0x1015c1e0']:
            self.assertIn(address, self.composed['native_routines'])
            self.assertNotIn(address, self.composed['adapters'])
        self.assertEqual(len(self.composed['cases']), 120)
        self.assertEqual(len(self.composed['sequence']['steps']), 20)
        descriptor_names = [row['unlock'] for row in self.content['modifiers']['descriptors']]
        for case in self.composed['cases']:
            self.assertEqual(case['expected']['modifiers']['queries'], descriptor_names)
            if case['name'].endswith('_override'):
                self.assertEqual(case['expected']['target'], 4.0)
                self.assertNotIn('house_stats', [event[0] for event in case['expected']['events']])
            elif case['name'].endswith('_restore'):
                self.assertEqual(case['expected']['target'], 6.0)
                self.assertEqual(case['expected']['state']['progress'], 3.0)

    def test_farm_discount_requires_special_flag_and_resolved_kind(self):
        targets = {}
        for case in self.composed['cases']:
            name = case['name']
            if name.endswith('_flat') and len(case['unlocked']) == 3:
                targets[name.split('_3_')[0]] = case['expected']['target']
        self.assertEqual(targets, {
            'abode': 24.0, 'farm': 7.199999809265137, 'mine': 8.0,
            'attached_farm': 7.199999809265137, 'attached_mine': 8.0,
            'non_special_farm': 8.0,
        })
        steps = self.composed['sequence']['steps']
        self.assertEqual(steps[1]['expected']['modifiers']['values']['build_time'], 0.800000011920929)
        self.assertEqual(steps[2]['expected']['target'], steps[1]['expected']['target'])
        self.assertEqual(steps[8]['expected']['modifiers']['values']['build_time'], 1.0)
        self.assertEqual(steps[9]['expected']['target'], 3.1688570976257324)
        self.assertEqual(steps[9]['expected']['state']['state'], 1)
