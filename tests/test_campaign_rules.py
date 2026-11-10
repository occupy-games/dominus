import hashlib
import json
from pathlib import Path
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
