import hashlib
import json
from pathlib import Path
import struct
import unittest

from tools.current_cards import decode_archive, rows
from tools.influence_rules import extract
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class SourceInfluenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads((ROOT/'game/tests/fixtures/source_influence.json').read_text())
        cls.metadata = json.loads((ROOT/'game/assets/original/campaign/influence-rules.json').read_text())

    def test_native_raster_storage_and_gate_provenance(self):
        raw = (ROOT/'data/godus2_4/godus.s86').read_bytes()
        image = NativeImage(raw)
        self.assertEqual(self.metadata, extract())
        for record in [self.fixture, self.metadata]:
            self.assertEqual(record['executable_sha256'], hashlib.sha256(raw).hexdigest())
            for address, instructions in record['native_routines'].items():
                self.assertEqual(image.read(int(address, 16), len(instructions)//2).hex(), instructions)
        self.assertEqual(self.fixture['adapters'], ['0x10353740','0x1035f180'])
        for record in self.metadata['constants'].values():
            value = bytes.fromhex(record['bytes'])
            self.assertEqual(image.read(int(record['address'],16),len(value)),value)
            self.assertEqual(struct.unpack('<d' if len(value)==8 else '<f',value)[0],record['value'])

    def test_original_initial_area_rows_and_configuration(self):
        archive = (ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
        files = decode_archive(archive)
        self.assertEqual(self.fixture['source_sha256'], hashlib.sha256(archive).hexdigest())
        self.assertEqual(self.metadata['source_sha256'], self.fixture['source_sha256'])
        table = 'initialworldsetup6/influence_areas.csv'
        self.assertEqual(self.fixture['area_table_sha256'], hashlib.sha256(files[table]).hexdigest())
        commands = [dict(id=str(0x1aaaaaa00000000+index),x=float(row[2]),z=float(row[3]),radius=float(row[4]),powers_only=bool(int(row[6])))
                    for index,row in enumerate(rows(files,table)[1:]) if len(row)>6 and row[2] and int(row[5])]
        actual = next(c for c in self.fixture['cases'] if c['name']=='source_initial_areas')['commands']
        self.assertEqual(actual, commands)
        self.assertEqual(len(commands),4)
        self.assertEqual(sum(c['powers_only'] for c in commands),1)
        self.assertEqual(self.metadata['rules']['threshold'],.25)

    def test_byte_captures_cache_identity_and_original_gates(self):
        cases = {c['name']:c for c in self.fixture['cases']}
        self.assertEqual(len(cases),17)
        for case in cases.values():
            x0,z0,x1,z1 = case['bounds']
            for state in case['states']:
                for field in ['4','6']:
                    data = bytes.fromhex(state['fields'][field])
                    self.assertEqual(len(data),(x1-x0)*(z1-z0))
                    self.assertLessEqual(max(data),128)
        self.assertEqual([s['changed'] for s in cases['unchanged_identity']['states']],[True,False])
        self.assertEqual([s['changed'] for s in cases['forced_identity']['states']],[True,True])
        self.assertEqual([s['changed'] for s in cases['large_identity']['states']],[True,False,True])
        self.assertEqual(set(bytes.fromhex(cases['power_area']['states'][0]['fields']['4'])),{0})
        gates = {tuple(g['fields']):(g['build'],g['power']) for g in self.fixture['gates']}
        self.assertEqual(len(gates),49)
        self.assertEqual(gates[(32,32)],(True,True))
        self.assertEqual(gates[(32,33)],(False,True))
        self.assertEqual(gates[(0,32)],(False,True))
        self.assertEqual(gates[(31,31)],(False,False))
