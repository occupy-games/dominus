import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.house_selection import extract
from tools.native_scenery_oracle import NativeImage
from tools.current_cards import decode_archive, rows

ROOT = Path(__file__).resolve().parents[1]


class HouseSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = extract()
        cls.fixture = json.loads((ROOT/'game/tests/fixtures/source_house_selection.json').read_text())

    def test_native_registrations_and_source_rows(self):
        self.assertEqual(self.data,json.loads((ROOT/'game/assets/original/campaign/house-selection.json').read_text()))
        self.assertEqual(len(self.data['rows']),62)
        self.assertEqual(self.data['locations'],{'locnone':0,'loc1':1,'loc2':2,'loc12':3,'loc3':4,'loc13':5,'loc23':6,'loc123':7})
        self.assertEqual(self.data['biomes']['biome012'],7)
        self.assertEqual(self.data['biomes']['biome0123'],15)
        self.assertEqual(self.data['special_models'],{'farms':1,'miningfields':2})
        by_name={r['id']:r for r in self.data['rows']}
        self.assertEqual(by_name['AbodeType_0_Rank_1']['size'],4)
        self.assertEqual(by_name['AbodeType_0_Rank_1']['locations'],1)
        self.assertEqual(by_name['AbodeType_0_Rank_1']['biomes'],7)
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(extract(output=Path(directory)/'selection.json'),self.data)

    def test_native_fixture_provenance_and_real_instruction_coverage(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        fixture=self.fixture
        for key in ['source_sha256','table_sha256','executable_sha256']:
            self.assertEqual(fixture[key],self.data[key])
        self.assertEqual(hashlib.sha256(raw).hexdigest(),fixture['executable_sha256'])
        files=decode_archive((ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes())
        config={row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(files,path) if len(row)>1}
        self.assertEqual(fixture['configuration'],self.data['configuration'])
        for key,value in fixture['configuration'].items(): self.assertEqual(value,float(config[key]))
        image=NativeImage(raw)
        for address,code in fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(fixture['adapters'],['0x1015c130','0x1015c1e0'])

    def test_original_selection_gates_and_size_priority(self):
        profiles={p['name']:p for p in self.fixture['profiles']}
        self.assertEqual(sum(len(p['samples']) for p in profiles.values()),4608)
        by_name={r['id']:r['index'] for r in self.data['rows']}
        lookup=lambda name,size,band,scheme,kind:next(row[-1] for row in profiles[name]['samples'] if row[:4]==[size,band,scheme,kind])
        self.assertEqual({row[-1] for row in profiles['locked']['samples']},{0})
        self.assertEqual(lookup('first_tent',3,0,-1,0),0)
        self.assertEqual(lookup('first_tent',4,0,-1,0),by_name['AbodeType_0_Rank_1'])
        self.assertEqual(lookup('first_tent',4,1,-1,0),0)
        self.assertEqual(lookup('first_tent',4,0,18,0),0) # Biome 3 is outside the tent's biome012 mask.
        self.assertEqual(lookup('first_tent',4,0,17,1),by_name['Farm_Rank_1'])
        self.assertEqual(lookup('first_tent',4,0,19,2),by_name['Mine_Rank_1'])
        self.assertEqual(lookup('first_tent',4,0,-1,1),0)
        self.assertEqual(lookup('lowland',4,0,-1,0),by_name['AbodeType_1_Rank_1'])
        self.assertEqual(lookup('lowland',5,0,-1,0),by_name['AbodeType_1_Rank_2'])
        self.assertEqual(profiles['first_tent']['limits'],{'sizes':[[4,4],[10000,0],[10000,0]],'minimum':4,'maximum':4,'biomes':7})
        self.assertEqual(profiles['locked']['limits'],{'sizes':[[10000,0],[10000,0],[10000,0]],'minimum':10000,'maximum':0,'biomes':0})
