import hashlib
import json
from pathlib import Path
import unittest

from tools.campaign import packed_map, decode_chunk
from tools.current_cards import decode_archive

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/godus2_4'
OUTPUT = ROOT / 'game/assets/original/adventures'


class AdventuresTests(unittest.TestCase):
    def test_original_island_crops_and_rules(self):
        catalog = json.loads((OUTPUT / 'catalog.json').read_text())
        archive = (SOURCE / catalog['archive']).read_bytes()
        self.assertEqual(hashlib.sha256(archive).hexdigest(), catalog['archive_sha256'])
        files = decode_archive(archive)
        missions = catalog['missions']
        available = [m for m in missions if m['available']]
        intro = [m for m in available if m['family']=='event_01' and m.get('order',100)<=4]
        self.assertEqual([m['seconds'] for m in intro], [60, 80, 75, 120])
        self.assertEqual(len(available), 205)
        self.assertGreater(len(missions), 200)
        self.assertFalse(any('editor' in m['id'] or '__tst' in m['id'] for m in missions))
        maps = {}
        for mission in available:
            if mission['pack_source'] not in maps:
                maps[mission['pack_source']] = packed_map(SOURCE / mission['pack_source'])[0]
            fields = maps[mission['pack_source']]
            self.assertGreater(mission['seconds'], 0)
            self.assertGreater(mission['required'], 0)
            self.assertGreater(mission['speed'], 0)
            self.assertGreater(mission['spawn_seconds'], 0)
            for name, fingerprint in mission['source_files'].items():
                self.assertEqual(hashlib.sha256(files[name]).hexdigest(), fingerprint)
                self.assertEqual((OUTPUT / 'source' / name).read_bytes(), files[name])
            x, z = mission['origin']
            width = mission['width']
            for kind, descriptor in mission['fields'].items():
                raw = (OUTPUT / descriptor['path']).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), descriptor['sha256'])
                exact = bytearray(b''.join(fields[kind][row*1024+x:row*1024+x+width] for row in range(z,z+width)))
                for name,evidence in mission.get('stream_revisions',{}).items():
                    if not name.startswith(kind+'_'): continue
                    location=evidence['source']
                    if '#' in location:
                        archive_path,member=location.split('#',1)
                        downloaded=(SOURCE/archive_path).read_bytes()
                        self.assertEqual(hashlib.sha256(downloaded).hexdigest(),evidence['archive_sha256'])
                        payload=decode_archive(downloaded)[member]
                    else: payload=(SOURCE/location).read_bytes()
                    self.assertEqual(hashlib.sha256(payload).hexdigest(),evidence['sha256'])
                    chunk=decode_chunk(payload)
                    cx,cz=int(name[-4:-2],16)*128,int(name[-2:],16)*128
                    for row in range(max(z,cz),min(z+width,cz+128)):
                        left,right=max(x,cx),min(x+width,cx+128)
                        exact[(row-z)*width+left-x:(row-z)*width+right-x]=chunk[(row-cz)*128+left-cx:(row-cz)*128+right-cx]
                self.assertEqual(raw, exact)
            for point in ['dock', 'goal']:
                px, pz = mission[point]
                raw=(OUTPUT/mission['fields']['terrain']['path']).read_bytes()
                self.assertGreaterEqual(raw[pz*width+px], mission['sea_level'])

    def test_compiled_scripts_and_executable_defaults_have_provenance(self):
        from tools.voyage_lua import compile_script
        from tools.native_config import recover
        catalog=json.loads((OUTPUT/'catalog.json').read_text())
        raw=(SOURCE/'godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),catalog['native_config']['sha256'])
        native=recover(raw)
        self.assertEqual(native['MissionScoreFollowerReachedTemple']['value'],1000)
        self.assertEqual(native['StickerChance_CurrentBeads_Event']['value'],8000)
        for mission in catalog['missions']:
            if not mission['available']: continue
            definition=json.loads((OUTPUT/mission['definition']).read_text())
            original=(OUTPUT/'source'/mission['source']/'scripts.lua').read_text(encoding='utf-8-sig')
            parsed=compile_script(original)
            self.assertEqual(parsed['body'],definition['program']['body'])
            self.assertEqual(parsed['functions'],definition['program']['functions'])
            self.assertIn('onPostLoad',original)


if __name__ == '__main__':
    unittest.main()
