import hashlib
import json
from pathlib import Path
import unittest
from tools.tree_imposters import decode

ROOT = Path(__file__).resolve().parents[1]

class TreeImposterTests(unittest.TestCase):
    def test_recovered_rectangles_preserve_source_and_fit_the_original_atlas(self):
        source = ROOT / 'data/godus2_4/sprites/pack_treeImposters_v2.png.dat'
        recovered = decode(source.read_bytes())
        stored = json.loads((ROOT / 'game/assets/original/tree_imposters.json').read_text())
        self.assertEqual(stored['source_sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(stored['entries'], recovered['entries'])
        self.assertEqual(len(recovered['entries']), 60)
        for entry in recovered['entries']:
            x, y, width, height = entry['rect']
            self.assertLessEqual(x + width, 1024)
            self.assertLessEqual(y + height, 1024)
        for kind in (0, 2, 10):
            self.assertTrue(all(e['rect'][2] > 0 and e['rect'][3] > 0
                                for e in recovered['entries'][kind * 5:(kind + 1) * 5]))

    def test_unknown_metadata_is_rejected(self):
        with self.assertRaises((ValueError, __import__('struct').error)):
            decode(b'unknown')
