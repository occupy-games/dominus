import hashlib
import json
from pathlib import Path
import re
import unittest

from tools.current_cards import decode_archive, rows

ROOT = Path(__file__).resolve().parents[1]


class CampaignRulesTests(unittest.TestCase):
    def test_research_and_economy_records_preserve_current_source(self):
        data = json.loads((ROOT / 'game/assets/original/campaign/research-rules.json').read_text())
        source = ROOT / 'data/godus2_4'
        archive = (source / data['source']).read_bytes()
        self.assertEqual(hashlib.sha256(archive).hexdigest(), data['source_sha256'])
        files = decode_archive(archive)
        for name, digest in data['tables_sha256'].items():
            self.assertEqual(hashlib.sha256(files[name]).hexdigest(), digest)
        versions = dict(rows(files, 'homeworldver.csv'))
        weyworld = data['world_registrations'][f"homeworld{versions['1']}"]
        self.assertEqual(weyworld['scope'], 'initialworldsetup' + versions['1'])
        for table in ('info', 'influence_areas', 'rewardchests', 'biomes'):
            self.assertEqual(weyworld[table], rows(files, f"{weyworld['scope']}/{table}.csv"))
        script = files[weyworld['harvest_source']['path']]
        self.assertEqual(hashlib.sha256(script).hexdigest(), weyworld['harvest_source']['sha256'])
        text = script.decode('utf-8-sig')
        tutorial = weyworld['tutorial']
        self.assertIn(f"SetCameraBaseRotation({tutorial['camera_degrees']}, 1)", text)
        self.assertEqual(tutorial['verdant'], [130,255,33])
        self.assertEqual(tutorial['rugged'], [116,290,38])
        self.assertEqual(tutorial['hallowed'], [[168,175,20],[178,444,38]])
        self.assertEqual(tutorial['granite'], [167,390,17])
        self.assertEqual([row['key'] for row in tutorial['messages'].values()],
                         [f'LOC_WeyTut_{number:02}' for number in range(1,7)])
        arrival = weyworld['arrival']
        self.assertEqual(arrival['followers'], [{'x': 40, 'z': 290, 'female': False}, {'x': 44, 'z': 311, 'female': True}])
        for record in arrival['followers']:
            sex = str(record['female']).lower()
            self.assertIn(f"SpawnFollower(0,{record['x']},{record['z']},0,0,{sex},0);", text)
        ark = arrival['ark']
        self.assertIn(f"BOAT_POS = {{x={ark['x']},y={ark['z']}}}", text)
        self.assertIn(f"Table(\"House Values\", \"Capacity\", {ark['house_row']}, pop)", text)
        data_rows = [row for row in rows(files, 'balance/housevalues.csv') if row and row[0].isdigit()]
        self.assertEqual(data_rows[ark['house_row']-1][2], ark['model'])
        for name, kind, count in [('FREE_FIELDS', 'farm', 4), ('FREE_MINES', 'mine', 14)]:
            block = text.split(f'{name} =', 1)[1].split('\n}', 1)[0]
            source_sites = [tuple(map(int, match)) for match in re.findall(r'x=(\d+),\s*y=(\d+),\s*size=(\d+)', block)]
            self.assertEqual(len(source_sites), count)
            self.assertEqual([(site['x'], site['z'], site['size']) for site in weyworld['harvest_sites'] if site['kind'] == kind], source_sites)
        for prefix, scope in data['scopes'].items():
            for currency in ['grain', 'ore']:
                name = prefix + '/' + currency + 'levels.csv'
                expected = [{'population': int(row[0]), 'card': row[1]} for row in rows(files, name)
                            if len(row)>1 and row[0].isdigit()] if name in files else []
                self.assertEqual(scope['currency_levels'][currency], expected)
            for row in rows(files, prefix + '/carddata.csv'):
                if not row or row[0] not in scope['cards']:
                    continue
                card = scope['cards'][row[0]]
                self.assertEqual(card['research_type'], row[7])
                self.assertEqual(card['research_needed'], int(row[8] or 0))
                self.assertEqual(card['prerequisite'], row[11] if len(row) > 11 else '')
            # Duplicate unlock rows are alternatives, not silently overwritten.
            for row in rows(files, prefix + '/unlocks.csv'):
                if len(row) > 1 and row[0] and not row[0].startswith('#'):
                    self.assertIn(row[1].strip(), scope['unlocks'][row[0]])
        self.assertEqual(len(data['scopes']), 7)
        self.assertEqual(data['stickers']['Sticker_Rare_Settlement']['contributions'], {'TRADE': 1000})
        self.assertEqual(data['configuration']['SettWorkerBirthRateSec0'], 30)
        self.assertEqual(data['native_configuration']['SettWorkerBirthRateSec0']['value'], 2700)
        self.assertEqual(data['configuration']['SettlementFarmerMaxPop'], 50)
        self.assertEqual(data['configuration']['PlayerStartingHappiness'], .2)
        self.assertEqual(data['configuration']['AstariStartingHappiness'], .3)
        self.assertEqual(data['configuration']['HappyDecayPerSec'], -.000000125)
        self.assertEqual(data['tables']['balance/housevalues.csv'], rows(files, 'balance/housevalues.csv'))


if __name__ == '__main__':
    unittest.main()
