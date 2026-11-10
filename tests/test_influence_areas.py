import hashlib
import json
from pathlib import Path
import unittest

from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage

ROOT=Path(__file__).resolve().parents[1]


class InfluenceAreaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_influence_areas.json').read_text())
        cls.rules=json.loads((ROOT/'game/assets/original/campaign/influence-rules.json').read_text())

    def test_original_controller_and_source_profile_provenance(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        image=NativeImage(raw)
        archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
        files=decode_archive(archive)
        self.assertEqual(self.fixture['executable_sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(self.fixture['source_sha256'],hashlib.sha256(archive).hexdigest())
        for address,instructions in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(instructions)//2).hex(),instructions)
        for name,path in [('area_table','initialworldsetup6/influence_areas.csv'),('hardware_table','hwlevelcontrols.csv')]:
            self.assertEqual(self.fixture[name+'_sha256'],hashlib.sha256(files[path]).hexdigest())
        for address in [0x1025ab20,0x100d0a10,0x10257780,0x10025f10,0x100cf9d0]:
            self.assertNotIn(hex(address),self.fixture['adapters'])
        table=rows(files,'hwlevelcontrols.csv')
        self.assertEqual(self.rules['hardware_profile'],next(row for row in table if row[0]=='DesktopHigh'))
        self.assertTrue(self.rules['rules']['expand'])
        self.assertEqual(self.rules['rules']['expand_rate'],.5)
        self.assertEqual(image.read(0x104f0284,100).split(b'\0')[0].decode(),self.rules['rules']['finish_event'])

    def test_original_timing_unlock_conversion_and_dirty_observations(self):
        cases={c['name']:c for c in self.fixture['cases']}
        self.assertEqual(len(cases),12)
        sequence=cases['desktop_expand']['states']
        self.assertAlmostEqual(sequence[0]['radii'][0],.2,places=7)
        self.assertEqual(sequence[4]['radii'],[1.])
        self.assertEqual(sequence[6]['radii'],[4.])
        self.assertEqual(sequence[7]['events'],[dict(name='influencechanged',argument=0)])
        self.assertEqual(sequence[0]['dirty'],[101])
        self.assertEqual(sequence[4]['dirty'],[100,101])
        self.assertFalse(cases['unlock']['states'][0]['changed'])
        self.assertTrue(cases['unlock']['states'][1]['changed'])
        self.assertEqual(cases['power_conversion']['states'][1]['powers_only'],[False])
        self.assertFalse(cases['power_conversion']['states'][1]['changed'])
        self.assertEqual(cases['power_conversion']['states'][1]['dirty'],[])
        self.assertTrue(cases['forced_conversion']['states'][1]['changed'])
        self.assertEqual(cases['relock']['states'][1]['radii'],[4.])
        self.assertEqual(cases['relock']['states'][0]['fields'],cases['relock']['states'][1]['fields'])
        self.assertEqual(cases['homeworld_initial']['states'][2]['radii'][:3],[50.,22.,12.])
        for case in cases.values():
            x0,z0,x1,z1=case['bounds']
            for state in case['states']:
                self.assertEqual(state['dirty'],sorted(set(state['dirty'])))
                for field in ['4','6']:self.assertEqual(len(bytes.fromhex(state['fields'][field])),(x1-x0)*(z1-z0))
