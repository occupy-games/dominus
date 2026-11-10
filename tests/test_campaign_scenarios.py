import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.campaign_scenarios import extract
from tools.current_cards import decode_archive
from tools.voyage_lua import compile_script

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'data/godus2_4'


class CampaignScenarioTests(unittest.TestCase):
    def test_authored_manual_starts_route_and_provenance(self):
        with tempfile.TemporaryDirectory() as output:
            data = extract(SOURCE,Path(output))
            stored = json.loads((ROOT/'game/assets/original/campaign/homeworld6-story.json').read_text())
            self.assertEqual(json.loads(json.dumps(data)), stored)
            archive = (SOURCE/data['source']).read_bytes()
            files = decode_archive(archive)
            self.assertEqual(hashlib.sha256(archive).hexdigest(),data['source_sha256'])
            for name,digest in data['files_sha256'].items():
                self.assertEqual(hashlib.sha256(files[name]).hexdigest(),digest)
            self.assertEqual([(p['x'],p['z']) for p in data['starts']],[(162.7,53.2),(163.3,52.8)])
            self.assertEqual([p['source_args'][5] for p in data['starts']],[False,True])
            self.assertEqual(len(data['route']),14)
            self.assertEqual(data['route'][0]['entry']['Target'],{'x':164,'y':58,'z':7.199999999999999})
            self.assertEqual(data['route'][-1]['entry']['Target'],data['constants']['PROMISED_LAND'])
            self.assertIn('onBlocked',data['route'][1]['entry'])
            self.assertEqual(data['constants']['followerOffscreenCutoff'],.1)
            self.assertIn('cameraEndUpdate',data['helpers'])
            self.assertIn('checkOnPreTutorialFollowers',data['helpers'])
            self.assertIn('waitForSecondFollowerLoop',data['waiting_hooks'])
            self.assertIn('onStartPlay',data['waiting_hooks'])
            self.assertEqual(len(data['promised_steps']),11)
            self.assertEqual(data['promised_steps'][1]['name'],'PromisedLandStep01_RemoveRock')
            self.assertEqual(data['object_config']['taps_to_destroy_rock'],1)
            first_rock = data['authored_rocks']['entries'][0]
            self.assertEqual((first_rock['origin_x'],first_rock['origin_z']), (160,122))
            self.assertEqual((first_rock['x'],first_rock['z']), (161,123))
            self.assertEqual((first_rock['size_x'],first_rock['size_z']), (2,2))
            self.assertEqual((first_rock['type'],first_rock['model_name']), (25,'boulder6'))
            self.assertEqual(first_rock['belief'],4)
            self.assertEqual(data['authored_rocks']['unsupported'],[])
            self.assertEqual(data['authored_rocks']['native']['executable_sha256'],data['day_cycle']['executable_sha256'])
            self.assertEqual(data['messages']['1002']['object_get'],{'symbol':'getFirstRock'})
            self.assertIn('Followers',data['messages']['4']['text'])
            manifest=json.loads((Path(output)/'homeworld6-opening.json').read_text())
            raw=(Path(output)/Path(manifest['height_data']).name).read_bytes()
            self.assertEqual(raw[53*1024+163],19)
            self.assertEqual(hashlib.sha256(raw).hexdigest(),manifest['height_sha256'])

    def test_lua_leading_decimal_literals_preserve_source_offsets(self):
        program=compile_script('x = 163-.3\ny = 53+.2\nobject.x = .5e1')
        self.assertEqual(program['body'][0][2],['binary','-',['literal',163],['literal',.3]])
        self.assertEqual(program['body'][1][2],['binary','+',['literal',53],['literal',.2]])
        self.assertEqual(program['body'][2][2],['literal',5.0])

    def test_lua_method_receiver_break_and_multiple_local_binding(self):
        program=compile_script('local x,y=FollowerPos(1)\nfor i=1,3 do if i==2 then break end obj:arrive(i) end')
        self.assertEqual(program['body'][0][0],'local_many')
        loop=program['body'][1][5]
        self.assertEqual(loop[0][1][0][1],[['break']])
        self.assertEqual(loop[1],['expr',['method_call',['var','obj'],'arrive',[['var','i']]]])
