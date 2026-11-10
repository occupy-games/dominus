import unittest

from tools.check_architecture import ROOT, check_tree, violations


class ArchitectureTests(unittest.TestCase):
    def test_repository_boundaries(self):
        self.assertEqual(check_tree(ROOT), [])

    def test_plain_simulation_and_explicit_rng_are_allowed(self):
        source = '''extends RefCounted
const Rules = preload("res://simulation/rules.gd")
var position := Vector2i.ZERO
func initialize(rng: RandomNumberGenerator) -> void:
    rng.seed = 123
'''
        self.assertEqual(violations(source, "simulation"), [])

    def test_scene_services_and_global_randomness_are_rejected(self):
        for token in ("Node3D", "Input", "FileAccess", "Time", "PhysicsServer3D", "randi"):
            with self.subTest(token=token):
                self.assertTrue(violations(f"extends RefCounted\nvar service = {token}", "simulation"))

    def test_assets_and_cross_layer_dependencies_are_rejected(self):
        for path in ("res://presentation/world.gd", "res://assets/tree.png", "uid://opaque", "res://simulation/../presentation/world.gd"):
            with self.subTest(path=path):
                self.assertTrue(violations(f'extends RefCounted\nconst Asset = preload("{path}")', "simulation"))
        self.assertTrue(violations('const World = preload("res://simulation/world.gd")', "presentation"))

    def test_comments_and_prose_do_not_trigger_service_checks(self):
        self.assertEqual(violations('extends RefCounted\n# Node3D uses Input\nvar label = "Time and Node3D"', "simulation"), [])


if __name__ == "__main__":
    unittest.main()
