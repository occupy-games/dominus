# Asset pipeline

The initial implementation catalogs the local resource dump, stages selected assets without changing their bytes, and previews them in Godot. Python 3.10+ and SQLite from Python's standard library are sufficient; there are no Python package dependencies.

## Run

From the repository root:

```sh
python3 tools/assets.py inventory
python3 tools/assets.py extract
python3 tools/assets.py library
```

The inventory writes `build/assets/catalog.sqlite3` and `build/assets/inventory.json`. Each database row records source path, size, SHA-256, extension, leading bytes, detected format, category, and detection evidence. The JSON report includes duplicate groups and validated pack tables. Classification uses signatures where available; a text sample or extension-assisted TGA header is explicitly recorded as weaker evidence. Unrecognized data remains unknown.

Extraction uses `assets/selection.json` and writes to `game/assets/extracted/`, preserving source directories. Its manifest records source and destination paths, role, hash, operation, settings, and known unresolved dependencies. Every selected source hash is checked against the catalog before copying; every output hash is checked afterward. Repeating the commands produces the same manifest for the same inputs. Rerun inventory after changing source files. Extraction does not remove old files; the manifest defines the current selection.

Use `extract --all-direct` to stage all recognized image, audio, and font files. Extensionless or incorrectly named supported files receive a format-appropriate suffix. `--source`, `--catalog`, `--output`, and `--selection` override the defaults. Keep source, catalog directory, and extraction output separate. The tool refuses output paths within the source directory.

Example catalog queries:

```sh
sqlite3 build/assets/catalog.sqlite3 'SELECT format, COUNT(*) FROM assets GROUP BY format;'
sqlite3 build/assets/catalog.sqlite3 "SELECT path, size, signature FROM assets WHERE category = 'unknown' ORDER BY size DESC LIMIT 20;"
```

## Main menu and asset library

`python3 tools/assets.py library` stages all recognized media (including DDS) and
exports every catalog entry to `game/assets/library/catalog.json`. This JSON is
a read-only viewer projection of the SQLite catalog. It includes bounded text
and hex excerpts for files whose visual/audio formats are not decoded yet.
The source hash of every catalog entry is checked before export. Generated
library data and extracted assets remain local and ignored by version control.

Run the project and choose **Asset library**. Search is case-insensitive over
source paths, detected formats and reconstructed object names. Category and **Previews only** filters combine
with the search. Select an entry to inspect it; the preview is loaded on demand,
so the library does not keep every texture or audio file in memory. Images fit
the preview panel over a transparency checkerboard. Fonts show a specimen.
Audio has play/pause, stop and seek controls and never autoplays. Unsupported
formats remain visible with their source metadata and text/hex excerpts.
Use **Main menu** or Escape to return; leaving the library stops playback.

The current library contains 8,663 entries and 1,564 media resources. These
counts describe files rather than individual objects inside proprietary packs.
Meshes/animations inside unresolved containers are not visually previewed yet.
After changing source files, rerun inventory and library generation. A missing
catalog displays setup instructions in the library instead of failing startup.

The application controller (`game/application/front_end.gd`) injects the
read-only catalog adapter (`game/infrastructure/asset_catalog.gd`) into the
presentation screen. Simulation is not involved in menu/library behavior.

## Tree catalog and reconstructed objects

The catalog uses a collapsible tree. **Source files** retains the original
directory hierarchy; each filtered source file appears once under its folder.
Folder expansion is retained while filtering. Search results keep their parent
folders. **Assembled objects** groups supported geometry into multipart models;
expand each component to inspect its geometry, material and texture sources.
The **Assembled objects** category limits results to reconstructed geometry.

Library generation now also invokes `tools/geometry.py` and writes model data
under `game/assets/library/models/`. It supports the observed single-mesh,
single-surface Marmalade text `.geo` subset: positions, normals, one UV set,
triangles and triangulated quads, with index/count validation. Matching `.mtl`
files resolve local texture references case-insensitively. Only sibling stems
and a shared source-model comment establish assembly membership; unrelated
meshes are not grouped by proximity. Conversion errors are included in the
generated catalog's `assembly_failures` list.

The currently supported object is **ChristmasTree**, with four source meshes
(`storey1`, `part01`, `part02`, `shadow`), four materials and two textures.
The main mesh has 618 triangles and each remaining component has two. The
viewer preserves shared source coordinates and uses one common center/scale
fit for the entire object. Source `scale 100` is recorded; its original runtime
unit semantics are not yet established. Rendering uses the supplied normals,
UVs and textures with a generic lit, double-sided alpha-cutout material.
This text-object view uses generic source-texture lighting. Binary meshes, rigs,
clips and selected source shader logic are now recovered separately; see
[original asset conversion](ORIGINAL_ASSETS.md).

Drag in the 3D viewport to orbit, use the wheel to zoom, and choose **Rotate**
for a turntable. **Explode** offsets components for inspection and toggles back
to their original shared positions. Individual component switches control
visibility. These are presentation-only inspection transforms; they do not
change source geometry or simulation state. The catalog adapter reads model
data and textures; `presentation/library/object_preview.gd` builds the view.
The 3D-model branch also exposes recovered binary model groups. Original
followers have model/animation selectors; decoded bank audio can be auditioned.
The example world places every model whose original material was recovered.

## Godot preview and checks

Open `game/project.godot` with Godot 4.8 and run the main scene for the menu and
library. The original development viewer remains at
`res://presentation/dev/asset_lab.tscn`. It displays all staged media in one
scrolling page; use the main library for browsing the full dump efficiently.

With the Godot executable on `PATH`:

```sh
python3 -m unittest discover -s tests -v
godot --headless --path game --editor --import
godot --headless --path game --script res://tests/validate_assets.gd
godot --headless --path game --script res://tests/test_front_end.gd
godot --headless --path game --quit-after 3
```

Launch directly into the library with `godot --path game -- --library`.
Front-end integration checks exercise navigation, combined filtering, empty
searches, missing catalog guidance, image preview, audio start/stop cleanup,
source folder hierarchy, all four object meshes, part visibility, explode and
reassembly. Python tests also validate face triangulation, rejected malformed
geometry and texture dependency resolution.

On this Mac the executable is `/Applications/Godot.app/Contents/MacOS/Godot`. The locally tested version is `4.8.beta2.official.cafc17a19`. Validation checks source-copy hashes, texture decoding and dimensions, audio duration, and font resource loading. The final command smoke-tests the viewer scene. Visual appearance and audible playback still require interactive review. A restricted runner can emit Godot user-data-directory and macOS certificate-store errors; those were present during local headless runs, while the resource checks and scene startup passed.

Generated catalogs, extracted content, and Godot caches are ignored by version control. The game project is isolated beneath `game/`, so Godot does not import the entire source dump.

## Findings from the first inventory

- 8,663 files totaling 1,077,654,452 bytes, excluding nine `.DS_Store` files.
- 681 groups of identical files by SHA-256.
- 1,381 PNGs, 95 TGAs, 3 JPEGs, 78 MP3s, and 5 TrueType-signature fonts. `sprites/avatarAmy.png` has a JPEG signature; `magescript.otf` has a TrueType signature.
- The initial selection contains terrain diffuse candidates, a landscape palette, a tree imposter atlas, belief UI, a plot texture, and sculpting commentary. Names suggest roles; interpreting their UVs, palettes, and game behavior requires further work. The tree atlas companion `.png.dat` remains unresolved.
- All 42 `.pack` files fit an observed little-endian count followed by `(32-bit key, offset, size)` entries, with 8,923 entries overall. Tables pass extent and overlap checks. They are reported in `inventory.json`; payloads are not yet decoded, and keys have not been mapped to names.
- 89 files have the observed Marmalade group signature, while 190 filenames end in `.group.bin`. The remaining variants require investigation. Four text `.geo` and four `.mtl` files provide potential reference material for mesh/material conversion.
- Wwise package signatures appear in six `.pck` files. These are separate from the directly usable commentary MP3s; runtime sound effects remain to be extracted.
- 6,374 files remain unknown by the current detector, including much of the extensionless world data. Unknown does not imply unusable or encrypted.

## Current extraction status

The findings above record the initial signature inventory. Subsequent Marmalade
resource parsing recovered 3,046 binary model meshes plus four text components,
32-bone followers with original clips, 14-bone sheep, trees, tents and 612 bank
audio files. Nine model materials and one VFX geometry record remain unresolved.
All 3,041 models with recovered materials populate the categorized example plane.
See [original assets](ORIGINAL_ASSETS.md) and [example world](EXAMPLE_WORLD.md).

Remaining work: atlas metadata, full material/shader parameters, verified binary
assembly transforms, event-name routing, additional animation families and
extensionless world data. Unsupported content remains unavailable rather than
receiving replacement art.
