import hashlib
import json
from pathlib import Path
import unittest

from tools.campaign import packed_map
from tools.plot_field import extract

ROOT = Path(__file__).resolve().parents[1]


class PlotFieldTests(unittest.TestCase):
    def test_lossless_original_field_and_pack_provenance(self):
        metadata = json.loads((ROOT/'game/assets/original/campaign/plot-field.json').read_text())
        self.assertEqual(metadata, extract())
        fields, *_ = packed_map(ROOT/'data/godus2_4/stream/Homeworld6.pack')
        decoded = bytearray([metadata['default']]) * (1024*1024)
        for index, value in metadata['overrides']:
            decoded[index] = value
        self.assertEqual(decoded, fields['plotrot'])
        self.assertEqual(hashlib.sha256(decoded).hexdigest(), metadata['sha256'])
        allocation = json.loads((ROOT/'game/tests/fixtures/source_plot_allocation.json').read_text())
        self.assertEqual(metadata['sha256'], allocation['plotrot_sha256'])
        # The runtime zero-blight specialization is permitted only for this
        # verified uniform field, not for arbitrary maps or rotation bytes.
        self.assertEqual(metadata['default'], 0)
        self.assertEqual(metadata['overrides'], [])
