import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT


class WeightedRewardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_weighted_rewards.json').read_text())

    def test_original_selection_instructions_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        image=NativeImage(raw)
        self.assertEqual(self.fixture['adapters'],['0x1035f7f0'])
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])

    def test_override_and_empty_draws_preserve_rng_consumption(self):
        for case in self.fixture['cases']:
            self.assertEqual(case['expected']['random_calls'],int(case['override']==0))
        eras={entry['value']:entry for entry in self.fixture['eras']}
        self.assertEqual([eras[i]['bucket'] for i in range(7)],[0,0,1,2,3,3,3])
        self.assertEqual([eras[i]['era'] for i in range(7)],[1,2,3,4,1,1,1])
        self.assertEqual(eras[0xffffffff]['bucket'],3)


if __name__=='__main__':unittest.main()
