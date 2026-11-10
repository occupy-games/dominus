import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage,ROOT
from tools.temple_terrain import extract


class TempleTerrainTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_temple_terrain.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_source_constants_and_instructions_are_reproducible(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/temple-terrain.json').read_text()))
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content['native_routines'],self.fixture['native_routines'])
        for address,code in self.fixture['native_routines'].items():self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertNotIn('0x10140ded',self.fixture['adapters'])
        self.assertEqual([t['name'] for t in self.content['special_types']],['Shrine_LandExp','Shrine_OreLandExp','Shrine_WeylandOreLandExp'])
        self.assertEqual(self.content['rules']['ordinary_seconds'],4)
        self.assertEqual(self.content['rules']['special_seconds'],60)

    def test_blocked_work_is_reversible(self):
        blocked=self.cases['phase_6_1_1_False']['expected']['state']
        self.assertEqual((blocked['phase'],blocked['timer'],blocked['progress']),(8,2,30))
        special=self.content['rules']['special_types'][0]
        restored=self.cases[f'restore_{special}_1']['expected']['state']
        self.assertEqual((restored['phase'],restored['progress']),(6,45))
        self.assertEqual(self.cases['phase_8_0_0_False']['expected']['state']['phase'],5)
        self.assertEqual(self.cases['phase_1_0_0_False']['expected']['state']['phase'],7)

    def test_expansion_decay_releases_audio_after_requesting_removal(self):
        special=self.content['rules']['special_types'][0]
        result=self.cases[f'boundary_{special}_60.0_True_7']['expected']
        self.assertEqual(result['state']['remove_requested'],1)
        self.assertEqual(result['state']['audio_handle'],-1)
        self.assertEqual([e[0] for e in result['events']][-3:],['audio_lookup','audio_release','audio_fade'])
        self.assertEqual(len(self.fixture['cases']),312)


if __name__=='__main__':unittest.main()
