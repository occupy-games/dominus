import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.campaign_scenarios import extract
from tools.current_cards import decode_archive
from tools.leash_lesson import extract as extract_leash_lesson
from tools.voyage_lua import compile_script

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'data/godus2_4'


class CampaignScenarioTests(unittest.TestCase):
    def test_authored_manual_starts_route_and_provenance(self):
        with tempfile.TemporaryDirectory() as output:
            data = extract(SOURCE,Path(output))
            stored = json.loads((ROOT/'game/assets/original/campaign/homeworld6-story.json').read_text())
            self.assertEqual(json.loads(json.dumps(data)), stored)
            self.assertEqual(data['builder_settlement'], {
                'power': 'GodPower_PlaceSettlement_1', 'cost': 3000, 'radius_setting': 'SettCompRadius2'})
            self.assertEqual(data['mining_settlement'], {
                'power': 'GodPower_PlaceSettlement_3', 'cost': 7500, 'radius_setting': 'SettCompRadius3'})
            self.assertEqual((data['ark']['site_id'], data['ark']['position'], data['ark']['beacon']), ('1036', [345,300], [327,310]))
            self.assertEqual((data['ark']['astari'], data['ark']['scan_seconds'], data['ark']['festival']['AstariFestivalLength']), ([307,317,3],10,30))
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
            self.assertEqual([step['name'] for step in data['belief_steps']], [
                'BeliefStep00_ShowCard','BeliefStep01_CardDismissed',
                'BeliefStep02_CollectBelief','BeliefStep03_SculptGrass'])
            self.assertEqual(data['belief_rules']['executable_sha256'],data['day_cycle']['executable_sha256'])
            self.assertEqual(data['constants']['SCULPT_GRASS_POS'],{'x':159,'y':136.75,'z':7.5})
            self.assertEqual(data['messages']['4007']['hintDelay'],30)
            self.assertEqual(len(data['authored_fields']), 15)
            self.assertEqual(data['authored_fields'][0], {'x':149, 'z':213, 'size':7})
            self.assertEqual(len(data['discovery']['SuperFast']), 5)
            self.assertIn('onCollectGrain', data['discovery']['SuperFast'][2]['hooks'])
            self.assertEqual(data['pit_clips']['sha256'], hashlib.sha256((SOURCE/'follower.group.bin').read_bytes()).hexdigest())
            self.assertAlmostEqual(data['pit_clips']['clips']['sacrifice_1'], 8.13333, places=5)
            self.assertAlmostEqual(data['pit_clips']['clips']['sacrifice_2'], 6.53333, places=5)
            self.assertAlmostEqual(data['pit_clips']['audio_delay'], 7.8, places=5)
            self.assertEqual(data['pit_clips']['roll_divisor'], 32767)
            self.assertEqual(data['pit_beam']['model'], 'vfx.group.bin:55c4ce73')
            self.assertEqual(data['pit_beam']['curve'], [[0,0],[0.5,0.8],[2,0.1],[8,0]])
            rain = data['rain']
            self.assertEqual((rain['fields'],rain['card'],rain['power']), (5,'Card_Adv_RainOfPurity_1','GodPower_RainOfPurity'))
            self.assertEqual((rain['cost_per_second'],rain['radius'],rain['growth_bonus']), (100,1,100))
            fountain = data['fountain']
            self.assertEqual((fountain['population'],fountain['gems'],fountain['model']), (260,10,'giftfountain02.group.bin:dff1563f'))
            self.assertEqual((fountain['width'],fountain['depth'],fountain['happiness']), (2,1,0.1))
            cliff = data['cliff_sculpt']
            self.assertEqual((cliff['population'],cliff['card'],cliff['power']), (200,'Card_CliffSculptingLevel1','GodPower_CliffSculpt'))
            self.assertEqual((cliff['layers'],cliff['belief_multiplier'],cliff['belief_threshold']), (3,0.1,2))
            self.assertEqual([(u['layers'],u['currency'],u['cost']) for u in cliff['upgrades']],
                             [(5,'gems',10),(9,'wheat',100),(12,'ore',100)])
            rock = data['rock_belief']
            self.assertEqual((rock['population'],rock['amounts']['25'],rock['multipliers']['25']), (75,4,10))
            collector = data['belief_collector']
            self.assertEqual((collector['population'],collector['model'],collector['prices'][0]), (95,'shrine.group.bin:dff1563f',1000))
            self.assertEqual((collector['interval'],collector['wait'],collector['radius']), (1,30,10))
            self.assertEqual([(u['radius'],u['multiplier'],u['cost']) for u in collector['upgrades']], [(15,1.1,10),(20,1.2,20)])
            manifest=json.loads((Path(output)/'homeworld6-opening.json').read_text())
            self.assertEqual(manifest['story_version'],data['version'])
            raw=(Path(output)/Path(manifest['height_data']).name).read_bytes()
            self.assertEqual(raw[53*1024+163],19)
            self.assertEqual(hashlib.sha256(raw).hexdigest(),manifest['height_sha256'])
            lesson_terrain, lesson = extract_leash_lesson(SOURCE)
            self.assertEqual((Path(output)/'leash-lesson.bin').read_bytes(), lesson_terrain)
            self.assertEqual(json.loads((Path(output)/'leash-lesson.json').read_text()), json.loads(json.dumps(lesson)))
            self.assertEqual(lesson['mission'],3)
            self.assertEqual(lesson['map'],'TERRAIN13_LeashTutorial')
            self.assertEqual(len(lesson['followers']),5)
            self.assertEqual(lesson['temple']['build_capacity'],4)

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
