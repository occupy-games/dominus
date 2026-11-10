import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from tools.current_cards import decode_archive
from tools.native_scenery_oracle import NativeImage
from tools.scenery_layout import compile_layout, source_types

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'data/godus2_4'
DIRECTORY = ROOT/'game/assets/original/campaign'


class SourceSceneryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata = json.loads((DIRECTORY/'homeworld6-scenery.json').read_text())
        cls.raw = (SOURCE/'godus.s86').read_bytes()
        cls.archive = (SOURCE/'received/godussteamrel/balance.datz').read_bytes()
        cls.files = decode_archive(cls.archive)
        cls.payload = (DIRECTORY/'homeworld6-scenery.bin').read_bytes()
        cls.records = list(struct.iter_unpack('<IffffIBBH',cls.payload[12:]))

    def test_complete_kernel_capture_keeps_original_provenance(self):
        data = self.metadata
        self.assertEqual(hashlib.sha256(self.raw).hexdigest(),data['executable_sha256'])
        self.assertEqual(hashlib.sha256(self.archive).hexdigest(),data['source_sha256'])
        self.assertEqual(hashlib.sha256(self.payload).hexdigest(),data['sha256'])
        for name,digest in data['source_files'].items(): self.assertEqual(hashlib.sha256(self.files[name]).hexdigest(),digest)
        for name,digest in data['source_fields'].items(): self.assertEqual(hashlib.sha256((DIRECTORY/('homeworld6-'+name+'.bin')).read_bytes()).hexdigest(),digest)
        image=NativeImage(self.raw)
        for address,code in data['native_routines'].items(): self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(source_types(SOURCE,self.files,image),data['types'])

    def test_counts_unique_roots_and_native_occupied_rectangles(self):
        self.assertEqual(self.payload[:12],b'DSCN'+struct.pack('<II',1,4203))
        self.assertEqual(sum(row[6]<20 for row in self.records),2937)
        self.assertEqual(sum(row[6]>=20 for row in self.records),1266)
        self.assertEqual(sum(row[7] for row in self.records),42)
        self.assertEqual(len({row[0] for row in self.records}),4203)
        occupied=set()
        for root,x,z,height,rotation,origin,kind,authored,reserved in self.records:
            self.assertEqual(reserved,0)
            size=2 if kind>=20 else 1
            cells={origin+dx+dz*1024 for dz in range(size) for dx in range(size)}
            self.assertFalse(occupied.intersection(cells))
            occupied.update(cells)
        self.assertEqual(len(occupied),8001)

    def test_native_first_rock_and_fractional_coastal_tree(self):
        self.assertEqual(self.records[0],(126113,161.,123.,6.,0.,125088,25,1,0))
        coast=next(row for row in self.records if row[0]==80001)
        self.assertEqual(coast[1:4],(129.32850646972656,78.60284423828125,6.600000381469727))
        self.assertEqual(coast[6:8],(0,0))
        heights=(DIRECTORY/'homeworld6-terrain.bin').read_bytes()
        self.assertLessEqual(heights[coast[0]],19)
        self.assertEqual(self.metadata['types']['15']['source'],'godseedtrees.group.bin')
        self.assertEqual(self.metadata['types']['0']['source'],'trees.group.bin')

    def test_wrong_native_image_or_balance_cannot_be_packaged(self):
        capture={'executable_sha256':'wrong','routine':'0x1025fcd0','bounds':[0,0,1024,1024],
                 'configuration':{'loc2Start':'25','loc3Start':'36'},'records':[]}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError,'executable'): compile_layout(capture,SOURCE,Path(directory))
            capture['executable_sha256']=self.metadata['executable_sha256']
            capture['configuration']['loc2Start']='23'
            with self.assertRaisesRegex(ValueError,'balance'): compile_layout(capture,SOURCE,Path(directory))
