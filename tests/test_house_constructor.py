import json
from pathlib import Path
import struct
import unittest

from tools.house_constructor import extract
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class HouseConstructorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads((ROOT/'game/assets/original/campaign/house-constructor.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_house_constructor.json').read_text())
        cls.cases={case['name']:case['expected'] for case in cls.fixture['cases']}

    def test_source_rows_constants_and_executed_instruction_provenance(self):
        self.assertEqual(self.data,extract())
        source=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
        self.assertEqual(len(self.data['records']),len(source['records']))
        for index,(key,row) in enumerate(source['records'].items()):
            self.assertEqual(self.data['records'][index],dict(index=index,id=key,rank=int(row['raw']['Rank']),
                values={field:row['values'][field] for field in self.data['fields']}))
        for key in ['source_sha256','table_sha256','executable_sha256','native_routines']:
            self.assertEqual(self.data[key],self.fixture[key])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for constant in self.data['constants'].values():
            self.assertEqual(image.read(int(constant['address'],16),len(constant['bytes'])//2).hex(),constant['bytes'])
        for address in [0x100bc660,0x1003f610,0x1003e400,0x100b7460,0x100b7900,0x10153dd0,0x10153de0]:
            self.assertNotIn(hex(address),self.fixture['adapters'])
        # Dynamic modifiers, model resolution, sampled fields and spatial
        # membership remain explicit input/service boundaries.
        for address in [0x100b7580,0x100bb560,0x1012ec90,0x100cf550]:
            self.assertIn(hex(address),self.fixture['adapters'])

    def integer(self,name,field):
        return int.from_bytes(bytes.fromhex(self.cases[name]['fields'][field]),'little')

    def test_native_identity_flags_clock_and_reconstruction(self):
        self.assertEqual(self.integer('first','0x88'),0x01000001)
        self.assertEqual(self.integer('owner','0x88'),0xe1000001)
        self.assertEqual(self.integer('provided_identity','0x88'),0x01123456)
        self.assertEqual(self.cases['provided_identity']['next_identity'],0)
        self.assertEqual(self.integer('identity_wrap','0x88'),0x01000000)
        self.assertEqual(self.cases['identity_wrap']['next_identity'],0x1000000)
        self.assertEqual(self.cases['masked_identity_zero']['next_identity'],1)
        self.assertEqual(self.integer('flags','0x2c0'),6)
        self.assertEqual(self.integer('configuration','0x2c0'),0x12345)
        self.assertEqual((self.integer('clock','0x4c')<<32)|self.integer('clock','0x48'),0x123456789ab)
        self.assertEqual(self.cases['reuse']['events'],[])
        self.assertEqual(self.cases['reuse']['spatial'],[])
        self.assertEqual(self.cases['reuse']['occupied'],[])
        self.assertEqual(self.cases['silent']['events'],[])
        self.assertTrue(self.cases['silent']['occupied'])

    def test_source_scenery_categories_field_boundaries_and_footprint(self):
        self.assertEqual([self.integer('mixed_scenery',key) for key in ['0x244','0x248','0x24c']],[3,2,2])
        self.assertEqual(self.cases['beauty_boundary']['fields']['0x250'],'00000000')
        self.assertEqual(struct.unpack('<f',bytes.fromhex(self.cases['beautified']['fields']['0x250']))[0],1.)
        self.assertEqual(self.cases['mine']['mine_queries'],[[10.,20.]])
        self.assertEqual(self.cases['first']['occupied'],[z*1024+x for z in range(120,124) for x in range(158,162)])
        self.assertEqual(self.cases['map_edge']['occupied'],[0,1,1024,1025,2048,2049])
        self.assertEqual(self.cases['far_edge']['occupied'],[z*1024+x for z in range(1022,1024) for x in range(1022,1024)])
        self.assertEqual(struct.unpack('<f',bytes.fromhex(self.cases['special_rotation']['fields']['0x118']))[0],self.data['rules']['rotation_override'])
