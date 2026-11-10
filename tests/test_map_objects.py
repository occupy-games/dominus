import copy
from pathlib import Path
import unittest

from tools.current_cards import decode_archive
from tools.map_objects import authored_rocks, native_rocks

SOURCE = Path(__file__).resolve().parents[1]/'data/godus2_4'


class MapObjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = (SOURCE/'godus.s86').read_bytes()
        cls.files = decode_archive((SOURCE/'received/godussteamrel/balance.datz').read_bytes())
        cls.models = (SOURCE/'GeneratedDataFiles/Models.csv').read_bytes()

    def test_authored_rock_enum_and_both_native_model_tables(self):
        native = native_rocks(self.raw)
        self.assertEqual(native['names']['rock1']['type'],25)
        self.assertEqual(native['names']['rock2']['type'],26)
        self.assertEqual(native['models']['25']['model_enum'],352)
        self.assertEqual(native['models']['25']['shadow_enum'],359)
        self.assertEqual(native['models']['25']['routine'],'0x10155d8d')

    def test_source_dimensions_and_coordinates_do_not_depend_on_density_bytes(self):
        data = authored_rocks(self.files,self.raw,self.models,'initialworldsetup6')
        rock = data['entries'][0]
        self.assertEqual(rock, {'source_line':2,'source_type':'rock1','type':25,
                               'origin_x':160,'origin_z':122,'size_x':2,'size_z':2,
                               'x':161.,'z':123.,'rotation':0.,'belief':4,
                               'model_name':'boulder6','shadow_name':'boulders_group_boulder6_shadow'})

    def test_missing_source_type_values_stay_unavailable(self):
        files = copy.copy(self.files)
        files['initialworldsetup6/initialmapobjects.csv'] += b'\nrock3,150,120,0,,,\n'
        data = authored_rocks(files,self.raw,self.models,'initialworldsetup6')
        self.assertEqual(len(data['entries']),1)
        self.assertEqual(data['unsupported'][0]['type'],'rock3')

    def test_changed_native_enumeration_rejects_instead_of_guessing(self):
        raw = self.raw.replace(bytes.fromhex('83fb0a730583c30aeb0383c30f899d2cfeffff'),
                               bytes.fromhex('83fb0a730583c30aeb0383c310899d2cfeffff'))
        self.assertNotEqual(raw,self.raw)
        with self.assertRaisesRegex(ValueError,'enumeration'): native_rocks(raw)
