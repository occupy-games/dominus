import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.reward_dispatch import extract, key


class RewardDispatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content=extract()
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_reward_dispatch.json').read_text())
        cls.cases={case['name']:case for case in cls.fixture['cases']}
        cls.pending={case['name']:case for case in cls.fixture['pending_cases']}

    def test_original_dispatcher_wrappers_and_hash_routines_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/reward-dispatch.json').read_text()))
        self.assertEqual(self.content['source_sha256'],self.fixture['source_sha256'])
        image=NativeImage(raw)
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertNotIn('0x10026880',self.fixture['adapters'])
        self.assertEqual(key('Reward_RandomStickerOrGem'),620583270)
        self.assertNotEqual(key('Story0'),key('story0'))
        self.assertEqual(len(self.fixture['cases']),266)
        self.assertEqual(len(self.fixture['pending_cases']),74)

    def test_all_source_packs_and_independent_registry_dispatch(self):
        packs=[row[0] for row in self.content['tables']['initialworldsetup/packdata.csv'][1:]
               if row and row[0].startswith('Pack_')]
        self.assertEqual(len(packs),14)
        self.assertTrue(set(packs)<=self.cases.keys())
        self.assertTrue({'discovery_'+name for name in packs}<=self.pending.keys())
        events=self.cases['Pack_BigTreasure1']['expected']['events']
        self.assertEqual(sum(event[0]=='grant' for event in events),23)
        self.assertTrue(all(event[1][3]==8 for event in events if event[0]=='grant'))
        self.assertEqual(events[-1],['refresh',[],0,0])
        events=self.cases['overlapping_registries']['expected']['events']
        self.assertEqual([event[0] for event in events],['story','grant','grant'])
        self.assertEqual(events[-2][1],[50,False,18,8,1012])
        self.assertEqual(events[-1][1],[50,True,18,8,1012])

    def test_deferred_discovery_clears_flags_before_callbacks_and_rereads(self):
        first,second=self.pending['pending_7_1_True']['expected']
        self.assertEqual([event[0] for event in first['events']],
                         ['is_discovery','notification_context','unlock','grant_temple','grant','refresh'])
        self.assertEqual(first['events'][1][-1],[7,1,True])
        self.assertEqual(first['events'][2][-1],[7,0,False])
        self.assertEqual(second['events'],[['is_discovery',[],0,0,[7,0,False]]])
        changed=self.pending['unlock_changes_reward']['expected'][0]
        self.assertEqual(next(event[1][0] for event in changed['events'] if event[0]=='grant'),60)
        changed=self.pending['context_changes_id']['expected'][0]
        self.assertEqual(next(event[1][0] for event in changed['events'] if event[0]=='unlock'),'TEMPLE_COMPLETE_-2147483648')
        changed=self.pending['unlock_changes_id']['expected'][0]
        self.assertEqual(next(event[1][1] for event in changed['events'] if event[0]=='grant_temple'),4294967295)
        self.assertFalse(any(event[0]=='grant_temple' for event in self.pending['pending_7_1_False']['expected'][0]['events']))

    def test_original_homeworld_story_rows_and_full_acquisition_sequences(self):
        rows=self.content['tables']['initialworldsetup6/storypieces.csv'][1:]
        self.assertEqual(sum(row[0]=='Story11' for row in rows),2)
        for sequence in self.fixture['story_sequences']:
            self.assertEqual(len(sequence['steps']),28)
            self.assertEqual([entry['id'] for entry in sequence['records']['stories']],[key(row[0]) for row in rows])
            previous=set()
            calls=0
            for step in sequence['steps']:
                acquired=set(step['state']['stories_acquired'])
                self.assertTrue(previous<=acquired)
                self.assertGreaterEqual(step['random_calls'],calls)
                previous=acquired
                calls=step['random_calls']
        first=self.fixture['story_sequences'][0]
        self.assertEqual(first['steps'][0]['state']['stories_acquired'],[key('Story0')])
        self.assertEqual(len(first['steps'][-1]['state']['stories_acquired']),len({row[0] for row in rows}))


if __name__=='__main__':unittest.main()
