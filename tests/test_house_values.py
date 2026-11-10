import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.current_cards import decode_archive, rows
from tools.house_values import extract, native_fields, resolve

ROOT = Path(__file__).resolve().parents[1]


class HouseValueTests(unittest.TestCase):
    def test_native_inheritance_and_supplied_house_records(self):
        with tempfile.TemporaryDirectory() as directory:
            data=extract(output=Path(directory))
        stored=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
        self.assertEqual(data,stored)
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(data['native']['executable_sha256'],hashlib.sha256(raw).hexdigest())
        files=decode_archive((ROOT/'data/godus2_4'/data['source']).read_bytes())
        self.assertEqual(data['table_sha256'],hashlib.sha256(files[data['table']]).hexdigest())
        self.assertEqual(len(data['records']),62)
        self.assertEqual(len(data['native']['fields']),53)
        self.assertEqual(data['native']['fields']['base size']['arithmetic'],'int32')
        self.assertEqual(data['native']['fields']['build time']['arithmetic'],'float32')
        tent=data['records']['AbodeType_0_Rank_1']
        self.assertEqual(tent['parent'],'Base_Rank_1')
        for key,value in [('base size',4),('capacity',2),('build capacity',1),('build time',7.5),('visionradius',12),('birth rate',5),('max belief',0)]:
            self.assertEqual(tent['values'][key],value)
        self.assertAlmostEqual(tent['values']['new builder contribution'],.3,places=6)
        # Columns absent from the current CSV and the source's literal 'd' are
        # left unresolved rather than silently assigned invented defaults.
        self.assertIn('belief height modifier',tent['unresolved'])
        self.assertEqual(data['records']['AbodeType_2_Rank_2']['unresolved']['bbheight'],'d')

    def test_unknown_native_arithmetic_and_parent_order_reject(self):
        raw=bytearray((ROOT/'data/godus2_4/godus.s86').read_bytes())
        evidence=native_fields(raw)
        routine=bytes.fromhex(evidence['bytes'])
        raw[raw.index(routine)]=0
        with self.assertRaises(ValueError): native_fields(raw)
        files=decode_archive((ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes())
        table=rows(files,'balance/housevalues.csv')
        child=next(row for row in table if len(row)>4 and row[4]=='AbodeType_0_Rank_1')
        with self.assertRaises(ValueError): resolve([table[0],child],evidence)
