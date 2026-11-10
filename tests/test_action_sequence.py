import hashlib
import json
from pathlib import Path
import unittest

from tools.action_sequences import extract
from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class ActionSequenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=json.loads((ROOT/'game/assets/original/campaign/action-sequences.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_action_sequence.json').read_text())
        cls.cases={row['name']:row['expected'] for row in cls.fixture['cases']}

    def test_source_identity_controls_rng_and_native_instruction_provenance(self):
        self.assertEqual(self.content,extract())
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for key in ['source_sha256','executable_sha256','tables','native_routines']:
            self.assertEqual(self.content[key],self.fixture[key])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(self.fixture['adapters'],['0x10002ac0','0x103752b0'])
        for record in self.content['identities'].values():
            self.assertEqual(image.read(int(record['address'],16),len(record['bytes'])//2).hex(),record['bytes'])
        self.assertEqual(self.content['rules'],dict(capacity=20,iteration_limit=21,random_divisor=32767.,rng_multiplier=214013,rng_increment=2531011,rng_shift=16,rng_mask=32767))
        self.assertEqual(self.fixture['default'],{key:self.content['default_state'][key] for key in ['next','skip_to','skip_probability']})

    def test_every_authored_state_and_source_name_survives_extraction(self):
        archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
        files=decode_archive(archive)
        for path,fingerprint in self.content['tables'].items():
            self.assertEqual(hashlib.sha256(files[path]).hexdigest(),fingerprint)
        source=rows(files,'balance/actionstates.csv')
        expected=[dict(zip(source[0],row)) for row in source[1:] if row and row[0]]
        observed=[state['source'] for action in self.content['actions'] for state in action['states']]
        self.assertCountEqual(expected,observed)
        self.assertEqual(len(observed),446)
        self.assertEqual(len(self.content['actions']),108)
        names={row['name']:row['id'] for row in self.content['actions']}
        self.assertEqual({key:names[key] for key in ['BuildPlot','BuildHouse','BuildFarm','BuildMine']},dict(BuildPlot=102,BuildHouse=103,BuildFarm=108,BuildMine=111))

    def test_source_blanks_are_unavailable_and_do_not_acquire_invented_defaults(self):
        incomplete=[(action['name'],row) for action in self.content['actions'] for row in action['states'] if not row['available']]
        self.assertEqual([(name,row['index']) for name,row in incomplete],[('FountainCelebrate',3),('AstariTaunt1',16),('AstariTaunt1',17),('AstariTaunt1',18)])
        for _,row in incomplete:
            self.assertNotIn('next',row)
            self.assertNotIn('skip_to',row)
            self.assertNotIn('skip_probability',row)

    def test_native_skip_boundary_lost_guard_and_by_value_behavior(self):
        self.assertEqual(self.cases['probability_one']['index'],1)
        self.assertEqual(self.cases['probability_equal']['index'],0)
        self.assertEqual(self.cases['probability_equal']['random_state'],0x7fff0000)
        self.assertEqual(self.cases['probability_loop']['random_calls'],21)
        self.assertEqual(self.cases['probability_loop']['queries'],[])
        self.assertEqual(self.cases['loop_guard']['queries'],[0]*21)
        self.assertEqual(self.cases['lost_persists']['queries'],[0,1])
        self.assertEqual(self.cases['lost_persists']['index'],0)
        self.assertEqual(self.cases['by_value_check']['queries'],[0,5])
        self.assertEqual(self.cases['probability_zero']['random_state'],1)
