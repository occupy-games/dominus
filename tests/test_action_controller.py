import json
from pathlib import Path
import unittest

from tools.action_controller import extract
from tools.action_sequences import extract as sequences
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


class ActionControllerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=json.loads((ROOT/'game/assets/original/campaign/action-controller.json').read_text())
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_action_controller.json').read_text())
        cls.cases={row['name']:row['expected'] for row in cls.fixture['cases']}

    def test_controller_selector_entry_rng_and_reference_code_all_execute(self):
        self.assertEqual(self.content,extract())
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for key in ['source_sha256','executable_sha256','tables','native_routines']:
            self.assertEqual(self.content[key],self.fixture[key])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        for address in ['0x10002ac0','0x10002150','0x1016b140','0x10008860','0x100e4180']:
            self.assertIn(address,self.fixture['adapters'])
        self.assertEqual(self.content['default_state'],self.fixture['default_state'])
        self.assertEqual(self.content['rules'],dict(house_actions=[103,108,111],temple_actions=[114,115],temple_state=6,decision_phase=2,native_slot=255))

    def test_original_flags_and_looping_map_every_source_action(self):
        source={row['id']:row for row in sequences()['actions']}
        self.assertEqual(len(source),len(self.content['actions']))
        for action in self.content['actions']:
            original=source[action['id']]
            self.assertEqual(action['name'],original['name'])
            self.assertEqual(action['looping'],bool(int(original['description'].get('Looping','0'))))
            states={state['index']:state for state in original['states']}
            self.assertEqual(len(states),len(action['states']))
            for state in action['states']:
                raw=states[state['index']]['source']
                if state['available']:
                    self.assertEqual(state['terminable'],int(raw['Terminable'])!=0)
                    self.assertEqual(state['face_end'],int(raw['FaceTargetEnd'])!=0)
                    self.assertEqual(state['end_skip'],int(raw['EndSkipState']))

    def test_failure_fallback_loop_restart_and_raw_result_are_distinct(self):
        self.assertEqual(self.cases['next']['actor']['step'],1)
        self.assertEqual(self.cases['end_skip']['actor']['step'],4)
        self.assertEqual(self.cases['end_skip_zero']['actor']['step'],2)
        self.assertEqual(self.cases['next_jump']['actor']['step'],1)
        self.assertTrue(self.cases['terminable_failure']['result'])
        self.assertEqual(self.cases['terminable_failure']['queries'],[])
        self.assertFalse(self.cases['unterminable_failure']['result'])
        self.assertEqual(self.cases['loop_restart']['actor']['step'],0)
        self.assertFalse(self.cases['retry_failure_ignored']['result'])
        self.assertEqual(self.cases['retry_failure_ignored']['actor']['clip'],347)
        self.assertEqual(self.cases['source_probability']['actor']['step'],5)
        self.assertEqual(self.cases['source_probabilities']['actor']['step'],7)

    def test_end_audio_and_queued_decision_precede_cached_path_cleanup(self):
        self.assertEqual(self.cases['end_audio']['log'],[['end_sound',1],['decision',19,2,0x01000001]])
        self.assertEqual(self.cases['phase_two_end']['log'],[['decision',19,2,0x01000001]])
        for name in ['cached_same','cached_same_uid','cached_same_position','invalid_cached']:
            result=self.cases[name]
            self.assertEqual(result['log'][-1],['reset_navigation'])
            self.assertEqual(result['actor']['cached_target'],{})
            self.assertEqual(result['actor']['target']['identity'],0x1f000000)
            self.assertEqual(result['actor']['path_time'],0.)
            self.assertEqual(result['actor']['gate_slot'],255)
            self.assertTrue(result['actor']['failed'])
        self.assertEqual(self.cases['cached_other']['actor']['path_time'],9.)
        self.assertEqual(self.cases['cached_same']['log'][0],['decision',19,2,0x01000001])
        self.assertEqual(self.cases['stale_target']['log'][-1],['decision',19,2,0x1f000000])
        self.assertNotIn('end_sound',[event[0] for event in self.cases['temple_complete']['log']])
        self.assertIn('end_sound',[event[0] for event in self.cases['temple_incomplete']['log']])
