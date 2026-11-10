import gzip
import hashlib
import json
from pathlib import Path
import struct
import unittest

from tools.current_cards import decode_archive, rows, text

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/godus2_4'


class CurrentCardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = (SOURCE / 'received/godussteamrel/balance.datz').read_bytes()
        cls.files = decode_archive(cls.raw)
        cls.manifest = json.loads((ROOT / 'game/assets/original/cards_24/catalog.json').read_text())

    def test_complete_catalog_tracks_source_tables_and_exact_art(self):
        entries = self.manifest['cards']
        expected = {r[0] for table in ['gui/carddetails.csv', 'gui/stickerdetails.csv']
                    for r in rows(self.files, table) if r and r[0].startswith(('Card_', 'Sticker_'))}
        self.assertEqual(set(entries), expected)
        self.assertEqual(len(entries), 249)
        self.assertEqual(self.manifest['source_sha256'], hashlib.sha256(self.raw).hexdigest())
        for name, digest in self.manifest['tables'].items():
            self.assertEqual(hashlib.sha256(self.files[name]).hexdigest(), digest)
        for entry in entries.values():
            if not entry['available']:
                self.assertTrue(entry['unavailable_reason'])
                self.assertFalse(entry['texture_path'])
                continue
            self.assertNotIn('/Resources/Cards/', entry['illustration_source'])
            original = SOURCE / entry['illustration_source']
            self.assertEqual(hashlib.sha256(original.read_bytes()).hexdigest(), entry['image_sha256'])
            thumb = ROOT / 'game' / entry['thumbnail_path'].removeprefix('res://')
            self.assertEqual(hashlib.sha256(thumb.read_bytes()).hexdigest(), entry['thumbnail_sha256'])
            width, height = struct.unpack_from('>II', thumb.read_bytes(), 16)
            self.assertLessEqual(width, 96)
            self.assertLessEqual(height, 146)
            if not entry['sticker']:
                self.assertGreater(height, width)

    def test_all_power_explanations_are_actual_localization(self):
        localization = {r[0]:r[1] for r in rows(self.files, 'gui/localization.csv') if len(r)>1}
        for entry in self.manifest['cards'].values():
            if entry['kind'] != 'powers' or not entry['available']: continue
            if not entry['description']:
                self.assertTrue(entry['missing_text_keys'])
                self.assertTrue(all(key not in localization for key in entry['missing_text_keys']))
            expected = '\n\n'.join(dict.fromkeys(text(key, localization) for key in entry['description_keys']))
            self.assertEqual(entry['description'], expected)
            self.assertNotIn('<s:', entry['description'])
        beautify = self.manifest['cards']['Card_GodPower_Beautify']
        self.assertIn('inspire your Followers to populate', beautify['description'])
        self.assertEqual(self.manifest['cards']['Sticker_ReligiousObject_3']['title'], 'Incense')
        self.assertTrue(self.manifest['cards']['Sticker_ReligiousObject_3']['illustration_source'].endswith('/Stickers/stk_incense.png'))
        self.assertEqual(self.manifest['cards']['Card_Belief_1000']['reward']['belief'], 1000)
        absent = self.manifest['cards']['Card_GodPower_Settlement_5a']
        self.assertEqual(absent['missing_text_keys'], ['LOC_Card_Desc_Settle_ArcherA'])
        self.assertEqual(absent['description'], '')

    def test_unknown_or_damaged_packing_is_rejected(self):
        with self.assertRaises(ValueError): decode_archive(b'unknown')
        corrupted = bytearray(self.raw)
        corrupted[-6] ^= 1
        with self.assertRaises((ValueError, OSError, EOFError)): decode_archive(corrupted)

    def test_binary_members_retain_significant_trailing_zero_bytes(self):
        name=b'stream/eventmap_05/terrain_0000'
        payload=b'\x53\0\0\0\0'
        body=struct.pack('<II',1,len(payload))+name.ljust(256,b'\0')+payload+b'\0'*3
        compressed=gzip.compress(body)
        archive=bytes(b ^ ((0x6c+i*0x4d)&255) for i,b in enumerate(compressed))
        self.assertEqual(decode_archive(archive)[name.decode()],payload)
