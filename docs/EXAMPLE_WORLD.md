# Large the original game example world

Choose **Example world · all the original game models** in the main menu, or launch with
`godot --path game -- --example`.

The current layout contains 3,041 usable source records on a plane approximately
2,029 × 2,073 world units. It deliberately includes high/low detail variants,
shadows, scaffolds, detached parts and seasonal variants. These are source
records, not a count of unique gameplay object types. Nine recovered meshes
with unresolved materials and one unsupported VFX record remain unavailable.

Categories are inferred from original resource-group names: Animals, Boats and
harbors, Dwellings, Effects and scene elements, Geology, Monuments and powers,
People and equipment, Props and treasures, Settlements and industry, Vegetation.
The tree preserves source groups and model names/resource hashes within them.
Every usable record has a permanent plot; none is dropped by random sampling.

## Space and inspection

The deterministic layout uses each model's actual source bounding box at a
common presentation scale of 0.003. Cells include five world units of clearance;
source groups and category regions add wider aisles. Each mesh is centered in
its own plot. Land exhibits use smooth colors from the original palette, without
diffuse grain or a repeating surface texture;
boats use water plots, harbor structures use a shoreline, and fish are submerged
under translucent water. Habitat assignments follow explicit source-group roles
rather than the broad category alone (for example, arkabode stays on land). Original vertex data is preserved. Large
scene meshes get larger plots; small props can be inspected at close zoom.

Selecting a tree node frames a category, source group or individual model.
Clicking geometry selects its source bounding box. The right panel provides an
independent orbit/zoom preview plus related base/part/scaffold/shadow records.
**Frame all these components** shows their separate plots together. Relationships
come from recovered model names; unknown hashes are not joined by guesswork.
The Christmas tree also links to its verified four-part assembly inspector.
The 335 recovered building families render complete source-coordinate assemblies
on their base-model plots. Individual source records retain their separate plots.

## Detail animation and building lifecycle

Selecting a building with verified component references automatically plays its
**Construction stages**. Membership comes from the original
`GeneratedDataFiles/HouseModels.h` table or a matching source family with recovered
`Locator` anchors. Scaffolds and cumulative construction chunks remain positioned
on one building throughout playback; the building does not recenter between
stages. The final stage uses the authored complete mesh and retains attachments
whose geometry is not already embedded in it. Embedded chunks are hidden at
completion to avoid duplicate surfaces. Shadow components follow their own stages.
**Rank progression** is a separate sequence where matching ranks exist.

Offsets are decoded from original `Locator` part slots. Some Weyworld chunks
are already in building coordinates; zero translation is accepted only after
at least 85% of their rounded vertex positions match the complete source mesh.
Each component records its placement evidence. Missing transforms remain
unavailable. Preview timing defaults to 1.5 seconds per stage, adjustable through
playback speed; this is not a recovered authored building animation or game timing.
The **Selected component** track still exposes a component mesh by itself.

## Terrain appearance

The supplied the original 2.4 source video was checked at 0:20, 0:45 and 1:53. Land uses
untextured warm sand and muted yellow-green source swatches, with soft cliff
shading derived from the original terrain shader. No landscape grain is applied.
Color conversion follows the renderer's output space and the views use linear
tone mapping. The complete original biome/palette mapping remains unresolved.

Water uses the original `OceanComposite.tga` flow/caustic and glint channels,
with source shader formulas ported from `shdrSeabed50` and `shdrSeaSimple`.
Full original sea depth, coastal topology and shader-state mappings are still
incomplete; the current rendering is not claimed pixel-identical to the original game.

Other skinned units expose their recovered original clip names in the detail
selector. There are 371 playable source clips: followers (323), sheep (15), wolves
(9), boats (6), rafts (4), window followers (4), chests (3), ark/slipway/treefruit
(two each), and cards (1). Seasonal skins reuse follower clips only when the
source skeleton is identical. Low-detail seasonal rigs and the pigeon have no
compatible recovered clip list. Four additional wolf slope clips have an
unresolved extra control transform and appear disabled with the decoding reason.

The player supports play/pause, restart, loop on/off, ¼× through 2× speed and
scrubbing. Animation is isolated to the detail view; it cannot change exhibit
positions or simulation state. Source root travel is removed to keep the unit
in view. Both the example world and asset-library model details use this player.
Objects without recovered motion or stages explicitly say so.

## Camera

- Wheel or pinch: zoom; the range is 0.2 units through a full-world overview.
- RMB drag: orbit/yaw and pitch.
- MMB or Shift+RMB drag: pan in the base plane.
- WASD/arrows: move in camera-relative tangent directions; Shift accelerates.
- F: frame selected; Home: overview; H: hide/show panels; Escape: close/back.

Pan preserves the camera's height offset from the base; it does not climb
terrain. Framing a tall object may set a new inspection height. The camera uses
`frame_at(uv)` and `coordinates(point)` from a surface provider. Only the plane
provider is implemented; sphere/torus providers need their own coordinate and
surface-intersection behavior before they can be enabled.

## Loading and validation

The complete manifest and navigator are available immediately. Original meshes
load around the camera, at most eight or six milliseconds of mesh work per
frame. Distant nodes are released; there are no invented proxy models. Overview
loads all exhibits progressively, so visiting a category or searching is faster
than waiting for the complete far view. On this Mac, a native render verified
all 3,041 model nodes; the full overview populated in about 11 seconds. This is
an observed capture time, not a target frame rate or startup requirement.

`tools/check_game.py` verifies every usable mesh and texture, full layout
coverage, unique placement, non-overlap with inspection clearance, category
filtering, component selection, library return, close/wide zoom, orbit and
constant-height pan, including a tilted base plane. Screenshots are generated
under `build/screenshots/`. The example layout is deterministic and regenerated
from the catalog; gameplay placements and simulation state use SQLite saves.

The playback suite also instantiates and samples every one of the 371 supported
clips on its source rig, instantiates all 335 building assemblies, verifies source
offsets and cumulative construction visibility, and checks pause, endpoints,
lifecycle scrubbing, rank sequences and matching world/detail habitats.
