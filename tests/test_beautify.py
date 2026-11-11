import hashlib
import json
import struct
import unittest

from tools.audio_events import beautify_loop
from tools.beautify import extract
from tools.beautify_particles import extract as extract_particles
from tools.native_scenery_oracle import ROOT, NativeImage
from tools.original_assets import chunks, package_media
from tools.particle_curves import sample_color, sample_curve, sample_draw_color


class BeautifyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = extract()
        cls.fixture = json.loads((ROOT / 'game/tests/fixtures/source_beautify.json').read_text())
        cls.cases = {item['name']: item['expected'] for item in cls.fixture['cases']}

    def test_original_configuration_and_executed_terrain_instructions(self):
        data = ROOT / 'game/assets/original/campaign/beautify.json'
        self.assertEqual(json.loads(data.read_text()), self.source)
        self.assertEqual(self.fixture['executable_sha256'], self.source['executable_sha256'])
        image = NativeImage((ROOT / 'data/godus2_4/godus.s86').read_bytes())
        for address, code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address, 16), len(code) // 2).hex(), code)
            self.assertNotIn(address, self.fixture['adapters'])
        self.assertEqual(self.source['rules']['configuration']['BEAUTIFY_TIMEOUT'], 1200.0)
        self.assertEqual(self.source['rules']['configuration']['LE_TIMER_TICK_LENGTH'], 30.0)

    def test_coast_fractional_radius_and_prior_beautification_change_quote(self):
        self.assertEqual(self.cases['coast']['events'][0], ['payment', 2.0, 8])
        self.assertEqual(self.cases['fractional_radius']['events'][:2],
                         [['payment', 5.760000228881836, 8], ['brush', 33, 33, 4, 4]])
        self.assertEqual(self.cases['overlap']['events'][:2],
                         [['payment', 2.125, 8], ['brush', 34, 34, 3, 3]])
        self.assertEqual(self.cases['overlap']['events'][2:4],
                         [['cell', 35, 34], ['cell', 34, 35]])
        self.assertEqual(self.cases['dry']['events'][-2:],
                         [['dirty', 36, 36, 3], ['refresh', 36., 36., 2.]])

    def test_terrain_stays_unchanged_when_the_action_is_rejected(self):
        for name in ['no_influence', 'no_hit', 'cannot_pay']:
            case = self.cases[name]
            self.assertFalse(case['ok'])
            self.assertEqual(case['serial'], 0)
            self.assertFalse(any(case['reads']))
        self.assertTrue(self.cases['power_influence']['ok'])
        wet = self.cases['water']
        self.assertFalse(any(value for probe, value in zip(wet['probes'], wet['reads']) if probe[0] in [1, 7]))

    def test_source_brush_audio_actions_and_exact_pcm(self):
        source = ROOT / 'data/godus2_4'
        output = ROOT / 'game/assets/original'
        recorded = json.loads((output / 'audio_events.json').read_text())['beautify_loop']
        self.assertEqual((recorded['attack_ms'], recorded['release_ms'], recorded['loop_frames'],
                          recorded['sample_rate'], recorded['volume_db']), (500, 2200, 252668, 48000, -2.0))
        for platform in ['Mac', 'Windows']:
            with self.subTest(platform=platform):
                media, records = package_media((source / f'SoundBanks/{platform}/GodusMain.pck').read_bytes())
                objects = {key: (kind, body) for kind, key, body in records}
                self.assertEqual(beautify_loop(objects, media), {k: v for k, v in recorded.items() if k != 'media'})
                original_pcm = chunks(media[recorded['media_id']], 12, True)[b'data']
                imported_pcm = chunks((output / recorded['media']).read_bytes(), 12, True)[b'data']
                self.assertEqual(original_pcm, imported_pcm)

    def test_registered_particle_scene_and_original_atlas_regions(self):
        source = ROOT / 'data/godus2_4'
        manifest = extract_particles(source)
        self.assertEqual(json.loads((ROOT / 'game/assets/original/beautify_particles.json').read_text()), manifest)
        self.assertEqual(manifest['scene'], dict(name='Beautify', offset=0x34081, toc_offset=0x7eb66,
                                                 scale=0.02, offset_xyz=[0, 0, 0], infinite=False, random=True))
        self.assertEqual({name: call['target'] for name, call in manifest['lifecycle'].items()},
                         {'create': 0x1024d580, 'move': 0x1024a650, 'stop': 0x1024c050})
        emitters = manifest['emitters']
        self.assertEqual([(item['name'], item['offset']) for item in emitters], [
            ('Beautify_Bokeh', 0x34677), ('Beautify_Sparkle', 0x37926), ('Beautify_RainbowBlurs', 0x3ac03)])
        self.assertEqual([[frame['atlas_rect'] for frame in item['frames']] for item in emitters], [
            [[342, 108, 54, 54]], [[404, 107, 93, 89]],
            [[310, 109, 32, 32], [278, 119, 32, 32], [786, 123, 32, 32], [754, 124, 32, 32]]])
        atlas_path = manifest['source']['atlas']
        atlas = (ROOT / 'game/assets/extracted' / atlas_path).read_bytes()
        self.assertEqual(hashlib.sha256(atlas).hexdigest(), manifest['source']['atlas_sha256'])

    def test_particle_curves_match_original_loader_before_compilation(self):
        manifest = extract_particles(ROOT / 'data/godus2_4')
        fixture = json.loads((ROOT / 'game/tests/fixtures/source_beautify_particles.json').read_text())
        self.assertEqual(fixture['executable_sha256'], manifest['source']['executable_sha256'])
        self.assertEqual(fixture['library_sha256'], manifest['source']['library_sha256'])
        for emitter, native in zip(manifest['emitters'], fixture['emitters'], strict=True):
            with self.subTest(emitter=emitter['name']):
                self.assertEqual(emitter['name'], native['name'])
                self.assertEqual(emitter['definition_end'], native['end'])
                self.assertEqual(len(emitter['curves']), 28)
                for authored, loaded in zip(emitter['curves'], native['curves'], strict=True):
                    self.assertEqual({field: authored[field] for field in loaded}, loaded)

    def test_portable_scalar_tables_and_samples_match_original(self):
        manifest = extract_particles(ROOT / 'data/godus2_4')
        fixture = json.loads((ROOT / 'game/tests/fixtures/source_beautify_particles.json').read_text())
        comparisons = 0
        cache_values = 0
        for emitter, native in zip(manifest['emitters'], fixture['emitters'], strict=True):
            self.assertEqual(emitter['scalar_curves'].keys(), native['scalar_curves'].keys())
            self.assertEqual(len(emitter['scalar_curves']), 18)
            self.assertEqual(emitter['curve_cache_resolution'], native['cache_resolution'])
            for field, curves in native['scalar_curves'].items():
                portable = emitter['scalar_curves'][field]
                self.assertEqual(portable.keys() - {'conversion', 'cache'}, curves.keys())
                for kind, values in curves.items():
                    with self.subTest(emitter=emitter['name'], field=field, kind=kind):
                        self.assertEqual(portable[kind], values['keys'])
                        samples = [sample_curve(portable[kind], portable['conversion'], time)
                                   for time in fixture['sample_times']]
                        self.assertEqual(samples, values['values'])
                        comparisons += len(samples)
                        cache = portable['cache'][kind]
                        table = cache['values']
                        if len(table) == 1:
                            table = table * cache['count']
                        bits = struct.pack(f'<{len(table)}f', *table)
                        self.assertEqual(dict(active=cache['active'], count=len(table),
                                              sha256=hashlib.sha256(bits).hexdigest()), values['cache'])
                        cache_values += len(table)
        self.assertEqual(comparisons, 1530)
        self.assertEqual(cache_values, 24090)

    def test_portable_particle_colors_match_native_cache_and_render_lookup(self):
        manifest = extract_particles(ROOT / 'data/godus2_4')
        fixture = json.loads((ROOT / 'game/tests/fixtures/source_beautify_particles.json').read_text())
        percent = manifest['curve_constants']['percent']
        for emitter, native in zip(manifest['emitters'], fixture['emitters'], strict=True):
            with self.subTest(emitter=emitter['name']):
                colors = emitter['color_cache']
                self.assertEqual(len(colors), emitter['curve_cache_resolution'] + 1)
                self.assertEqual(colors[-1], colors[-2])
                self.assertEqual(colors, native['color']['cache'])
                scale = emitter['color_time_scale']
                self.assertEqual(scale, native['color']['time_scale'])
                self.assertEqual([sample_color(colors, age, scale, percent) for age in fixture['color_times']],
                                 native['color']['samples'])

    def test_particle_opacity_and_argb_match_native_draw_path(self):
        manifest = extract_particles(ROOT / 'data/godus2_4')
        fixture = json.loads((ROOT / 'game/tests/fixtures/source_beautify_particles.json').read_text())
        self.assertEqual(len(fixture['draw_inputs']), 119)
        for emitter, native in zip(manifest['emitters'], fixture['emitters'], strict=True):
            with self.subTest(emitter=emitter['name']):
                colors = [sample_draw_color(emitter, manifest['curve_constants'], *case)
                          for case in fixture['draw_inputs']]
                self.assertEqual(colors, native['draw_colors'])
                self.assertIn(0, [color >> 24 for color in colors])
                self.assertIn(255, [color >> 24 for color in colors])

    def test_native_beautify_scene_births_motion_and_release(self):
        manifest = extract_particles(ROOT / 'data/godus2_4')
        fixture = json.loads((ROOT / 'game/tests/fixtures/source_beautify_particles.json').read_text())
        playback = fixture['playback']
        emitters = manifest['emitters']
        self.assertEqual(playback['clocks'], [emitter['clock'] for emitter in emitters])
        self.assertEqual(playback['group_end'], emitters[-1]['end'] - 1)
        for case in (playback, fixture['fractional_playback']):
            for frame in case['frames']:
                for emitter, row in zip(emitters, frame, strict=True):
                    for sample in row['rates']:
                        self.assertEqual(sample['rates'], emitter['birth_rates'])
        frames = playback['frames']
        self.assertEqual([[row['births'] for row in frame] for frame in frames[:9]],
                         [[0, 1, 0], [0, 0, 0], [0, 0, 0], [0, 1, 0], [1, 2, 2],
                          [1, 3, 1], [1, 3, 2], [1, 3, 2], [1, 3, 1]])
        self.assertEqual({particle[-1] for particle in frames[6][2]['particles']}, {0, 1, 2, 3})
        self.assertNotEqual(frames[0][1]['particles'][0][3], frames[4][1]['particles'][0][3])
        release = playback['release_step']
        for step in range(release, len(frames)):
            delta = playback['timesteps_ms'][step]
            for previous, current in zip(frames[step - 1], frames[step], strict=True):
                self.assertEqual(current['births'], 0)
                survivors = {slot: (remaining - delta, lifetime)
                             for slot, remaining, lifetime, *_ in previous['particles'] if remaining > delta}
                self.assertEqual({slot: (remaining, lifetime) for slot, remaining, lifetime, *_ in current['particles']},
                                 survivors)
        self.assertEqual([len(row['particles']) for row in frames[release]], [5, 15, 8])
        self.assertTrue(all(row['finished'] and not row['particles'] for row in frames[-1]))

    def test_original_land_effect_clock_and_expiry_fixture(self):
        timer = json.loads((ROOT / 'game/tests/fixtures/source_land_effect_timer.json').read_text())
        self.assertEqual(timer['executable_sha256'], self.source['executable_sha256'])
        self.assertEqual(timer['native_routines'], self.source['timer_routines'])
        self.assertFalse(timer['native_routines'].keys() & set(timer['adapters']))
        self.assertEqual(self.source['rules']['timer'], {'milliseconds_per_second': 1000, 'catch_up_limit': 10})
        cases = {case['name']: case for case in timer['cases']}
        clock = cases['fixed_clock']
        steps = {step['now']: step['expected'] for step in clock['steps']}
        timer_byte = clock['probes'].index([7, 9, 2])
        self.assertEqual(steps[31000]['changed'], [[0, 1], [3, 0], [32, 0]])
        self.assertEqual(steps[31000]['serial'], 5)
        self.assertEqual(steps[61037]['anchor'], 61000)
        self.assertEqual(steps[421000]['reads'][timer_byte], 26 / 128)
        self.assertEqual(steps[752000]['reads'][timer_byte], 26 / 128)
        self.assertEqual(steps[782000]['reads'][timer_byte], 25 / 128)
        override = cases['explicit_elapsed']['steps'][3]['expected']
        self.assertEqual(override['anchor'], 5000)
        self.assertEqual(override['changed'], [[6, 2], [7, 2], [8, 2]])
        zero = cases['explicit_elapsed']['steps'][-1]['expected']
        self.assertEqual(zero['anchor'], 520000)
        self.assertEqual(zero['reads'][timer_byte], 11 / 128)
        self.assertEqual(cases['high_word_fractional_period']['steps'][1]['expected']['anchor'], (1 << 32) + 15)
