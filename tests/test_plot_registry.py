import hashlib
import json
from pathlib import Path
import struct
import unittest

from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class PlotRegistryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = json.loads((ROOT/'game/tests/fixtures/source_plot_registry.json').read_text())
        cls.schedule = json.loads((ROOT/'game/tests/fixtures/source_plot_schedule.json').read_text())
        cls.rules = json.loads((ROOT/'game/assets/original/campaign/plot-resize-rules.json').read_text())

    def test_original_instruction_and_rate_provenance(self):
        raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
        image = NativeImage(raw)
        for record in [self.registry, self.schedule]:
            self.assertEqual(record['executable_sha256'], hashlib.sha256(raw).hexdigest())
            for address, instructions in record['native_routines'].items():
                self.assertEqual(image.read(int(address, 16), len(instructions)//2).hex(), instructions)
        for address in [0x10235d50, 0x10044110, 0x10236110, 0x10237580, 0x10237660, 0x102379c8]:
            self.assertNotIn(hex(address), self.registry['adapters'])
        # Scheduler observes dispatch; the separate region oracle executes it.
        self.assertIn('0x1023798b', self.schedule['adapters'])
        self.assertNotIn('0x1025e0d0', self.schedule['adapters'])
        rate = self.rules['progress_rate_native']
        self.assertEqual(image.read(int(rate['address'], 16), 8).hex(), rate['bytes'])
        self.assertEqual(struct.unpack('<d', bytes.fromhex(rate['bytes']))[0], self.rules['progress_rate'])
        self.assertEqual(self.registry['progress_rate'], self.rules['progress_rate'])
        source = json.loads((ROOT/'game/tests/fixtures/source_house_selection.json').read_text())
        for key in ['source_sha256', 'table_sha256']:
            self.assertEqual(source[key], self.schedule[key])

    def test_native_pool_partition_and_footprints(self):
        self.assertEqual(len(self.registry['cases']), 18)
        for case in self.registry['cases']:
            for state in case['states']:
                active = [plot['id'] for plot in state['plots']]
                self.assertEqual(sorted(active+state['free']), list(range(1024)))
                owners = {}
                for plot in state['plots']:
                    for z in range(int(plot['z']), int(plot['z'])+plot['size']):
                        for x in range(int(plot['x']), int(plot['x'])+plot['size']):
                            key = str(z*1024+x)
                            self.assertNotIn(key, owners)
                            owners[key] = plot['id']
                self.assertEqual(owners, state['owners'])

    def test_native_lifetime_boundary_and_slot_reuse(self):
        cases = {case['name']:case for case in self.registry['cases']}
        states = cases['interior_damage']['states']
        for index in range(5):
            plot = next(p for p in states[index]['plots'] if p['id'] == 0)
            self.assertEqual(plot['size'], 0)
            self.assertEqual(plot['progress'], min(1., struct.unpack('<f', struct.pack('<f', .305*index))[0]))
        self.assertFalse(any(p['id'] == 0 for p in states[5]['plots']))
        self.assertEqual(states[5]['free'][0], 0)
        reused = cases['removed_slot_reuse']['states'][-1]
        self.assertTrue(any(p['id'] == 0 and p['size'] > 0 and p['progress'] == 0. for p in reused['plots']))
        for axis, edge, inside in [('x',128,1), ('x',192,-1), ('z',96,1), ('z',160,-1)]:
            boundary = next(p for p in cases[f'boundary_{axis}_{edge}_0']['states'][0]['plots'] if p['id'] == 0)
            included = next(p for p in cases[f'boundary_{axis}_{edge}_{inside}']['states'][0]['plots'] if p['id'] == 0)
            self.assertEqual(boundary['size'], 4)
            self.assertEqual(included['size'], 8)

    def test_native_dirty_neighborhoods_and_unlock_rescan(self):
        self.assertEqual(len(self.schedule['marks']), 49)
        for example in self.schedule['marks']:
            x, z = [value//32 for value in example['cell']]
            self.assertEqual(example['dirty'], [row*32+column
                             for row in range(max(0,z-1),min(32,z+2))
                             for column in range(max(0,x-1),min(32,x+2))])
        for case in self.schedule['cases']:
            expected = case['expected']
            indices = [z*32+x for x,z in expected['regions']]
            self.assertEqual(indices, sorted(case['dirty']) if case['name'].startswith('unchanged') else list(range(1024)))
            self.assertEqual(expected['dirty'], [])
