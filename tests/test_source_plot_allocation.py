import hashlib
import json
from pathlib import Path
import unittest

from tools.campaign import packed_map
from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/'game/assets/original/campaign'


class SourcePlotAllocationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_plot_allocation.json').read_text())
        cls.raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        cls.archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
        cls.files=decode_archive(cls.archive)

    def test_native_scan_and_all_explicit_input_provenance(self):
        f=self.fixture
        self.assertEqual(hashlib.sha256(self.raw).hexdigest(),f['executable_sha256'])
        self.assertEqual(hashlib.sha256(self.archive).hexdigest(),f['source_sha256'])
        self.assertEqual(hashlib.sha256((DIRECTORY/'homeworld6-scenery.bin').read_bytes()).hexdigest(),f['scenery_sha256'])
        fields,*_=packed_map(ROOT/'data/godus2_4/stream/Homeworld6.pack')
        for key in ['terrain','plotrot']: self.assertEqual(hashlib.sha256(fields[key]).hexdigest(),f[key+'_sha256'])
        x0,z0,x1,z1=f['bounds']
        self.assertEqual(bytes(fields['plotrot'][z*1024+x] for z in range(z0,z1) for x in range(x0,x1)).hex(),f['plotrot_region'])
        configuration={row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(self.files,path) if len(row)>1}
        for key,value in f['configuration'].items(): self.assertEqual(value,configuration[key])
        image=NativeImage(self.raw)
        for address,code in f['native_routines'].items(): self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertIn('0x101c0760',f['adapters']) # Ordered cell storage adapter.
        self.assertNotIn('0x10237580',f['adapters']) # Actual footprint reservation loop executes.

    def test_source_geometry_observations_and_reservations(self):
        cases={c['name']:c for c in self.fixture['cases']}
        self.assertEqual({k:len(c['plots']) for k,c in cases.items()},
                         {'cleared':0,'sculpted':1,'forbidden_byte':0,'byte64':1,'byte127':0,'byte128':1,'flat_patch':13,'mixed_sizes':9,'wrong_location':0})
        self.assertEqual(cases['sculpted']['plots'],[{'id':0,'x':158.,'z':120.,'size':4,'height':6.,'center':[160.,122.],'radius':2.}])
        for case in cases.values():
            used=set()
            ordering=[]
            for plot in case['plots']:
                cells={(int(plot['z'])+dz)*1024+int(plot['x'])+dx for dz in range(plot['size']) for dx in range(plot['size'])}
                self.assertFalse(used.intersection(cells))
                used.update(cells)
                ordering.append((-plot['size'],plot['z'],plot['x']))
            self.assertEqual(ordering,sorted(ordering))

    def test_original_homeworld_and_weyworld_biome_observations(self):
        cases={c['scope']:c for c in self.fixture['biome_cases']}
        self.assertEqual(sum(len(c['samples']) for c in cases.values()),704)
        for scope,case in cases.items():
            path=scope+'/biomes.csv'
            self.assertEqual(hashlib.sha256(self.files[path]).hexdigest(),case['sha256'])
            self.assertEqual(rows(self.files,path),case['rows'])
        home=cases['initialworldsetup6']
        self.assertEqual({s[3] for s in home['samples']},{0})
        way={(s[0],s[1]):s[2:] for s in cases['initialworldsetup7']['samples']}
        self.assertEqual(way[(132.,259.)],[17,1])
        self.assertEqual(way[(117.,294.)],[19,2])
        self.assertEqual(way[(259.,315.)],[18,3])
        self.assertEqual(way[(146.,259.)],[-1,0])
        self.assertEqual(way[(145.875,259.)],[17,1])
