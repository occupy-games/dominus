# Original the original game asset conversion

All runtime artwork comes from the supplied `data/godus2_4/` files. Conversion
preserves original geometry, textures, rigs, animation transforms and audio;
there are no replacement models, music, SFX or generated illustrations. The user
explicitly requested Roboto Condensed for UI and world labels; `tools/fonts.py`
copies the supplied local TTF files and records their paths and hashes separately.
Generated output is ignored by version control.

## Rebuild

Run the inventory/media/library pipeline first, then:

```sh
python3 tools/original_assets.py
python3 tools/models.py
godot --headless --path game --editor --import
python3 tools/check_game.py
```

`tools/original_assets.py` accepts `--source`, `--output`, `--ww2ogg`,
`--codebooks` and `--revorb`. The default external converter locations are
`build/reference/ww2ogg-master/ww2ogg`, its `packed_codebooks_aoTuV_603.bin`, and
`build/reference/revorb`. Build ww2ogg from the [author's source](https://github.com/hcs64/ww2ogg).
Revorb's implementation is available in
[WolvenKit's conversion tools](https://github.com/WolvenKit/wwise-audio-tools/blob/master/src/revorb/revorb.cpp).
It needs libogg/libvorbis headers and libraries. Its stream API can be wrapped
in a CLI taking input/output paths; the checked-in wrapper is
`tools/revorb_main.cpp`. For the MacPorts libraries used locally:

```sh
c++ -std=c++11 -Ibuild/reference -I/opt/local/include -L/opt/local/lib tools/revorb_main.cpp -lvorbis -logg -o build/reference/revorb
```

These are offline converters, not game art. Keep revorb's copyright/permission
notice with its fetched source; ww2ogg's license remains in its source checkout.

## Recovered content

| Source | Recovery |
| --- | --- |
| `follower.group.bin` | Male/female meshes and textures, 32-bone skeleton, skin weights, original idle/walk/hammer-ground clips |
| `sheep.group.bin` | Both source meshes, texture, 14-bone skeleton, stand/walk/graze clips |
| `trees.group.bin` | 79 original geometry components and two textures |
| `tents.group.bin` | Four components; base, part, scaffold and shadow names verified against `GeneratedDataFiles/HouseModels.h` |
| 187 binary model-bearing groups | 3,046 decoded CIwModel meshes; one VFX record remains unsupported |
| Four text `.geo` files | Four additional Christmas-tree components with source materials/textures |
| Mac `the original gameMain.pck`, `BubbleTunes.pck` | 612 audio files; 22 IDs referenced by MusicTrack objects |

The model catalog has 3,050 recovered records: 3,041 with recovered textures and
nine unresolved materials. All usable records appear in the example world,
including LOD and seasonal variants. IDs combine source group and resource hash;
known names come from generated source tables and verified naming patterns.
Catalogs retain source SHA-256, model resource ID, material status, bounds and
converted paths. Unknown names keep their hashes.

## Observed formats and checks

The Marmalade group reader validates section/resource extents and class hashes.
The observed model variant stores float vertex positions in separate X/Y/Z
arrays, followed by duplicate remaps, normals, UVs and indexed triangles.
Source skin sets supply bone indices, weights and bone-local coordinates;
weighted rest-pose reconstruction was checked against source vertices (about
0.0008 source units RMS for the original male mesh). Animation conversion keeps
keyframe times and parent-local transforms. Runtime removes root translation
for display so simulation alone controls movement.

Observed texture records have a 27-byte header, `pitch × height` texels and a
trailing flag. Supported layouts are RGB888, RGBA8888 and the observed 16-bit
variant. The decoder preserves texels and does not recolor texture output.
Original shader parameters can still change intended appearance: the tree tint
math is ported from `shdrTree` in `shaders.group.bin`, using source palette
swatches. Complete biome mappings, all material states and all original shader
effects remain unresolved; generic source-texture lighting is not claimed as
pixel-identical the original game rendering.

Wwise package tables, DIDX/DATA and HIRC are read without changing source banks.
PCM is wrapped in WAV; Wwise Vorbis is rebuilt with ww2ogg and its original
codebooks. Revorb recomputes timing without transcoding. Merely remuxing the
zero-granule output was insufficient for short clips. Every recovered stream
loads with positive duration in Godot. The known MusicTrack references select
music. `tools/audio_events.py` resolves the original SculptLoop/Stop events and
supported follower animation cues through the bank's event/action/container
links. Exact marker times come from `VFX/Scripts/anim`; hammer-ground strikes at
0.9 seconds. The default switch branches are used. Full Wwise mixing and all
game-state switches remain unresolved. Scrubbing is silent; pause and the SFX
setting also stop animation cues.

Beautify uses the PCM loop targeted by its original Play and Stop events.
Both platform banks agree on the sound, its source gain, and the linear
500 ms and 2200 ms transitions. The game keeps one active voice while validated
brush samples arrive and lets a released voice fade. The renderer bridges
fixed-tick delivery with a short contact timeout.
[Wwise v88 parser](https://raw.githubusercontent.com/bnnm/wwiser/master/wwiser/parser/wparser.py)
[Wwise v88 property IDs](https://raw.githubusercontent.com/bnnm/wwiser/master/wwiser/parser/wdefs.py)

`tools/beautify_particles.py` follows the executable's brush registration to
`GOD_Beautify.txt` and the selected `Beautify` scene in `GodPowers.ptc`. The
manifest records three emitters, six atlas frames and 84 curves. The offline
comparison runs the original emitter loader with an in-memory byte reader and
checks the authored keys and compiled scalar tables. The portable compiler
reproduces the native two-point linear intervals, 30-point cubic intervals and
scalar unit conversions. The original evaluator agrees at 1,530 sampled
positions across the primary and secondary curves, and the 24,090 scalar values
cached by the original emitter agree byte for byte. The packed color keys use
hue in degrees and byte-valued saturation and value. The original converts each
key to RGB with x87 truncation and then interpolates its channels. All 1,503
packed colors and 69 unblended renderer lookups match the original, including
samples on both sides of the 100-percent wrap. The draw routine computes age
from remaining lifetime and uses it to index the opacity curve independently
of the optional RGB phase offset. The emitter opacity is multiplied by the
particle's opacity and by the effect opacity, which can inherit a parent
multiplier. The native draw comparisons cover 357 packed colors across the
three emitters. They include alpha-zero culling and saturation at 255.

The native scene replay loads the three child effects from the selected group
and executes their original initialization and update routines. It records
births, local positions, lifetime, size, rotation and frame for a stationary
brush. Sparkle emits on the initial update and the RainbowBlurs emitter uses all
four atlas frames during the replay. The release stops new births while existing
particles keep moving and expire on their own clocks. The replay uses in-memory
allocation and an identity callback for the uninitialized transform slot.
Godot's presentation scheduler advances the authored 30 Hz birth clock,
samples the two original rate lanes, and carries fractional births across
updates. It matches 78 native samples across integer and fractional frame
times. The check supplies the captured random state after each birth batch
until Godot can run the particle birth and motion code itself. Live brush
movement and particle drawing still need integration.

The supported multipart text reader preserves shared coordinates for the
Christmas tree. Binary building assemblies use the recovered Locator coordinates
described below. Missing transforms or behaviors are not invented. Format research included
[dade's Marmalade documentation](https://dade.readthedocs.io/en/latest/api/marmalade.html)
and the [Wwise package reader](https://github.com/bnnm/wwiser-utils/blob/master/scripts/wwise_pck_extractor.bms).
The custom model/rig readers implement the observed local the original game layout.

## Extended detail playback

`tools/models.py` also calls `tools/model_behaviors.py` to recover per-model skin
bindings, animation manifests and individually loaded clips under `models/motion/`.
Keyframes may contain either full transforms or rotation-only transforms; the
latter retain the source skeleton translations. Unused identity sentinel
transforms are checked before removal. Of 375 observed source clips, 371 decode
for detail playback. Four wolf slope clips contain nonidentity extra control
transforms with unresolved mapping, so they remain unavailable. Source hashes
and per-clip errors are retained in the motion report.

The model catalog records land/water/shore/underwater roles, construction-stage
IDs and available rank sequences. Building membership/order comes from
`GeneratedDataFiles/HouseModels.h` or matching anchored source families.

## Whole-building assembly and terrain materials

The Locator resource (`iw_hash("Locator") == 0x87748379`) begins with a variable
length uint32 range table, followed by 16-byte records `(slot, X, Z, Y)`.
Observed tables have 28, 37 or 42 types. Type 1 stores construction-part anchors;
even slots 2, 4, 6 identify part01, part02, part03. Coordinates are translated
to Godot X/Y/Z without inventing rotations. Tent part registration is checked
against the authored complete mesh to less than 0.001 source units RMS.

There are 335 recovered building assemblies. Some Weyworld chunks are already
authored in the complete mesh's coordinates; identity placement requires at
least 85% rounded vertex overlap and records that geometric evidence. Source
Locator evidence is recorded separately. All supplied usable family members
are retained. Construction reveals cumulative anchored chunks; completion
displays the original finished mesh plus nonembedded attachments, avoiding
duplicate surfaces. Part, scaffold and complete shadows follow their own stages.
Playback timing is a detail-view control, not a newly authored animation asset.

Land appearance follows the supplied the original 2.4 source video: smooth original-palette
colors, no repeating diffuse grain, original cliff AO/lighting formulas and
linear tone mapping. Sand uses palette (54,41), uplands (2,38), and pale high
land (27,42). These are reference-selected source swatches; the complete original
biome mapping is unresolved. Source `initialBalanceMobile.dat` supplies light
RGB 0.45 and ambient RGB 0.9. Water ports flow/caustic and glint calculations
from the supplied `shdrSeabed50`/`shdrSeaSimple` shaders using `OceanComposite.tga`.
The original map's bathymetry supplies coastal depth; all original shader states
remain incomplete.


## Original map and HUD

The large-map selector inventories 21 supplied stream packs. Eight supported
starts use distinct original height grids: Homeworld, Homeworld2–5, Homeworld7,
Hubworld_01 and Hubworld_02. `tools/campaign.py` resolves case-sensitive stream
names with Jenkins one-at-a-time hashes; known keys include terrain_0000
(`a3ac09e5`) and p1Start (`98fc8bcf`). Pack table bounds are checked before
decoding. Missing/zero-length terrain records represent empty chunks. Generated
map manifests preserve pack SHA-256, record keys/offsets/sizes/payload hashes,
height hashes and start-record provenance. The independently decoded Homeworld
pack is tested against the previously recovered loose height grid.

Homeworld7's packed p1Start is empty; its supplied `stream/homeworld7/p1start`
record places two followers on dry original terrain at (85,242) and (87,242).
This revision pairing is recorded explicitly. The current archive's
`homeworldver.csv` selects version 7 for Weyworld. New Homeworld7 starts use the
matching research, initial currencies, 71 chest sites, 34 temple sites, and
authored influence coordinates. Beacon completion activates the corresponding
source influence gates. The direct map start keeps the supplied dry followers
and loads the original empty Ark abode, two scripted followers and free farms
and mines from `initialworldsetup7/scripts.lua`. The Ark uses the `arkabode`
assembly from the capacity row in `balance/housevalues.csv`. Homeworld departure,
Ark passengers and the Astari portion of the setup remain to be integrated.
Homeworld6 has no supplied packed player start. Twelve large event-map packs
are inventoried but unavailable because their rules and waterlines still need
porting and validation.

The other enabled maps share the supported legacy desktop opening with
start-relative registration. Map IDs and height fingerprints persist in
simulation state. Homeworld7 saves from before Weyworld registration retain
their existing site layout and progress.

`tools/campaign.py` recovers the 64 Homeworld terrain chunks with the source
loader's Simple9, sparse and raw formats, preserving hashes and decoder-address
evidence. The original sea level is 19 and layer height is 0.3. The original
`p1Start` records place the two followers at (175,166) and (176,162). The extracted
tree/rock/gem/plot fields retain their raw values; their complete semantics are
not established. The current scenery variant interpretation is provisional.

`tools/ui_assets.py` decodes `Scaleform_Compiled/Textures.gfx` external-image,
sub-image and symbol tags. Its catalog preserves 205 named regions and hashes
for both original DDS atlases. DDS pixels are converted losslessly to PNG.
The sculpt button uses the existing source `sprites/Atlas_AutoGUI.png`: circle
region (173,755,74,74), hand region (84,1037,62,68). These are source sprite crops;
the HUD layout is implemented in Godot. This does not establish exact original
Scaleform layout or behavior parity.

`tools/current_cards.py` recovers `received/godussteamrel/balance.datz` using
the source loader's rolling XOR (byte i XOR (0x6c + 0x4d*i)) followed by gzip.
Evidence is `godus.s86:0x1017339e–0x101733c0`. Gzip CRC/size and every archive
record extent/path are checked. The archive contains 2,051 records, including
an identical duplicate utf7test.csv. Its current carddetails, stickerdetails,
localization and reward tables yield 249 distinct card/sticker records.
238 have supplied current illustrations. Legacy/debug records without current
portraits remain unavailable; the active galleries never use the old square
`Resources/Cards` fallback. Source-marked legacy/internal records are excluded
from the active galleries but retained in the provenance catalog.

Illustrations resolve the actual case-insensitive path named in the 2.4 table,
preferring `Scaleform/Resources` over the older compiled resource set. Titles
and explanation keys resolve against that archive's English localization.
Stickers use their exact named `Resources/Stickers` art, source research
contributions and source tutorial text. Quantified rewards retain the source
reward amounts, including cases where the source intentionally reuses another
quantity's illustration. Missing original prose is not invented.

Each descriptor retains original keys, source/table/row, image path and SHA-256;
the catalog retains archive and table hashes. Conversion creates small
96 × 146 maximum thumbnails from the source color crop `(0,61,256,390)` in
`OBJ_Card.as:onImageLoadComplete`; sticker pixels keep their original aspect.
The full original crop loads only for a visible detail card. On-screen cards
use the original `GFX_CardSmallBorders_01` frame. Off-screen and hidden controls
release their textures; the adapter keeps weak image references only.

The complete 2.4 catalog is independent of the currently supported legacy
simulation rules. Compatibility IDs bind existing inventory/commands to their
catalog entries. Unported original effects stay unavailable; this extraction
does not establish complete 2.4 gameplay parity.

Follower and belief counters compose the authored round-bar left cap, a
one-pixel center strip and mirrored right cap in presentation. No replacement
bitmap is generated. `GFX_Pawn_Standard` retains its 40:33 aspect ratio. The
smaller hand uses the same existing hand/circle crops with enough inner margin.
Projected badges remain visible when completed building components
are batched. A single canvas layer draws the badges from the source atlas,
avoiding a separate 3D draw call per house. The original blue `GFX_Pawn_Worker` marks building activity, and
`GFX_IWIcon_Belief` marks collectable belief. Badges outside supplied influence
circles are hidden. Original fatigue/breeder indicators are not assigned to
unimplemented fatigue or residence states.


## Progression and influence configuration

`progression_content.gd` normalizes the supplied desktop card, initial-card,
population, unlock, house, object and shrine tables. Initial-card component counts
are retained where the two source card tables disagree. Supported completions
are Spirituality, Tents/Lodge, Sculpting Upgrade, Construction and Totem Upgrade;
later effects remain unavailable. Source house values determine footprint,
capacity and timers. Whole-model family selection uses recovered mudhut and
primitive assemblies; this does not establish complete version-to-version abode
appearance parity.

The supplied tables identify themselves as `BalanceFiles_b1.6`; their legacy
Default influence anchor is (141,125), whereas the streamed Homeworld begins at
(175,166). The campaign adapter translates the legacy influence circles and
object records by that anchor difference, preserving original coordinates and
the registration offset in its rules. This is an explicit scenario registration,
not proof that the object placements match the supplied video. Entries below the
supported waterline remain unavailable; unknown fixed rewards are not replaced.
Chest-model type selection and tree/rock variant interpretation remain provisional.

Influence uses the original radii and unlock predicates. Distinct source
population thresholds advance persistent player levels; completed shrine IDs
unlock their expansion circles. Simulation validates affected cells. Presentation
uploads circle coordinates/radii as a small float parameter texture and applies
the original OutOfRange color to terrain, water and source object materials.
The texture encodes runtime geometry parameters and contains no new artwork.

The named follower chest-reaction and card-celebration events were found in
`godus.s86` and linked through the original Wwise bank. The event manifest retains
both source hashes. Full Wwise mixing, particle effects and all original power
visuals are not yet reproduced. Totem navigation is simulated; its unrecovered
beam asset remains unavailable.

`test_campaign.gd` covers the real source-map opening through Tents and region
expansion. `test_progression.gd` uses a controlled small map with original rules
to cover later material consumption, Construction, abode upgrades, shrine repair,
powers and SQLite continuation. Those controlled cases do not establish complete
original campaign parity. Native capture fixtures separately check card/chest
presentation and influence growth.

## Authored distant-tree sprites

`tools/tree_imposters.py` recovers the 5-by-12 rectangle/trim table from supplied
`sprites/pack_treeImposters_v2.png.dat`, retaining the source and atlas SHA-256.
The renderer uses the existing extracted PNG with the original
`shdrImpostersWithDiscard` R-trunk/G-foliage/alpha-coverage interpretation from
`shaders.group.bin`. Whole palm, deciduous and alpine mesh variants map to atlas
groups 0, 2 and 10 by their variant suffix and visual correspondence. The original
streamed field's packed variant interpretation is still unresolved; this is not
proof of exact original tree placement. Close views retain complete original
meshes. No replacement tree image or generated artwork is used.
