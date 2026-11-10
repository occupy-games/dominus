import hashlib
import json
import unittest

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.storm_chests import extract


class SourceAvailabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'game/tests/fixtures/source_availability.json').read_text())
        cls.cases={c['name']:c for c in cls.fixture['cases']}

    def test_original_capacity_and_ownership_instructions_execute(self):
        raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.fixture['executable_sha256'])
        content=extract()
        self.assertEqual(content['source_sha256'],self.fixture['source_sha256'])
        image=NativeImage(raw)
        self.assertEqual(set(self.fixture['adapters']),{'0x10179af0'})
        for address,code in self.fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
            self.assertNotIn(address,self.fixture['adapters'])
        self.assertEqual(content['availability_rules']['unregistered_limit'],0x0fffffff)

    def test_stock_and_lifetime_limits_remain_distinct(self):
        self.assertEqual(self.cases['spent_frees_stock']['states'][0]['value'],7)
        self.assertEqual(self.cases['spent_does_not_free_lifetime']['states'][0]['value'],0)
        self.assertEqual(self.cases['acquisition_cap']['states'][0]['value'],6)
        self.assertEqual(self.cases['stock_cap']['states'][0]['value'],8)
        self.assertEqual(self.cases['owned_underflow']['states'][1]['value'],4294967288)

    def test_unknown_is_not_an_existence_test(self):
        case=self.cases['unknown']
        self.assertEqual(case['states'][0]['value'],0x0fffffff)
        self.assertEqual([e['kind'] for e in case['states'][0]['events']],['acquisition','stock'])
        self.assertEqual(case['states'][3]['events'],[])
        self.assertTrue(case['states'][0]['state']['stock_registered']['@17'])
        self.assertTrue(case['states'][0]['state']['acquisition_registered']['@17'])
        reset=self.cases['unknown_resets_existing']['states'][0]
        self.assertEqual(reset['state']['stock_limits']['@17'],0x0fffffff)
        self.assertEqual(reset['state']['acquisition_limits']['@17'],0x0fffffff)
        self.assertEqual(self.cases['registered_missing_values']['states'][0]['value'],0)
        self.assertEqual(self.cases['collision_chains']['states'][0]['events'],[])
        self.assertEqual(len(self.cases['colliding_unregistered']['states'][0]['events']),2)

    def test_original_chest_loop_uses_actual_capacity_instructions(self):
        fixture=json.loads((ROOT/'game/tests/fixtures/source_chest_reward_capacity.json').read_text())
        self.assertEqual(fixture['executable_sha256'],self.fixture['executable_sha256'])
        self.assertNotIn('0x10001600',fixture['adapters'])
        self.assertIn('0x10001600',fixture['observation_hooks'])
        image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
        for address,code in fixture['native_routines'].items():
            self.assertEqual(image.read(int(address,16),len(code)//2).hex(),code)
        cases={c['name']:c for c in fixture['cases']}
        grants=lambda name:[e[2][0] for s in cases[name]['states'] for e in s['events'] if e[0]=='grant']
        for name in ['stock_full','lifetime_full','zero_limit']:
            self.assertEqual(grants(name),['Reward_ChestSticker'])
        for name in ['unknown','stock_released','unsigned_over_limit']:
            self.assertEqual(grants(name),['Reward_RandomStickerOrGem'])
        self.assertEqual(grants('bonus_with_stock'),['Reward_RandomStickerOrGem','Reward_BonusChestSticker'])
        for case in cases.values():
            self.assertEqual(case['states'][-1]['chests'],[])


if __name__=='__main__':unittest.main()
