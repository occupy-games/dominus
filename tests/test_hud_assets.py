import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HudAssetTests(unittest.TestCase):
    def test_native_gauge_and_corner_art_preserve_source_provenance(self):
        data = json.loads((ROOT / 'game/assets/original/ui/catalog.json').read_text())
        native = data['native_atlas']
        source = ROOT / 'data/godus2_4' / native['source']
        runtime = ROOT / 'game/assets/extracted' / native['source']
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), native['sha256'])
        self.assertEqual(source.read_bytes(), runtime.read_bytes())
        for x, y, width, height in native['regions'].values():
            self.assertGreater(width, 0)
            self.assertGreater(height, 0)
            self.assertLessEqual(x + width, 512)
            self.assertLessEqual(y + height, 2048)
        for name in ['GFX_CEPopFront.png', 'GFX_CESettings_Front.png', 'GFX_CEGems_Front.png',
                     'GFX_IconWheatRate.png', 'GFX_IconMining.png', 'GFX_IconGemsSmall.png']:
            self.assertIn(name, data['regions'])
