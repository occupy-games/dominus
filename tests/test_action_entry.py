import json
from pathlib import Path
import unittest

from tools.action_entry import extract
from tools.action_sequences import extract as sequences
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class ActionEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=json.loads((ROOT/'game/assets/original/campaign/action-entry.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_action_entry.json').read_text())
        cls.cases={row['name']:row['expected'] for row in cls.fixture['cases']}

    def test_original_entry_and_enumeration_instruction_provenance(self):
        self.assertEqual(self.content,extract())
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for key in ['source_sha256','executable_sha256','tables','native_routines']:
            self.assertEqual(self.content[key],self.fixture[key])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address,code in self.content['enumeration_evidence'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        self.assertEqual(self.fixture['adapters'],['0x10002150','0x10035fd0','0x1015fd00','0x1015fda0'])

    def test_every_source_entry_has_an_explicit_available_or_unavailable_record(self):
        source=sequences()
        rows={(action['id'],state['index']):state['source'] for action in source['actions'] for state in action['states']}
        self.assertEqual(len(rows),len(self.content['records']))
        for record in self.content['records']:
            row=rows[(record['action'],record['index'])]
            self.assertEqual(record['update_name'],row['UpdateType'])
            if record['available']:
                self.assertEqual(record['update_type'],self.content['update_types'][row['UpdateType']])
                self.assertEqual(record['loop'],int(row['Loop'])!=0)
            else:
                self.assertEqual(row['Loop'],'')
                self.assertNotIn('loop',record)
                self.assertNotIn('update_type',record)
        self.assertEqual(len(self.content['update_types']),52)
        self.assertEqual(sum(row['available'] for row in self.content['records']),443)
        self.assertEqual(self.content['update_types']['MoveTo'],4)
        self.assertEqual(self.content['update_types']['AnimationEndFaceTarget'],51)

    def test_missing_clip_preserves_native_update_gate_and_call_order(self):
        self.assertEqual(self.content['rules']['missing_clip'],347)
        self.assertEqual(self.content['rules']['missing_update'],200)
        self.assertTrue(self.cases['last_clip']['result'])
        self.assertTrue(self.cases['missing_navigation_update']['result'])
        self.assertTrue(self.cases['missing_lower_update']['result'])
        self.assertFalse(self.cases['missing_animation_update']['result'])
        self.assertFalse(self.cases['missing_higher_update']['result'])
        failed=self.cases['missing_animation_update']
        self.assertEqual([entry[0] for entry in failed['log']],['resolve','duration','animate'])
        self.assertEqual([entry[0] for entry in self.cases['first']['log']],['resolve','orientation','duration','animate'])
        self.assertEqual([entry[0] for entry in self.cases['no_channel']['log']],['resolve','duration'])

    def test_complete_entry_resets_timings_and_keeps_by_value_resolver_changes(self):
        for case in self.fixture['cases']:
            actor=case['expected']['actor']
            self.assertEqual(actor['step'],case.get('index',0))
            self.assertFalse(actor['entry_done'])
            self.assertEqual(actor['clip_phase'],0.)
            self.assertEqual(actor['clip_time'],0.)
        self.assertTrue(self.cases['by_value_loop']['log'][-1][2])
        self.assertEqual(self.cases['negative_duration']['actor']['clip_duration'],-1.)
        self.assertEqual(self.cases['zero_duration']['actor']['clip_duration'],0.)
