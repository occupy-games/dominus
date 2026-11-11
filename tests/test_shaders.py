import hashlib
import json
from pathlib import Path
import struct
import unittest

from tools.original_assets import resource_group
from tools.shaders import decode_shader, terrain_beautify_texture

ROOT = Path(__file__).resolve().parents[1]


class ShaderSourceTests(unittest.TestCase):
    def test_shader_text_and_parameter_payloads_are_exact_source(self):
        output = ROOT / 'game/assets/original/shaders'
        catalog = json.loads((output / 'catalog.json').read_text())
        groups = {}
        self.assertEqual(len(catalog['shaders']), 74)
        for record in catalog['shaders']:
            path = ROOT / 'data/godus2_4' / record['source']
            if record['source'] not in groups:
                raw = path.read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), record['group_sha256'])
                groups[record['source']] = resource_group(raw)
            raw = groups[record['source']][record['resource_type']][record['resource_id']]
            self.assertEqual(hashlib.sha256(raw).hexdigest(), record['member_sha256'])
            parsed = decode_shader(raw)
            cursor = 0
            for stage in ['vertex', 'fragment']:
                length, = struct.unpack_from('<I', raw, cursor)
                self.assertEqual(parsed[stage].encode(), raw[cursor+4:cursor+4+length])
                self.assertEqual(raw[cursor+4+length], 0)
                cursor += length + 5
                self.assertEqual((output / record[stage]['path']).read_bytes(), parsed[stage].encode())
            self.assertEqual(parsed['parameters'], raw[cursor:])
            self.assertEqual((output / record['parameters']['path']).read_bytes(), raw[cursor:])
            self.assertEqual(parsed['parameter_count'], record['parameter_count'])
        crop = next(r for r in catalog['shaders'] if r['name'] == 'shdrCropsGrain')
        fragment = (output / crop['fragment']['path']).read_text()
        self.assertIn('int2rgb(207,168,101)', fragment)
        self.assertIn('int2rgb(125,163,48)', fragment)
        self.assertIn('linearTint(diffMap.g,finalRipeCol)', fragment)
        self.assertIn('pow(ripeness,12.0)', fragment)

    def test_malformed_shader_lengths_reject(self):
        with self.assertRaises(ValueError):
            decode_shader(struct.pack('<I', 1000) + b'void main(){}\0')

    def test_beautify_terrain_sampler_uses_the_bound_original_texture(self):
        catalog = json.loads((ROOT / 'game/assets/original/shaders/catalog.json').read_text())
        port = next(item for item in catalog['runtime_ports'] if item['path'].endswith('/source_land.gdshader'))
        terrain = next(item for item in catalog['shaders'] if item['name'] == 'shdrTerrain50')
        self.assertEqual(port['member_sha256'], terrain['member_sha256'])
        texture = terrain_beautify_texture(ROOT / 'data/godus2_4')
        self.assertEqual(port['textures'], [texture])
        self.assertEqual(texture['sampler'], 3)
        installed = ROOT / 'game/assets/extracted' / texture['source']
        self.assertEqual(hashlib.sha256(installed.read_bytes()).hexdigest(), texture['sha256'])


if __name__ == '__main__':
    unittest.main()
