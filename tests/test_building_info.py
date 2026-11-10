import hashlib
import json
from pathlib import Path
import unittest

from tools.building_info import extract

ROOT=Path(__file__).resolve().parents[1]


class BuildingInfoTests(unittest.TestCase):
    def test_illustrations_labels_and_layouts_keep_original_provenance(self):
        content=json.loads((ROOT/'game/assets/original/ui/building-info.json').read_text())
        self.assertEqual(content,extract())
        self.assertEqual(content['labels']['LOC_ROWNAME_HOME_TIME_TILL_FULL'],'Next Follower In:')
        self.assertEqual(content['records']['AbodeType_0_Rank_1']['title'],'Shelter')
        self.assertEqual(content['records']['Temple_Shrine_LandExp']['title'],'Beacon')
        self.assertEqual(content['records']['Temple_Dock_Event']['illustration_source'],'Scaleform_Compiled/Resources/Info_Panel/Info_Dock_Event.png')
        self.assertIn('LOC_TEMPLE_INFO_DESCRIP_EXPANSION',content['labels'])
        for record in content['records'].values():
            raw=(ROOT/'data/godus2_4'/record['illustration_source']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(),record['image_sha256'])
            self.assertEqual((ROOT/'game'/record['texture_path'].removeprefix('res://')).read_bytes(),raw)
