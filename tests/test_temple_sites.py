import hashlib
import json
import unittest

from tools.current_cards import ROOT,decode_archive
from tools.temple_sites import extract


class TempleSiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.content=extract()

    def test_source_placements_are_reproducible(self):
        self.assertEqual(self.content,json.loads((ROOT/'game/assets/original/campaign/temple-sites.json').read_text()))
        raw=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.content['source_sha256'])
        files=decode_archive(raw)
        for path,digest in self.content['tables_sha256'].items():self.assertEqual(hashlib.sha256(files[path]).hexdigest(),digest)
        self.assertEqual(sum(len(v) for v in self.content['scopes'].values()),192)

    def test_homeworld6_beacons_costs_and_ark_are_authored(self):
        sites={s['id']:s for s in self.content['scopes']['initialworldsetup6']}
        first=sites['1012']
        self.assertEqual((first['x'],first['z'],first['source_height'],first['rotation']),(165,144,20,150))
        self.assertEqual((first['build_ticks'],first['build_capacity'],first['model']),(600,2,'shrineexpansion'))
        self.assertEqual(sites['1020']['ore_cost'],10)
        self.assertEqual(sites['1036']['food_cost'],700)
        self.assertEqual(sites['1036']['ore_cost'],500)
        self.assertEqual(sites['1036']['build_capacity'],300)
        self.assertEqual(sites['1100']['card'],'Pack_BigTreasure1')
        self.assertEqual(self.content['ambiguous_ids'],{'initialworldsetup3':['1102']})
        self.assertEqual(sum(s['id']=='1102' for s in self.content['scopes']['initialworldsetup3']),2)


if __name__=='__main__':unittest.main()
