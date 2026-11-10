from pathlib import Path
import tempfile
import unittest

from tools.geometry import assemblies_from_records, read_geo

GEO = '''// Source file: sourceart/Tree.mb
CIwModel
{
 name "tree"
 CMesh
 {
  name "body"
  scale 100
  CVerts
  {
   numVerts 4
   v {0,0,0}
   v {1,0,0}
   v {1,1,0}
   v {0,1,0}
  }
  CVertNorms
  {
   numVertNorms 1
   vn {0,0,1}
  }
  CUVs
  {
   setID 0
   numUVs 4
   uv {0,0}
   uv {1,0}
   uv {1,1}
   uv {0,1}
  }
  CSurface
  {
   material "bark"
   CQuads
   {
    numQuads 1
    q {0,0,0,-1,-1} {1,0,1,-1,-1} {2,0,2,-1,-1} {3,0,3,-1,-1}
   }
  }
 }
}
'''


class GeometryTests(unittest.TestCase):
    def test_quad_triangulation_preserves_positions_normals_uvs_and_scale(self):
        model = read_geo(GEO)
        self.assertEqual(model["source_scale"], 100)
        self.assertEqual(model["vertices"][2], [1, 1, 0])
        self.assertEqual(model["triangles"], [[[0, 0, 0], [1, 0, 1], [2, 0, 2]], [[0, 0, 0], [2, 0, 2], [3, 0, 3]]])

    def test_invalid_indices_counts_and_unsupported_features_are_rejected(self):
        for source in [GEO.replace("{3,0,3,-1,-1}", "{9,0,3,-1,-1}"), GEO.replace("numVerts 4", "numVerts 5"),
                       GEO.replace("setID 0", "setID 1"), GEO.replace("scale 100", "scale nan"),
                       GEO.replace("name \"body\"", "name \"body\"\n unsupportedFeature 1")]:
            with self.subTest(source=source[:50]), self.assertRaises(ValueError):
                read_geo(source)

    def test_material_resolution_is_local_case_insensitive_and_reports_missing_parts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tree.geo").write_text(GEO)
            (root / "tree.mtl").write_text('CIwMaterial\n{\n name "tree/bark"\n texture0 "BARK.TGA"\n}')
            records = [{"path": "tree.geo", "format": "marmalade_geo_text"},
                       {"path": "tree.mtl", "format": "marmalade_material_text"},
                       {"path": "textures/bark.tga", "format": "tga", "preview": "textures/bark.tga"}]
            models, failures = assemblies_from_records(root, records)
            self.assertFalse(failures)
            self.assertEqual(models[0]["parts"][0]["texture_source"], "textures/bark.tga")
            # An unresolved texture never becomes a fabricated material.
            models, failures = assemblies_from_records(root, records[:2])
            self.assertFalse(models)
            self.assertIn("texture missing", failures[0]["reason"])


if __name__ == "__main__":
    unittest.main()
