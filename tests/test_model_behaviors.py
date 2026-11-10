from pathlib import Path
import struct
import unittest

from tools.model_behaviors import environment_for, decode_locators
from tools.original_assets import ROOT, resource_group, iw_hash, decode_skeleton, decode_animation, decode_model


class ModelBehaviorTests(unittest.TestCase):
    def test_original_part_anchor_registers_tent_chunk_to_whole_mesh(self):
        path = ROOT / "data/godus2_4/tents.group.bin"
        if not path.is_file(): self.skipTest("Local Godus dump not supplied")
        resources = resource_group(path.read_bytes())
        base_id = iw_hash("rank1_loc1_var1_storey1")
        locator = decode_locators(resources[iw_hash("Locator")][base_id])
        self.assertEqual(locator["type_count"], 42)
        offset = locator["parts"][1]
        base = decode_model(resources[iw_hash("CIwModel")][base_id])["vertices"]
        part = decode_model(resources[iw_hash("CIwModel")][iw_hash("rank1_loc1_var1_storey1_part01")])["vertices"]
        error = sum(min(sum((point[i]+offset[i]-candidate[i])**2 for i in range(3)) for candidate in base) for point in part)
        self.assertLess((error/len(part))**0.5, 0.001)
        with self.assertRaises(ValueError):
            decode_locators(resources[iw_hash("Locator")][base_id] + b"\0\0\0\0")

    def test_high_detail_locator_uses_its_actual_range_table_length(self):
        path = ROOT / "data/godus2_4/hiend_lowlandrural2.group.bin"
        if not path.is_file(): self.skipTest("Local Godus dump not supplied")
        resources = resource_group(path.read_bytes())
        locator = decode_locators(resources[iw_hash("Locator")][iw_hash("rank1_loc1_var1_storey1")])
        self.assertEqual(locator["type_count"], 37)
        self.assertAlmostEqual(locator["parts"][1][1], 250.73077, places=3)

    def test_habitat_distinguishes_water_units_land_buildings_and_shores(self):
        cases = {"boats.group.bin": "water", "rafts.group.bin": "water",
                 "fish.group.bin": "underwater", "eventdock.group.bin": "shore",
                 "slipway.group.bin": "shore", "arkabode.group.bin": "land",
                 "sheep.group.bin": "land", "hiend_tents.group.bin": "land"}
        for source, expected in cases.items():
            with self.subTest(source=source): self.assertEqual(environment_for(source), expected)

    def test_rotation_only_keys_preserve_source_rest_translation(self):
        path = ROOT / "data/godus2_4/chest.group.bin"
        if not path.is_file(): self.skipTest("Local Godus dump not supplied")
        resources = resource_group(path.read_bytes())
        bones = decode_skeleton(next(iter(resources[iw_hash("CIwAnimSkel")].values())))
        data = resources[iw_hash("CIwAnim")][iw_hash("chest_open")]
        self.assertEqual(data[28], 3)  # First key contains source rotations only.
        clip = decode_animation(data, len(bones), bones)
        for pose, bone in zip(clip["frames"][0]["poses"], bones):
            self.assertEqual(tuple(pose[:3]), tuple(bone["position"]))
        self.assertTrue(any(a != b for a, b in zip(clip["frames"][0]["poses"], clip["frames"][8]["poses"])))
        with self.assertRaises(ValueError): decode_animation(data + b"\0", len(bones), bones)

    def test_unknown_wolf_control_transform_is_not_silently_dropped(self):
        path = ROOT / "data/godus2_4/wolf.group.bin"
        if not path.is_file(): self.skipTest("Local Godus dump not supplied")
        resources = resource_group(path.read_bytes())
        bones = decode_skeleton(next(iter(resources[iw_hash("CIwAnimSkel")].values())))
        clip = resources[iw_hash("CIwAnim")][iw_hash("default_walk_1_up")]
        with self.assertRaisesRegex(ValueError, "extra animation transform"):
            decode_animation(clip, len(bones), bones)


if __name__ == "__main__": unittest.main()
