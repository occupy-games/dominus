# Authored Homeworld6 opening

`python3 -m tools.campaign_scenarios` decodes the supplied current balance
archive. It parses the original Lua to inert expressions and callback bodies;
it never evaluates Lua or arbitrary Python expressions. The original stream
decoder recovers the complete Homeworld6 terrain, tree and rock fields. Source
archive, individual files, pack, fields and decoder records retain SHA-256
provenance in the generated manifests.

Homeworld6's empty packed `p1Start` is intentional. Its `onPreLoad` clears map
starts, while the global sculpt tutorial and scoped respawn hook explicitly
spawn the pair at `(162.7,53.2)` and `(163.3,52.8)`. The authored starts are in
the water at raw terrain level 19. They must not be replaced by dry starts
inferred from a camera or influence circle.

The recovered data includes 14 ordered `BLOCKAGES` targets, original callback
closures, source constants, tutorial localization/positions and the scoped CSV
tables. The original reactions table provides the restored tutorial movement
multiplier; the race table supplies the base follower speed. The global sculpt
failure hook identifies the coastal free-sculpt band.

## Implemented portion

Choose **Campaigns → Homeworld6** in the main menu. The selection screen shows
the current playable endpoint. The same opening can be launched from the
project root with

```
/Applications/Godot.app/Contents/MacOS/Godot --path game -- --homeworld6-opening
```

This entry uses a separate save. The played sequence reaches ten followers,
presents the original New Age Shelters card and opens its first source chest.
The chest awards the Tools sticker needed by that card. Open the Timeline from
the top-left button, acknowledge its original explanations, drag Tools onto New
Age Shelters, then close the Timeline. Release Builders onto reachable flat
plots to build Beach Huts. The original next milestone awards Restore Ruins
at 16 followers. Open that card, dismiss its explanation and release Builders
near the first Shrine of Expansion. They prioritize the reachable repair over
nearby house plots. After repair, click the Beacon card to activate its original
influence areas. More reachable plots support the next population milestone,
Power of Prayer at 24 followers. Open and close that card, then click the
belief markers on the Beach Huts. Acknowledge the belief counter explanation
and drag an upper grass layer. Build toward the Pit of Doom and release a
Builder from a nearby house once the site is inside your influence. Click the
card above the repaired Pit, then close its explanation. At 50 followers, open
and close the Leashing card to enter the original tutorial map. Click and hold
the indicated follower, drag to the plot and release. Then hold on the house
and drag an occupant to the same building site. In the group lesson, hold
over each of the four followers in turn and release over the shrine. The
completion message returns you to Homeworld. Hold on a free follower or a
house with a releasable Builder and drag to an empty plot to build there, or
onto an unfinished abode to fill an open Builder slot. Use the same gesture
to send Builders to the Dock. The Dock becomes
actionable once the Pit's influence area has expanded. Claim the Voyages card
after repairs, then select the Dock and press GO to sail to the first island.
You can also leash followers into the repaired Pit of Doom. The Pit awards
gems after the pending sacrifices finish and their original payout delay has
elapsed. Each sacrifice reduces happiness and slows births in the follower's
ordinary abode. Select the Pit to see its totals.
Victory returns you to Homeworld with the original Farming prompt and opens
voyage selection from the Dock. Excavate buried sticker chests and complete
the Wooden Lodge cards with compatible stickers to build at higher elevations.
Release nearby Builders or leash them to later Beacons of Expansion, then
claim the card over each repaired site to expand the original influence areas.
At 165 followers, open and dismiss the Farming card. Collect 3,000 belief and
select the Farming Settlement power. Drag the placement ring over completed
homes, then press Preview and Squish it! Click the settlement to release a
Farmer, or leash a Farmer to a valid plot within its radius. Click the field's
marker when the wheat is ready. Start two fields to reveal Super Fast Building.
Claim the card and follow its prompts to collect wheat from the fields near the
settlement and the original terraced fields. Once the lesson ends, place a
Farming Settlement near those terraces and release Farmers to work reachable
fields again. Builders need wheat for ordinary abodes outside settlements once
the card is active, and the source build-time modifier applies to new
construction.
The main menu's Continue action selects the more recently modified standard or
Homeworld6 opening save after restarting the application.

`campaign_opening_content.gd` loads the source map independently of the older
opening and injects its authored influence coordinates without translating
the older map's objects. `campaign_opening.gd` owns rescue state, protected
followers, fixed-tick delays, acknowledgement commands, source callback execution,
scheduled callbacks and the current trail target. The existing bounded pure
interpreter executes the recovered arrival/obstacle closures.

The original fractional positions remain unchanged while the followers drown.
An ordinary validated coastal layer drag extends real terrain beneath them;
it does not teleport them to shore. The six-second rescue embrace precedes
worship and its original continuation message. Navigation approaches reachable
obstacles and stops at cliffs rather than stopping at the beginning of the path.
An immutable definition and sea-floor field are shared by snapshots, while
messages, closures, callback flags and schedules are detached mutable state.
SQLite continuation normalizes integral identity fields to preserve follower
membership and movement after loading.

The recovered camera helpers now execute their actual source bodies through the
bounded interpreter, including numeric loops, loop breaks, method receivers and
local multiple-return bindings. Presentation submits an eight-number orthographic
projection and a movement-end command. Simulation performs the source screen-margin
tests, maintains each follower's checkpoint history, polls arrivals every second,
pauses the early journey when both followers leave the view, and resumes when
camera movement brings either back. Catch-up only uses the original already-passed,
dry, offscreen checkpoint while the trailing follower is also offscreen. It cannot
teleport a visible follower or teleport to water. Source scrolling messages,
localized follower hints, one-second camera unlock and persistence survive saves.
Headless self-play has an explicit all-seeing observer until supplied camera
commands select a finite view. Camera and zoom input respect the source locks.
The original leading-follower blocked hook and post-sculpt hook also execute
their source bodies. Unblocking waits 0.2 seconds and requires a complete path;
merely finding another reachable approach to an obstacle does not clear it.

The final checkpoint enters the separate original `TrailStep02_FirstArrived`.
Its source code regathers the pair, selects the trailing follower and polls its
arrival every half second. It waits for that follower to reach `y >= 119` when
the path is valid. An invalid path uses the distinct, explicitly authored final
target repair; this is separate from the camera's offscreen catch-up rules.
The stage locks the camera and new terrain edits. Saves retain that pending loop.

The following arrival callback also runs its source body: it unlocks plot claims,
emits the original rainbow, god-ray, six bird and sound references, requests the
source camera, stops the two long effects after ten seconds, clears the arrival
message after twelve seconds and hands off after the ten-second cheer interval.
Particle rendering and the missing audio-event media remain unavailable; emitting
the original references does not establish visual or audio parity.

`tools/day_cycle.py` recovers the native `Midday`, `Sunset` and `Midnight` routines from their
Lua registration entries and validates their actual x87 arithmetic. The manifest
retains the executable hash, routine bytes, addresses and config initializers.
The supplied current configuration gives midday 480, sunset 960, midnight 1080 and a 1200-second
cycle, rather than guessed fractions of a day. `simulation/day_cycle.gd` advances
those injected values at fixed ticks; the original scheduled sunset callback
freezes the clock. This does not yet apply the original time-dependent lighting
to the renderer or implement all native day-cycle consumers.

Promised Land's arrival and first rock-removal steps now execute their original
callbacks. The first explanation waits seven seconds, its acknowledgement shows
the separate rock explanation, and the next acknowledgement enables exactly the
authored first rock through the source activity-lock exception. The explanation
anchors to that object's logical position. Source groups have separate message
IDs, so Promised Land's message 2 cannot accidentally acknowledge Trail message 2.
`tools/map_objects.py` separately recovers the authored rock from
`initialworldsetup6/initialmapobjects.csv`. Its CSV origin is `(160,122)`;
the native loader adds half its two-by-two dimensions to obtain `(161,123)`.
The loader's name-slot and enum conversion identify `rock1` as object type 25.
Both native model dispatch tables map that type to model enum 352 (`boulder6`),
with shadow enum 359. The decoder retains those registration/dispatch bytes,
position/footprint routines and executable/table hashes. Source rock types with
missing values or model dispatch stay unavailable. Packed field byte 157 at the
same center is not the authored object's type or model selection.

Simulation resolves every occupied cell to this one stable rock identity. Its
whole footprint obstructs plots, and a clearing command removes the object once
and persists all four occupied cells in the clearing mask. Nearby packed scenery
outside that footprint remains separate. Detached render descriptors carry the
source center, dimensions, model name and current visibility; presentation neither
imports simulation rules nor chooses object types. The source boulder meshes now
load through the shared content adapter, including independent campaign previews.
The current `balance/config.csv` override supplies one clearing tap, overriding
the general config's two taps. Removal persists through the existing rock mask,
clears the source UI/action/exception and does not trigger the older map's first
card or belief reward. The midnight callback and explanation closure survive
SQLite reload. Action-hand requests, attached reaction identity and the requested
tree-regeneration flag are retained; rendering that hand, executing the full
`LiftFail` follower action and tree regeneration remain unported.

`python3 -m tools.house_values` recovers the native house column registration and
inheritance multiplication stage at `0x1002bfd0`. It preserves instruction bytes,
addresses and source hashes for 53 multiplied fields, then resolves the 62 supplied
house rows using the native integer/float32 arithmetic. The first tent's inherited
capacity is 2, base size 4, build time 7.5 seconds and vision radius 12. Its resolved
values and provenance are injected into this private campaign independently of the
older shelter data. This is not yet a complete runtime abode implementation:
native columns absent from the current CSV and unsupported literals such as its
`d` remain explicitly unresolved. Existing-plot maintenance/claims, builder
assignment and house occupancy still need their source behavior registered
before first-house construction can be enabled. The native cooperative work
arithmetic is now separately recovered in `simulation/construction_work.gd` and
compared against twelve original CPU cases. See `docs/CAMPAIGN_ECONOMY.md` for
the current campaign adapter and its remaining reaction/membership boundaries.

`simulation/source_plots.gd` now ports the original flat/clear square-capacity
fields (`0x1025e210` and `0x1025e5e0`). A size-N footprint needs N-by-N
unobstructed quads and (N+1)-by-(N+1) equal dry terrain vertices. The native
maximum is 16. `World.source_plot_capacity` queries the current terrain and
tree/rock/building occupancy without changing authoritative state. This is a
capacity query; allocation, cell eligibility, claims and building work are
separate decisions.

The optional offline `tools.native_plot_oracle` executes those actual x86
routines against the shipped source terrain and compact scenery. Its checked-in
fixture captures 4,096 coordinates in each of three controlled states: initial,
the authored first rock removed, and that removal plus raw vertex `(161,120)`
raised from 19 to 20. The pure simulation matches all 12,288 samples. In these
inputs, rock removal leaves capacity 3 at `(159,121)`; it does not automatically
produce the tent's size-4 footprint. The edited vertex makes capacity 4 at
`(158,120)`. These are controlled geometric comparisons, not a complete native
tutorial playthrough or proof of the eventual first allocated plot.

`source_plots.new_region` also ports the native fresh-allocation phase
(`0x102397f5`) for one dirty region with no existing plots. It tries larger
sizes first, then rows and columns, reserves every quad of an accepted plot,
and preserves integer half-size height-band queries. The original pool's
1,024-plot limit applies. `tools.native_plot_allocation_oracle` executes the
actual scan, native cell predicates, pool allocation and footprint reservation;
ordered cell storage and spatial registration are explicit adapters. Nine
controlled captures exercise source terrain/scenery, a sculpted vertex,
plot-rotation byte boundaries, mixed sizes and a different height band.
They use a clipped loaded/influence domain inside the starting influence circle,
not the original full AOI raster. Initial scenery occupancy is held fixed during
controlled terrain edits. Beauty, existing plots, claims, spatial-search order
and runtime scenery regeneration are outside these captures. In the sculpted
case the scan allocates origin `(158,120)`, size 4, center `(160,122)`, radius 2;
clearing alone still allocates no tent in that clipped domain.

`source_biomes.gd` ports native biome scheme/type lookup and height bands.
Selection uses the greatest positive outer-radius-minus-distance, preserves
earlier ties, and excludes the exact outer boundary. Current source indices
map schemes 17/19/18 to biome types 1/2/3; altitude boundaries are 25 and 36.
The original inner radius is not part of this predicate. All 704 captured
Homeworld6/Weyworld7 samples match. Infrastructure injects the source biome rows
and current configuration as plain private-campaign data, validated on restore.

The private campaign now maintains those plots against its actual terrain,
scenery, availability, biome and quantized influence fields. Plot lifetimes run
before dirty maintenance, and authored influence advances afterward, matching
the native gameplay tick order. Terrain edits and scenery clearing mark the
registry; influence changes feed its pending dirty regions. Existing plot
maintenance does not acquire an additional AOI gate. Only fresh scans with no
possible origin in the authoritative influence tiles are skipped.

`tools.plot_field` losslessly extracts Homeworld6's original 1,048,576 rotation
bytes. They are all zero, stored as a default with no overrides and validated
against the original pack and byte-field hashes. At positive dry plot heights
this byte cannot satisfy the native blight-height interval, so the campaign
adapter is restricted to that verified field. Other fields remain unavailable
until their blight state is ported.

`test_campaign_plots.gd` plays the real rescue and trail, prepares the coastal
corner through an accepted drag, acknowledges arrival messages and removes the
original rock. The resulting first plot is `(158,120)`, size 4, as in the native
geometry/allocation capture. A second played test without that drag produces no
first plot after clearing. SQLite preserves appearing and disappearing plot
timing, ownership and free-list order. Live influence shrink checks existing
plot retention; an explicitly controlled damage checkpoint checks interior
repair and delayed slot release. These integration checks do not establish a
full native global plot trace, follower claims or first-abode construction.

`tools.house_selection` recovers native column offsets, the actual location and
biome enumeration initializers, and the farm/mine model classifications into
`house-selection.json`, with source and instruction provenance. Pure
`source_houses.gd` ports the original selector (`0x100b72c0`) and the allocator's
availability phase (`0x102377f0`). Building choice takes the largest eligible
footprint, then greatest source order, preserving earlier equal-order ties.
Unlocks, altitude, optional biome locking and production type are independent
filters. Farms/mines contribute available biomes, but not abode plot sizes.
Homeworld6 does not enable `HousesBiomeLocked`; Weyworld7 does. The source
`PlotsAppearClaim` script key now reaches its dependent `PlotsAppear` condition.
Private world queries expose detached building choices and plot limits without
creating houses or overriding the unavailable tutorial handoff.

The optional `tools.native_house_selection_oracle` executes the actual selector,
production filters, biome conversion and availability scan with explicitly
injected resolved rows and unlock memberships. All 4,608 cases and eight size/
biome availability profiles match the pure port. This does not prove a complete
native CSV loader, actual plot claims, follower assignment or house occupancy.
The Godot check additionally verifies the tutorial unlock connection, detached
queries, save continuation and malformed saved-row rejection. Reproduce with:

```
PYTHONPATH=build/research-tools python3 -m tools.native_plot_allocation_oracle
python3 -m tools.house_selection
PYTHONPATH=build/research-tools python3 -m tools.native_house_selection_oracle
```

`source_terrain.gd` ports the original default discrete four-corner query
(`0x1025b8f0`), including strict corner-diamond boundaries and the central
three-corner median. It does not use nearest-vertex rounding or bilinear heights.
The raw vertex adapter combines current dry terrain, saved submerged sculpt
levels and the immutable authored sea floor without copying the map.
`GetStepAtPoint` in the private source interpreter now uses this query with the
original Lua wrapper's float32 height-scale/division boundaries, preserving
fractional coordinates. Native samples include the observable 29.0000019 step
result and truncation of negative fractions at the map edge.

`tools.native_terrain_sample_oracle` executes the actual sampler, height wrapper
and registered Lua callback with raw-grid and Lua-value adapters only. All
30,976 corner cases, 192 source points and 14 edge queries match the pure port;
192 Lua callback captures also match exactly. The headless check covers detached
queries, edited submerged/dry vertices and SQLite persistence. This is the
default discrete query, not the separate continuous geometry query, active-sculpt
override query, full scenery regeneration or rock-motion queuing.
Reproduce its fixture with:

```
PYTHONPATH=build/research-tools python3 -m tools.native_terrain_sample_oracle
```

Native plot registration (`0x10239abe`) uses half the plot size as its spatial
radius. `GetFirstPlotInRadius` requests inclusion of that radius, so its search
must not be replaced by center-distance-only lookup. Six captured comparisons
exercise the original circle predicate (`0x1012d990`), including exact tangency.
Reproduce the fixture with the isolated optional emulator described below:

```
PYTHONPATH=build/research-tools python3 -m tools.native_plot_oracle \
  --fixture game/tests/fixtures/source_plot_masks.json
```

Homeworld6 now loads initial placements recovered from the actual native
generation kernel at `0x1025fcd0`, rather than expanding density bytes into
objects. The original initialization call site loads authored CSV objects first,
then generates the complete `0..1024` rectangle. The bounded offline oracle runs
that loader, coordinate hashes (`0x10276500`/`0x10276550`), original four-corner
terrain sampler, biome/type selection and footprint registration. In-memory
adapters provide the supplied terrain/densities/table values and object storage;
locks, diagnostic logging, scene/event registration and dirty-region notification
have no device side effects. The original executable entry point is never run.
The explicit environment and adapter addresses remain in the manifest.

Current balance overrides `loc2Start=25` and `loc3Start=36` are applied before
capture. This produces 2,937 trees and 1,266 rocks, including all 42 authored
objects (41 Godseed trees and the first rock), with 8,001 non-overlapping occupied
cells. A complete default-band comparison produced the same positions/footprints,
with 937 tree classifications changed by those current overrides. Separate
opening-region runs with all cells loaded and with mathematically zero-density
cells skipped produced identical 102-object results. The call harness invalidates
its translated immediate arguments between calls; distinct probe calls verify it
does not reuse stale coordinates.

`homeworld6-scenery.bin` stores the 4,203 records in 117,696 bytes. Its manifest
retains input hashes, original native instruction bytes and all 27 source model
dispatches, dimensions and belief values. Infrastructure validates those hashes
against the story/map and injects plain initial records. Simulation owns the
occupancy index and clearing masks. Static descriptors/index tables remain shared
immutable data; a small cached visibility mask is duplicated for presentation.
Fractional transforms survive SQLite, and sampled dry coastal trees are retained
even when their integer root cell is water. Godseed models resolve their separate
original package. Missing source imposter mappings keep the original mesh.

This recovers initial placement under the documented oracle adapters; it does
not prove complete original runtime or device execution. Runtime regeneration,
tree growth/height transitions after sculpting, original shadows/materials and
all source object interactions still need ports. The older selectable campaigns
retain their previous provisional density expansion. The first-house handoff
remains unavailable until actual source plot/construction rules are ported;
an assumed four-by-four square is not substituted for the unresolved footprint.

The source rock anchor-height visibility shortcut has been replaced by pure
`source_rock_motion.gd`. Native dirty-scenery refresh (`0x10260e90`) samples the
object's actual fractional position and queues changed rock heights in a pool
of at most 12 motions. The update at `0x1015da0e..0x1015db18` advances elapsed
float32 time, resamples the current target and linearly combines it with the
saved start height. Completion uses a strict greater-than duration comparison.
Original configuration registration identifies `TreeRockRaiseAnimationTime`
at `0x105da89c`, with a one-second executable default and no current CSV override.
`tools.rock_motion` retains its source hashes, registration and instruction bytes
in `rock-motion.json`; infrastructure injects only plain duration/sea-height/limit
values. Original pool overflow reuses slot zero in place, rather than adding a
thirteenth motion; the previous object's last height remains unchanged.

Validated terrain edits dirty the 32-cell regions containing their affected
quads. Simulation scans the source object footprint index in native tile/row/
column order, retains rock identities and occupancy when the ground changes,
and owns current heights, slot/free-list ordering and elapsed time. Clearing
cancels an active transition. Mutable motion data survives SQLite independently
of the shared immutable object descriptors. Old private definitions without
motion configuration retain their prior compatibility behavior.

Presentation caches each rock's source transform and updates only the affected
MultiMesh instances, interpolating between fixed snapshots. Rock movement does
not rebuild the source scenery tile; entering a tile uses the current saved
height immediately. Transform caches avoid GPU readbacks and retain rotation
and scale. The headless check verifies ownership, interpolation and batch reuse;
its conditional native-renderer check verifies the actual instance transform.

`tools.native_rock_motion_oracle` executes the actual rock-only dirty scan, pool
operations and timed update with explicit controlled terrain/object inputs.
Eight captures cover unchanged/raised/lowered ground, exact duration, retargeting,
moving targets, overflow and a four-tile seam. This is not a full original world
update: trees, regeneration, scene registration and other entity pools are absent.
`test_rock_motion.gd` compares every captured queue/height state and exercises a
normal sculpt command, immutable snapshots, in-flight SQLite continuation and
original mesh-batch updates. Reproduce the configuration and captures with:

```
python3 -m tools.rock_motion
PYTHONPATH=build/research-tools python3 -m tools.native_rock_motion_oracle
```

The initial-tree terrain response now preserves planted Y and native
activation/plot occupancy, with the original scale curve in presentation;
see `docs/CAMPAIGN_ECONOMY.md`. Runtime density regeneration and planted growth
records remain separate work.

`source_existing_plots.gd` additionally ports the original existing-plot cell
predicate (`0x102363c0`) and full/interior ownership checks (`0x10236510` and
`0x10236610`). A free or unclaimed neighboring cell can pass the cell predicate,
but cannot count as this plot's owned footprint. Another claimed plot blocks
absorption. Original flat/scenery/building masks, plot-origin rotation/biome
gates and candidate-cell blight gates remain distinct inputs. The native height
conversion truncates float32 absolute height divided by its original double
scale; absolute height 6.0 therefore tests raw levels 19 through 21 for blight.
`native_existing_plot_oracle.py` executes all three actual routines, their
ownership-tree searches and the original blight predicate for 456 controlled
cases. This supplies the validation predicates for the pending resize/merge
phase; it does not enable claims, invent a first tent plot or complete the
unavailable first-abode handoff.

`source_plot_resize.gd` now implements one existing-plot layout iteration over
those predicates, including source expansion order, repair movements, claimed
plot preservation, minimum-size removal, footprint ownership updates and ordered
neighbor revisits. `native_plot_resize_decisions.py` exhausts the original branch
kernels: 768 growth inputs (eight flags and three available-size regimes) and
4,096 repair inputs (twelve flags). Their resulting source rules occupy 4,864
bytes, validated by hash in infrastructure and injected as immutable plain data.
No emulator runs in the game. The rest of the source decisions, including cell
predicates, remain executable simulation code.

The independent `native_plot_resize_oracle.py` runs the complete original
single-plot maintenance iteration, not just those branch kernels. Sixty-four
captures compare layout, ownership and revisit order after flatness/scenery/
building changes, claimed plots, size limits and neighboring plots. Original
predicate, geometry-choice and footprint-registration loops execute; only map
node allocation/erasure and presentation/diagnostic services are adapted. These
controlled single-iteration cases do not verify the original global dirty scan/revisit scheduler,
full AOI initialization, all neighbor arrangements or follower claim assignment.
The private first-abode handoff remains unavailable until those stages connect.

`source_plot_registry.gd` composes those rules into the full enabled region body:
it collects origins strictly inside the source 64-cell window, drains the native
LIFO revisit queue to stability, then allocates fresh plots around remaining
ownership. Its 1,024-slot pool retains removed plots until their float32
transition reaches one, releases them on the following update, and preserves the
source free-list order. The original rate is recovered from `0x104ec570` and
injected through the existing rule adapter. Stored origins/sizes update on the
same later tick. Local capacity caching changes neither field values nor layout.

`native_plot_registry_oracle.py` executes the complete original region loop and
pool/lifetime routines for eighteen controlled cases: empty regions, growth,
repair, claimed neighbors, overlapping windows, exact window boundaries and
released-slot reuse. It retains the original footprint loops and ordered pool
instructions; only ordered-map storage and presentation services are adapted.
`test_plot_registry.gd` compares every captured state and checks detached
snapshots, in-flight save-codec restoration, deterministic continuation and
malformed ownership/pool/progress rejection.

`source_plot_schedule.gd` ports the adjacent 3-by-3 dirty neighborhood, full
invalidation when available sizes or biome masks change, and row-major dispatch.
`native_plot_schedule_oracle.py` captures 49 map-edge/interior neighborhoods and
eight availability/dispatch scenarios from original instructions. The scheduler
capture observes the region body boundary; the registry capture independently
executes that body. Neither uses a runtime emulator. These modules are not yet
connected to the private campaign's still-unported native AOI field or follower
claim assignment. They do not enable the unavailable first-abode handoff, model
the source mode that clears all plots, or establish a complete campaign run.

`source_influence.gd` now ports the original registered-circle raster kernel
(`0x100d0a10`), its byte storage and the construction/power predicate
(`0x10257570`). The native fields sample cell centers with a two-unit feather,
quantize to bytes scaled by 128, and compare against the current source clickable
threshold. Construction requires normal influence at/above the threshold and
power-only influence at/below it; powers accept the maximum of both fields.
The source non-maximum update clears the entire bounded rectangle. Repeated
circle identities skip unchanged geometry unless forced. uint64 identities
persist as decimal strings to avoid JSON rounding, while field tiles persist as
plain arrays and restore to packed bytes.

`native_influence_oracle.py` executes the original circle registry, raster,
Morton lookup, quantizing writer and eligibility predicate. Only heap allocation
and zeroing are storage adapters. Seventeen scenarios compare 191,000 captured
field bytes, including fractional/nonbinary positions, overlaps, map edges,
power-only circles, clears, forced/cached identities and actual Homeworld initial
area rows; 49 separate native captures verify threshold boundaries. The headless
test also compares the private campaign's current power/action queries against
13,500 original initial-area raster cells, preserves immutable injected constants
and validates detached fields and save-codec continuation.

`source_influence_areas.gd` now ports the authored-area portion of the original
`0x1025ab20` update with the actual raster kernel. Original DesktopHigh has
`influenceExpand=1`: radius fractions grow by half the supplied fixed delta,
rounding at the native float32 boundaries. The controller retains current radii
and one-way power-only conversion, honors unlock/explicit-activation inputs,
clears fields on rebuild, marks the original 16-cell dirty sampling grid, and
emits `influencechanged` once after a changing pass becomes stable. It preserves
the original cumulative dirty flag and the conversion branch's separate writes.

The independent `native_influence_area_oracle.py` executes the original full
controller with empty house/dynamic pools. Twelve scenarios compare every radius,
power-only flag, dirty region, callback and 135,360 field bytes. They cover
desktop/instant expansion, unlocks, explicit activation, conversion, relocking,
rebuilds, overlapping/fractional/off-map circles and the actual Homeworld rows.
Unlock membership, fixed delta, heap storage and presentation/debug services are
explicit adapters; the controller, raster, native hardware getter and plot dirty
marking execute original instructions.

The private campaign now advances this state at fixed ticks, derives displayed
area radii from it and uses the actual byte fields for action/construction
queries. SQLite checks save in mid-expansion and compare continued state and
callback order; malformed state rejects before replacing the world. Live area
value changes use a zero-delta forced rebuild, preventing stale permissions when
a radius shrinks. The actual rescue/trail and first-rock tests still pass; the
UI test now waits the original initial expansion before its rescue drag.

Dynamic building influence, global Lua consumers of `influencechanged`, explicit
shrine activation routing and follower claim assignment remain
unported. The controller emits a detached callback intent; it does not invent the
later tutorial effects. The first-abode handoff remains unavailable.

Presentation loads the original drowning, paired give/take embrace, worship and
scared clips against the verified shared skeleton. Source tooltip art and
localized text display the active instructions; acknowledgement forwards a
command. Passive hints permit the terrain drags they explain. The paired poses
face each other. No replacement meshes, animation or sound are generated.
The rescue emits its original sound-event name, but the corresponding media
mapping is not recovered in the current audio-event manifest and remains silent.

The pure temple pre-work frame now composes actual obstruction scanning with
worker-presence response, passive repair, forced decay, cooldown and source
elevation targeting. Its further composition with the original work/completion
block is checked against contiguous native instructions, including a completion
sound using the height after the same tick's rise. These comparisons cover 276
frame cases, 99 composed repair cases and 144 continuation steps, with saves at
each sequence boundary. The separately ported affiliation pass now preserves
strict deadlines, clock/RNG ordering, overlapping settlement order and the two
source containment predicates, with 191 geometry cases, 101 affiliation cases
and 64 continuation steps. `source_temple_lifecycle.gd` now composes affiliation,
terrain/elevation and repair/completion against the contiguous original
`0x10140c0f`–`0x101414d8` block. A further 176 cases and 128 continuation steps
cover both timer branches, forced decay, overlapping settlement order, same-tick
modifier changes, completion and saved continuation. The shared native type and
state slots remain single authoritative facts; invalid later inputs reject
before modifier, clock or random callbacks. Source spatial services, active-pool
ownership, deferred reward composition, spatial index, downward motion service,
final removal owner and follower job integration still precede enabling this
lifecycle in the authored campaign.

The upgrade-mask refresh is now pure simulation as well. Infrastructure supplies
the eight original `templeupgrades.csv` rows in source order, with their unlock
IDs and parsed family labels. The port preserves separate 64-bit follower and
house masks, global per-family bit positions and the first empty-to-active
spatial invalidation. Ninety cases and 48 saved steps execute original refresh,
popcount and unlock lookup instructions. A further 174 cases and 128 saved steps
execute that actual helper inside the contiguous affiliation/terrain/work block.
`source_temple_effects.gd` now resolves the effect expressions against explicit
base rows and current actor/site positions. The original parser `0x10171610`
confirms eight source expressions and five operation-prefix cases. Its field
offsets come from native column registration: race StaminaDecay uses word 21,
job StaminaDecay word 10 and housing Capacity word 16, independently of CSV order.
Eight comparisons cover the original inherited-center/radius helper. Another
179 cases execute actual follower mask collection (`0x100340d0`), race/job
getters (`0x100342a0`, `0x100343b0`), housing collection (`0x100b6d60`) and the
housing getter's shrine effects (`0x100b7580`), including actual containment and
upgrade refresh. They preserve additive/multiplicative row order, both mask
words, overlap deduplication and the abode/monastery/farm/mine filters. All six
monastery class comparisons run. The family shrine's ordinary-house bonus is
one capacity slot; the other recovered row is not an unconditional extra two.
Raw source words preserve copied hashes/flags and exact float32 stores. Saved
input checks and 48 moving-actor steps verify these detached queries. Resolved
base rows and unrelated global modifiers remain explicit inputs/adapters; the
queries do not create actors or advance jobs.
The bulk follower update (`0x1006d050`) now lives in
`source_temple_propagation.gd`. It clears only active followers' attached stat
records, preserves permanent masks and unreferenced records, queries only
nonempty shrine masks and processes the returned candidate list in source order.
The request retains the shrine's own center/radius; containment can separately
inherit its settlement's sphere. Null entries and followers without attached
stats still release their temporary candidate nodes. Repeated candidates OR
their bits; shared stat records remain shared. Seventy-five native cases and
64 moving-follower steps compare actual source traversal, clearing, containment,
OR writes and temporary-node release. Saves restore authoritative masks and the
explicit candidate service's continuation. Actual race/job getters read the
resulting stored masks, without a single-actor rescan substituting for the bulk
pass. Source spatial lookup and candidate allocation remain adapters.

The original house callback (`0x100b6e10`) now refreshes the stored house mask
before notifying geometry. An attached reference suppresses only the geometry
callback, not mask refresh; unchanged masks still notify when no reference is
attached. Another 118 native cases and 32 moving-house steps execute the actual
wrapper, containment, callback gate and shrine housing-stat getter, including
saved continuation. The pure stat consumers `follower_from_mask` and
`house_from_mask` return detached rows without mutating authoritative masks.
The geometry callback's foundation scan (`0x1003b690`) now lives in
`source_building_foundation.gd`. It counts raw terrain samples differing from
the building's stored integer anchor in either direction. It preserves inclusive
half-up bounds, the quarter-unit inset, strict original tolerance and float32
anchor/difference stores. The counter resets before terrain-override lookup;
successful overrides suppress raw-ground reads, failed overrides fall back, and
empty intervals still perform the manager lookup. A further 276 cases and 48
moving/saved steps execute the actual scan, rounding and absolute-value helper.
Another 118 cases and 48 steps execute the original house callback, actual scan
and housing getter together. Attached references keep the previous foundation
counter while still refreshing shrine masks. The composed pure protocol shares
one authoritative position and validates later foundation inputs before clearing
the earlier mask.
`source_house_terrain_frame.gd` ports `0x100bb96b..0x100bbbdb`, including the
forced timer update and actual foundation scan. The block beginning at
`0x100bb9a8` advances damage, converts the remaining timer back to construction
progress when the foundation recovers, and adds work from the current builder
count. Damage and completion require a strict threshold crossing. The 244
native cases and 64 saved sequence steps compare state and callback order,
including the completion sound and `abodecomplete` hook. Stat-row lookup,
model changes, effects, economy and the clock use explicit service adapters.
Terrain-override storage, the rest of the house update and actor lifetime
registration remain unported.

The target lookup at `0x100b7e80` tests the positive global override
before the positive per-house override. The Lua table binds these fields to
`AbodeOverrideBuildTimes`, `AbodeClearOverrideBuildTimes` and
`AbodeOverrideSingleHouseBuildTime`. The ordinary path multiplies the resolved
row's `Build Time` by the live multiplier, then applies a second multiplier
when the special flag is set and the resolved kind equals 1. The descriptor
records at `0x105e4c10` and `0x105e4c28` bind `FasterBuildTimers` and
`FasterBuildTimers2` to the same live float at `0x10fcd81c`. The record at
`0x105e4c88` binds `FasterBuildTimers_Farms` to `0x10fcd844`. Both live
floats initialize to 1.0 at `0x10437ec0`; the descriptor value floats hold
0.9, 0.8 and 0.9 respectively. The source modifier pass at `0x101b3181` writes
unlocked descriptors in table order, so the second general upgrade replaces
the first. Inactive descriptors leave their destinations as they were.
`source_progression_modifiers.gd` preserves all 15 records and 14 destinations.
The composed house frame calls `source_house_build_time.gd` using the live
values and a resolved row. Another 120 original executable cases and 20
saved steps exercise the actual unlock set membership query, modifier pass,
target lookup, foundation scan and house frame together.

`source_house_base_stats.gd` now selects that base row using `0x100b6750`.
Standalone houses use their stored index. Attached houses use the kind in the
attachment and the original switch at `0x1013caa0`. The initializer copies
the five matching settlement rows from the resolved unit table. The fallback
slot has no initialized template in this source and remains unavailable.
The attached lookup replaces capacity, breeder count, both belief bounds and
birth rate, preserving the other recovered fields. The 90 native row cases
include all 62 source rows. Another 36 cases execute the actual base lookup,
unmodified stat getter, build-time calculation and terrain/work frame together.
Those captures keep the shrine masks and environment modifiers clear.
The named stat query now composes the base row and shrine mask with the
environment pass at `0x100b7744`. The `Environment Buffs` registration names
`balance/environmentbuffs.csv`. Its six supplied rows affect
`Belief Modifier` through tree, rock and God Seed counts or the fraction of
nearby ground covered by beautification. The original calculation raises
count-based multipliers to the object count and interpolates beautification
multipliers from 1. Caps below 1 are floors. Caps at or above 1 are ceilings.
Homeworld6 awards its tree advances at 290 and 5,000 followers. Completing
their typed research applies the two source tree multipliers in table order.
The campaign samples live trees around an abode's source anchor and refreshes
the count after tree or terrain changes.
There are 192 native contribution comparisons and 102 composed stat queries,
including shrine-before-environment ordering, monastery/farm/mine eligibility
and real unlock set membership. The house-only branches of the original
refresh entries now supply those samples. `0x10044670` visits the active
house pool in order, clears the object counters, uses the base-row vision
radius for the spatial query and releases the results in traversal order.
`0x100444c0` refreshes beautification only inside the strict combined
radius and leaves the object counters intact. Both run the circular scan
at `0x100b7900`, clearing the old beauty fraction before resolving the
radius and sampling beauty followed by blight. Seven native refresh cases
and twelve saved sequence steps compare both branches with the actual
counting, classification and sampling instructions. The constructor uses
the same pure classification and scan.

The scan can now read the actual simulation raster. The original field read
at `0x100cf550` decodes an unsigned byte in units of 1/128, with missing
tiles returning zero. The combined blight read at `0x100cf4b0` uses the
greater of fields 2 and 3. The existing-plot query reads field 5 separately.
The original absolute writers preserve truncation and byte wrap, the
protected-tile branch and the 128-entry notification queue for fields 1–3.
The simulation stores tiles in row order and the executable comparison uses
the original Morton order. Seven native write stages, 18 probes per stage and
a composed house refresh compare those representations. The authored world
save restores the fields, and rebuilding influence clears only fields 4 and 6.
The Beautify action at `0x10086890` quotes the uncovered part of its footprint
and calls `0x10086780` to clear blight fields 2 and 3, paint dry cells in field
1 and write their timeout in field 7. The playable campaign command now uses
that brush. Ten executable cases compare the actual charge request, brush
bounds, field writes and refresh region. In the public campaign, the brush's
area callback now updates the ordinary abodes' beauty sample. The port uses
the compatibility abode center and live vision radius with the recovered
scan and belief modifier. The arm window limits repeated activation costs.
The terrain's benefit is independent of that window. At expiry the public
campaign resamples cached abodes near changed cells. That invalidation is a
compatibility integration. The original expiry path invokes the cell dirty
callback, and the original house refresh has separate call sites. The source
action's other spatial entity effects, full notification consumers and
particle burst remain pending. The campaign renderer now ports the
`shdrTerrain50` terrain shimmer using `GemDiffuse.tga`, the texture bound at
sampler 3 by the original terrain pass. It samples the saved terrain fields on
the streamed mesh and removes the shimmer as the painted bytes expire. The
timeout routine at `0x100d0730`
advances field 7 in whole timer steps, then clears allocated fields 2, 3 and 1
when a nonzero cell timer reaches zero. The port preserves tile and Morton
order, retains fractional elapsed time, and reanchors without decrementing
when the normal clock exceeds the ten-step catch-up limit. Explicit elapsed
overrides can exceed that limit. Twenty-four original clock transitions cover
these branches and save continuation. A paid campaign cast runs through the
default 40-step lifetime in the headless game and reloads before the expiry tick.
The same run checks the actual belief increment, its displayed rate and
migration from a save with painted terrain and no cached house fraction.
The unlock table edits in `balance/balanceunlockmodifier.csv` are a separate
source path. `Faster_Building_1`, for example, changes the House Values rows.

The separate route-grid consumer at `0x100dc549` additionally gates by tribe,
family masks and the source spatial query (`0x1013efa0`). Its route-grid propagation,
spatial invalidation ownership, base-stat resolution and follower/house lifetime
integration remain unported. These stat-query comparisons do not enable the
unfinished source campaign or establish all actor behavior.

## Explicit remaining work

This is not a complete source campaign and is not enabled in the campaign
picker. The full global sculpting pre-tutorial/mission switch, original HUD visibility/style masks,
reaction details, rendering/audio for celebration effects and later Promised Land/story stages still
need ports. Camera focus coordinates are applied, but original normalized zoom
ratios and camera interpolation still need mapping to the presentation camera.
The older map's
construction, objects and victory conditions are not substituted for those
unported stages. Full current abode inheritance, biome rules, Astari setup,
source temple/chest lifetimes, Ark progression and the remaining story must be registered
before this can become the default original campaign.

The temple-site adapter now recovers all 27 Homeworld6 records with original
coordinates, optional raw height, rotation, model chain, costs and builder caps.
Their presentation uses supplied assembled models. This does not advance the
unavailable first-abode handoff. The independent temple repair port executes the
original currency gates (`0x1013ce70`, `0x1013ced0`), raw start (`0x1013d8b0`)
and complete work-state block (`0x10141204`–`0x101414d8`). It matches 236 native
cases, including ready/working/complete phases 5/6/7, payment order, inclusive
completion, Ark action requests and deferred reward flags. Reference-effect
internals, other temple-specific rewards, constructor/occupancy/burial, remaining phases
and full follower aggregation/dispatch are still dependencies. Compatibility
campaign repairs share the verified float32 work arithmetic and reloadable
`Config.templeFixerFalloff`; their existing worker assignment is not evidence of
the original job dispatcher.

The deferred Temple of Discovery reward branch (`0x10140b9c`–`0x10140c0f`)
is now a separate pure update. It clears pending/ready flags before completion
unlocks, then rereads the reward and source ID and calls the original temple
wrapper (`0x10051520`). Seventy-four cases execute that original branch together
with its real discovery type predicate, hash routines, wrapper and shared
dispatcher. Repeated updates and restoration cannot dispatch it twice.
`source_reward_dispatch.gd` ports the full `0x10050930` protocol, including
ordered story ownership, essential/nonessential choices and recursive five-slot
packs. Its 266-case comparison includes every recovered pack; three 28-step
sequences use the original Homeworld6 story rows, including the duplicate
`Story11` ID, without inventing a replacement identity. These captures adapt
final credit; the queue/inventory composition is verified below. Event-reward
selection and story-display internals remain explicit services.
These ports do not substitute the compatibility economy for the source campaign
or make the first-abode handoff available.

The shared reward queue now ports admission (`0x10050170`), collection selection
and acknowledgement (`0x1004eda0`, `0x1004eee0`), and LIFO consumption
(`0x10051080`). The pure `source_rewards.gd` composes those with dispatch and
actual acquired/spent count rules. Its comparison covers 327 cases and 1,147
transitions, including every original pack through the actual native dispatcher,
queue and inventory writes. It preserves queued-copy limits, pre-credit removal,
gem grouping, signed deferred resources, special extra actions and the original
follower seed draw. Restoring after every transition preserves queue ownership
and supplied RNG continuation. Pack selector results, current-currency helpers,
research internals, follower/name effects and story display remain explicit
services; these cases do not establish full reward-driven campaign progression.
The private definition carries source queue constants and all special-card rows;
source catalog registration and the remaining domain services still precede
enabling that path in the playable campaign.

The `promised_land` state owns the arrival, rock removal and first-abode
steps. After the rock, the source callback pauses the followers and waits one
second before selecting the plot and offering its original instruction. The
player can still sculpt inside the authored bounds. The instruction stays
inactive until the real plot registry finds a nearby footprint. The renderer
uses the extracted plot texture at the detached center returned by `PlotPos`.

Acknowledging the instruction releases the source reaction. The opening uses
the source plot conversion and release helpers, the original tent assembly and
resolved house values, and the tutorial's two-builder override. Movement and
work use the shared fixed-tick construction service. The source callbacks show
construction, clear the instruction on completion, and advance the tutorial
after both followers enter. Native follower action execution and full house
lifetime still need integration. `test_promised_land.gd` plays this sequence
from rescue using ordinary commands and reloads the world during construction.

The next source callbacks use the second-plot area at `(162,127)`. Clearing
rocks checks the tent's builder availability after one second. The builder pip
and the tent submit the same validated release command. The first tent retains
its breeder, and the released follower walks to a real nearby plot, builds and
occupies the second tent. The original tutorial holds entrance and breeding
behind their separate acknowledgements. The fixed-tick clock uses the source
birth interval and the original sunrise routine at `0x1019cc50` to restore day
speed. Save/load preserves the paused timer and recursive source callback. A
save from the earlier second-plot handoff enters the new source callbacks when
its archive and callback identities match.

The growth tutorial uses the original callbacks to count nearby plots and
abodes and to lock builder release at the end of the stage. Builders consume
reachable registry plots and reserve their old bed until they enter the new
tent. The population threshold and card come from the scoped original tables.
Showing the card requests an autosave, and closing the card or loading that
autosave advances to the chest handoff. The card's technology research remains
pending until a matching sticker is assigned.

`test_campaign_opening.gd` plays the actual rescue and first-cliff stair drags on
the real map, follows the pair to their first land-assessment pause and checks callbacks, detached state, malformed
saves and both direct/SQLite continuation. The later callback test explicitly
uses a controlled checkpoint fixture; it does not prove a complete trail run.
`test_campaign_camera.gd` executes the actual observer helpers with controlled
views and checkpoint fixtures, verifies each teleport guard and checks save
continuation. Its controlled fixtures alone do not establish trail playability.
`test_campaign_trail.gd` now plays the complete fourteen-checkpoint trail from the
original fractional water spawns using only accepted drag, camera and tooltip
commands. It exercises inward retraction and outward bridges, keeps both followers
moving without teleports, reloads SQLite during the second land assessment, and
compares the exact continued final state. Separate asymmetric fixtures verify the
final waiting and invalid-path repair branches on that genuinely played terrain.
The test also checks the ten-second arrival handoff, source effect/audio event
references, twelve-second tooltip expiry, sunset freeze and wrapped clock events.
This proves the trail under the currently ported navigation, not all original
movement/collision behavior, later tutorial playability or a complete campaign.

`test_promised_land.gd` continues the genuinely played trail through the first
rock, checks the seven-second explanation delay, source-only object exception,
midnight freeze, command-query ownership, save continuation and absence of legacy
card rewards. It also checks clicks across the complete authored footprint,
single removal, neighboring scenery preservation and malformed footprint rejection.
`test_map_objects.py` checks the native type/model mapping, source CSV record,
unsupported types and rejection of changed enumeration instructions.
`test_source_scenery.py` verifies the complete binary's hashes, native routine
bytes, model dispatches, captured counts, non-overlapping occupancy and independent
native first-rock/coastal-tree observations. `test_source_scenery.gd` checks the
injected state, all Godseed models, coastal occupancy, fractional restoration,
malformed transform rejection and visibility-mask ownership. Rendering checks
remove exactly one source boulder without exposing phantom packed-cell picking.
`test_house_values.py` verifies source/byte provenance, inherited
values and explicit unresolved fields. `test_source_plot_allocation.gd` compares
the nine fresh-region and 704 biome captures. `test_house_selection.gd` compares
4,608 original building choices and the native availability profiles.
`test_source_terrain.gd` compares default discrete source terrain queries and
their original Lua binding. End-to-end abode progression is checked separately
through the source callbacks and ordinary player commands.

`campaign_opening_player.gd` is a pure deterministic self-player. Its hypothetical
route search only chooses gestures; every edit is revalidated through the same
world command as player input. It cannot write terrain, teleport followers, grant
belief or change the story. It reconnects a stranded Builder's existing job
with validated layer drags before preparing further house plots.
For an isolated simulation run:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/play_campaign_trail.gd
```

The run writes its ordinary command trace to `build/authored-trail-commands.json`;
the verification suite writes provenance and its checked run to
`build/authored-trail-playthrough.json`. These are trail-only artifacts.
Add `-- --promised-land` to continue the self-player through the supported first
rock removal, five occupied tents, the ten-follower card and the first chest.
It continues through the original Timeline explanations, the typed resource
drop, the exit and three completed Beach Huts. It then opens Restore Ruins,
repairs the first Beacon, clicks its reward card and prepares further housing
for the 24-follower Power of Prayer milestone. The self-player completes that
card, collects belief from the source house group and performs the grass-layer
drag. The New Age Shelters card is completed and its one Tools sticker has
been consumed.

After Timeline exit, the source plot selector chooses the unlocked
`AbodeType_1_Rank_1` row. It uses the assembled `lowlandrural2` model and its
inherited capacity, build time and breeding values. The first completed hut
runs the source abode callback and anchors the original tip to the house.
Moving a Builder to a completed hut frees their previous bed. Births in both
homes count toward the original 16-follower milestone.

The first Beacon is source temple `1012` at `(165,144)`. Repair uses its original
assembled model, rotation, two-Builder capacity, work arithmetic and 600-tick
duration. Its recovered terrain-footprint predicate pauses work when terrain
buries the site. Builders reserve their home beds during repair and return
afterwards. Completing construction sets a separate repaired state. Clicking
the source `Card_Expansion` portrait activates the temple and unlocks the
original `Expansion_1a` and `Expansion_1b` influence areas. The source script's
messages, autosave, reload continuation and population threshold execute through
the same inert callback interpreter. Mid-repair SQLite continuation is compared
tick for tick by `test_promised_land.gd`.

The playable integration uses the existing cell-route and approach adapter for
Builders. Full native follower action dispatch and house lifetime remain
unfinished.

The four original Belief listeners and seven localized messages execute through
the existing interpreter. The desktop listener gives 500 belief if the balance
is zero, fills nearby Beach Huts to their inherited capacity and selects at
most four houses. `source_abode_clumps.gd` follows the native pool traversal,
strict distance test, linked merge order and first-largest tie rule at
`0x10246d80`. The isolated oracle checks 64 original callback sequences and
12 cases of the fill routine at `0x100b8a30`, including preservation of a bank
above the house's fill level.

Each collection moves the house's stored belief into the balance through the
same single-click command as the rest of the game. Save continuation executes
the original card reload callback and the persisted first-collection shortcut.
The counter hint and its 30-second fallback both reach the source grass lesson.
Its completion callback receives the actual layers of the validated terrain
edit, preserving the original skip for already lowered grass. The original
house-group arrow request and target handles are retained as plain state. Its
visual mapping remains unfinished. During Discovery, occupied Beach Huts
generate collectible belief on the existing campaign production clock using
their inherited belief values. The exact native production cadence remains
unverified.

The desktop Discovery and Pit of Doom listeners run against the original site
at (170, 162). The claim unlock follows the source influence check, and
construction uses the site's source work requirement and Builder slots. The
original repair reward is `Card_PitOfSacrifice`. The popup carries the original
localized explanation and its dismissal requests an autosave.

To regenerate the independent native comparison and run it in Godot

```
PYTHONPATH=build/research-tools python3 -m tools.native_abode_clumps_oracle
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/test_abode_clumps.gd
```

The first chest uses Homeworld6 `rewardchests.csv` row 5 at `(177,147)`.
`authored_chests.gd` composes the recovered constructor, exposure, opening,
reward-capacity and disappearance rules. The original Promised Land camera
callbacks select the search and click instructions. Opening starts the recovered
animation immediately, awards `Sticker_Tools_1` after the source opening timer,
and removes the actor after the source disappearance timer. The consumed source
ID, capacity counters and exact float32 phase timer persist through SQLite.
Rendering and picking receive detached chest snapshots. The typed research query
verifies that this sticker fits New Age Shelters.

The recovered Timeline stages retain their localized explanations and GUI
targets, the source input locks and the original callbacks for opening,
assignment and closing. Simulation commands gate both the close control and the
typed card drop. Completing New Age Shelters consumes the sticker in inventory
and native chest-capacity accounting, persists its assigned resource, and runs
the original completion callback and autosave. Reloading an incomplete Timeline
uses its original restart fallback. Reloading the completed-card autosave uses
the source return-to-Homeworld fallback. Program functions are appended during
extraction, allowing old pending callbacks to retain their identifiers when
verified opening saves receive the new stages.

The next source investigation is follower construction assignment. The original
`GetFirstPlotInRadius` Lua binding is `0x10243550`: it queries spatial kind mask
`0x80` with object radii enabled, then returns plot index OR `0x05000000`.
`SelectPLOT` (`0x1023eed0`) validates that tag and writes the selected UI pointer
at `0x10a748f0`; that operation alone does not establish a follower claim.
The native builder candidate routine is `0x100cd790`, in function-table slot
`0x105b68e0`. Adjacent routines `0x100cb1d0`/`0x100cb7d0` select farm/mine work:
their house-selector production-kind arguments are 1 and 2, whereas the builder
uses 0. These are different work selectors, not interchangeable abode paths.

`tools.native_build_candidate_oracle` now executes the builder's full scan over
explicit ordered plot candidates. Native house choice, worker-cap lookup,
distance scoring and target-reference writes run unchanged. The capture injects
spatial candidate membership/order, the actor-record guard, raw height and the
influence result. All 59 cases match `simulation/source_build_candidates.gd`,
including unlocks, capacities, fractional positions, source lowland choices,
height bands, disabled actors, zero/negative weights and strict first-wins ties.
The builder reads the second worker-count array at counter base `+0x1004`, not
the first reservation array at `+0x4`; filling only reservations does not reject
a plot. Its influence call passes 1, requesting the original power/max field
predicate at the integer center rather than fresh allocation's stricter gate.
The registry's `claimed` flag (native `+0x4c`) does not reject a candidate in
this branch. A plot offer must not be treated as setting that flag or reserving
a follower; the native drag path can also set it (`0x10070b66`).

`tools.build_candidates` injects all 62 resolved source house capacities and
plot priorities with inherited-value and instruction provenance. The score
helper (`0x100ca310`, native `fsqrt` at `0x102d5a70`) preserves float32 stores,
the squared height term and the sum of search/plot radii. Native height-band
conversion divides stored absolute height by the original double scale and
truncates; a float32 height of 7.5 therefore remains below raw band 25.

`World.source_build_offer` composes that pure branch with actual follower
positions, ground height sampled from current terrain, influence, source
availability and stable plot
identities. It requires explicit candidate order and decision parameters;
the source spatial collector and full follower decision dispatcher are not
substituted with a guessed order/profile. The played first-plot test checks
live/detached agreement and absence of state mutation. Existing buildings leave
this query unavailable until their real worker counters and candidate branches
are connected. These offers do not start jobs, claim plots or enable the
unavailable abode handoff.

The source Lua `BuildAbodeOnPlot` binding (`0x10244460`) calls `0x10045500`,
which constructs through `0x10044cb0` and then invokes additional building/state
operations (`0x100bab30`, `0x100b8810` with state 5). It must not be assumed to
be the ordinary follower's construction-start path. `CanFollowerBuildOnPlot`
(`0x10240480`) resolves follower/plot handles and checks a native house choice;
it alone does not establish worker assignment, navigation or construction.

The ordinary follower starts construction through `0x1006b4d0`, whose factory
is `0x10044cb0`. `tools.native_plot_conversion_oracle` executes that factory's
selection, placement, matching-house rotation and plot release. Allocation and
the full building constructor are explicit adapters, so these 20 comparisons
prove the request protocol rather than a functional building. Ground and a
single native random word are injected inputs; the original RNG stream has not
been substituted with a Godot stream.

`simulation/source_plot_conversion.gd` reproduces moved-point ground sampling,
the 0.02 source height offset, original-center biome selection and float32
placement/angle stores. Rotation starts consuming one random word only when at
least three existing buildings share the chosen type and owner; its low 15 bits
select one of four quarter turns. Type-zero raw requests remain unsupported,
with no fallback model. Successful new construction unregisters the footprint,
returns its stable pool identity immediately and dirties the surrounding nine
regions. This differs from the deferred fade/release of geometrically invalid
plots. Allocation failure and reconstruction retain the original plot.
Save-codec continuation, exact pool order, dirty regions and double-release
rejection are checked headlessly. The native stack-cookie helper also executes
unchanged: stubbing it with a zero integer return would incorrectly erase the
factory's already prepared house-pointer return. The full constructor, follower
state transition and campaign callback dispatch remain to be connected.

`tools.native_build_start_oracle` now executes the ordinary follower's whole
`0x1006b4d0` start routine and the factory together, with 15 captures. The full
house constructor, cost evaluator/payment, settlement lookup, target assignment,
action executor and effect delivery remain explicit service adapters. The native
type-one reference constructors run unchanged. Their target copies the building
identity while retaining the reference's initial (-1,-1) position.

`simulation/source_build_start.gd` ports this service protocol. Ordinary workers
look up their settlement at the actor position; specialized workers use their
stored settlement. Food-spending enablement is queried for both, but only
ordinary workers request/pay mode-one plot cost. Payment precedes allocation,
including zero/negative supplied costs, and allocation failure does not refund
it. A positive payment emits the native payment-effect request only after a
successful factory result. Target assignment uses action 250 before requesting
the next action: 103 ordinarily, 108 for specialized farmers or 111 for miners.
Native effect (-1,5,1) and the constructed building's half-size rectangle follow.
No new art/audio mapping is inferred from those numeric intents.

Native and pure comparisons check all operation ordering, raw constructor
arguments, source selection, immediate plot release, targets, action requests,
effects and dirty rectangles, including exact continuation from the save numeric
codec. Controlled farm/mine biome-unlocked cases select source indices 6/12;
locked and invalid special-abode requests preserve index zero. The special flag
with profession zero cannot select an ordinary abode (`0x10026a30`); it must not
silently become an ordinary request. The campaign does not yet execute this
protocol as a complete job until its currency, startup, model and action/path services
are available. The constructor/reference composition below does not enable the
unavailable first-abode handoff.

`tools.native_house_constructor_oracle` executes the complete original house
initializer (`0x100bc660`) and base-entity initializer (`0x1003f610`) with explicit
resolved-stat, model-resource, clock, sampled-field and spatial-membership
adapters. Native nearby-object classification (`0x100b7460`), circular field scan
(`0x100b7900`) and the initial occupancy branch (`0x1003e400`) also execute. That
last routine sets authoritative occupancy; only its renderer dirty notification
is adapted. It must not be replaced with a blanket presentation no-op.

The 83 captures cover all 62 original source rows plus flags, explicit resource
configuration, supplied/masked/overflowing identities, a 64-bit clock,
reconstruction, scenery classes, fractional coordinates, map clipping, strict
beauty thresholds, farm/mine requests and the source rotation override for
`AbodeType_1_Rank_4`. Core fields and slot resets match
`simulation/source_house_constructor.gd`. Identity zero in the supplied low
24 bits consumes the global counter; overflow of those low bits is preserved.
The caller supplies simulation time explicitly, including the native three-second
base timer offset. No wall clock is read by simulation.

Footprint origins use the original `0x10357040` helper: float32 subtraction of
half the base size, then `floor(value + 0.5)`. Flooring the subtraction directly
would shift odd-sized buildings and fractional/edge placements. Native occupancy
raster cells and dirty rectangles are checked independently; reuse skips fresh
registration and retains existing occupancy. The building record owns origin and
size, and its pure footprint query clips against the original 1024-square map.

Surroundings preserve native truncation, strict squared-circle membership,
row/column order and the `> 0.5` beautified-field threshold. Full query sequences
are compared using compact hashes rather than shipping millions of duplicate
sample records. Supplied nearby scenery is classified with the native type/mode
predicates. This does not recover the spatial collector's membership decisions.
Specialized mine initialization requests the source rank-specific random range;
an explicit supplied result is used by the capture, not a claim about the RNG
stream. Source events remain numeric intents without invented particle/audio
mappings. Save validation normalizes identities and scalar/slot types and checks
the next initialization continues identically after the exact-number codec.

These are core-state observations under explicit service inputs. Dynamic house
modifiers (`0x100b7580`), model/component resolution, full resource currency state,
follower action paths and the house lifetime still need to
compose before enabling the first-abode campaign handoff. Parent/null table rows
in constructor comparisons do not make those rows buildable campaign content.

`tools.native_house_factory_oracle` now executes allocation (`0x100441c0`), the
plot factory and the full constructor/base initializer together. Its constructor
hook observes arguments without replacing instructions. Fifteen transactions
compare with `simulation/source_house_factory.gd`, including full-pool failure,
normal/reused slots, fractional placement, farm/mine initialization, sampled
surroundings, initialized occupancy and immediate plot release. Model resolution,
modified-stat evaluation and spatial membership remain explicit service inputs.
This is stronger than comparing the constructor and factory separately, but it
does not execute follower decisions or house lifetime behavior.

The native allocator updates list links only. It links the allocated slot into
the active chain before the factory counts matching house types/owners. An old
body in a reused slot can therefore cause one rotation RNG call where two other
matching active houses would not. The pure pool retains that body until the
constructor replaces it. This describes raw pool release; full building
destruction/cleanup is a separate operation, not established by this test.
Released identities return in LIFO order, and native release returns the next
active identity. Allocation exhaustion consumes no ground sample, random word,
entity identity or plot ownership.

The original world initializer (`0x101b02c0`, called at `0x10435d75` with world
root `0x10d9b590`) allocates `0x2d8004` bytes for the house array: a four-byte
array header plus 4,096 records of `0x2d8` bytes. Its pool header lies at root
offset `0x231ee4`, resolving to `0x10fcd474`. The native header initializer
`0x1019fbc0` is executed and every free-list identity compared against pure
initialization. This is pool capacity, not a claim that all slots are available
for player abodes or that the world contains no reserved buildings.

`source_house_factory.gd` commits the initialized house and identity counter,
then runs settlement attachment and source plot release in order. Returned
descriptors detach mutable bodies; the pool owns authoritative geometry. A
production pool save rejects missing/partial active bodies and mismatched
body/slot identities. Both pools and the exact-number codec preserve factory
continuation; occupancy is checked independently of any rendered mesh. Raw
capture inputs can contain deliberately partial existing bodies for the matching
scan, but these are not accepted as complete production saves. Parent/null rows
do not acquire model support from these low-level operations. The remaining
follower/global-identity startup, action/path services, model/component
resolution and lifetime/event composition still gate the first-abode campaign.

`source_target_references.gd` ports native logical-follower assignment
(`0x10033d20` / `0x100caf60`) and clearing (`0x10033cd0` / `0x100caeb0`). The
original reset and validation helpers execute in 33 CPU cases with 44 observed
transitions. Only skill evaluation (`0x10034650`) and invalid-reference diagnostics
are adapted. House references require a nonzero matching identity. Plot references
require a nonzero size and float32 squared distance from the current center no
greater than the original double threshold. Invalid new references are validated
by value, preserving the old target and caller's input. Invalid stored handles
reset without changing counters; unsupported reference kinds remain unavailable.

Assignment increments the second worker array and float32 skill sum, leaving
the first active-work array untouched. Clearing reverses that reservation except
for the follower's home. Action 106 retains a matching home; action 104 can change
settlement membership. Local profession 8 can convert the target house's
profession. The house field at `+0xec` is its settlement index, as shown by the
original membership writer at `0x10124b9f`; it is not a renderer handle.
Settlement total increments are distinct from worker reservations and are not
undone by this clear helper. Full settlement lifetime remains separate.

Repeated raw assignment does not clear the prior reservation. Clearing an
unregistered valid target underflows the native unsigned count, and a changed
skill can leave a negative residual. These raw helper results are preserved;
source action lifecycle must supply the appropriate clearing order. Neither
helper claims a plot by setting its claimed flag. Tests cover inclusive distance
boundaries, stale identities, null owners, owner/profession conditions, skill
rounding, detached restoration and exact-number continuation.

`tools.native_construction_start_oracle` executes the ordinary start, actual
allocation/factory, complete core/base initializer and actual target setter in
one capture. Constructor and target hooks observe arguments without replacing
instructions. Twenty-five transactions compare with `source_construction_start.gd`:
successful and paid/full-pool cases, fractional/zero skill, settlement attachment,
specialized farm/mine actions, local/foreign profession conversion, freed-slot
reuse, full 32-bit identity-counter wrap, prior plot targets and sampled scenery.
The composed pure service uses the same authoritative house/plot pools and
counter dictionaries. It pays before allocation, commits the complete source
house, releases the plot, reserves the worker and then requests the source action
transition. Active construction work remains zero at this point.

The integrated capture also confirms that converting a previously targeted
plot does not itself remove its old worker reservation; earlier action cleanup
must do so. Restoring the integrated result retains the actual new house identity
and permits clearing its target reservation without mutating the original saved
snapshot. Full-pool failure retains payment, the old plot and the invalid target,
without consuming identity, skill evaluation or action transition.

The integrated comparison still supplies dynamic stats, model/field membership,
settlement attachment, job skill, currency writes and action/path transition at
explicit boundaries. It does not establish arrival, active work, native follower
startup/global identity ordering, spatial dispatch or the complete building
lifetime. The first-abode campaign handoff therefore remains unavailable.

`source_plot_cost.gd` ports the original quote (`0x10235bd0`), per-resource
affordability (`0x10235c90`) and combined predicate (`0x10235cf0`). Its adapter
injects all 62 resolved `Wheat Consumed` values at native offset `+0x108` with
table/executable provenance. The quote selects an ordinary abode by stored plot
size and its stored height's native truncated altitude band. The cost wrapper
passes scheme zero to the selector; it does not query the plot's actual biome
or use a placement offset. A matching house is required before settlement lookup.

Food cost is the selected float32 value multiplied by the original three gates:
no settlement at the unshifted plot center, positive native counted-house total,
and enabled `FoodSpending`. The count is the source per-tick total at
`0x107d1b44`; the original loop counts surviving houses in states 1 and 4.
It must not be replaced by the number of allocated pool slots. This port accepts
that total explicitly while the full native house update/lifetime is unported.
Mode one compares signed 64-bit food against the quote. Mode two compares ore
against the source zero threshold; other modes permit the request. The combined
predicate always checks mode-one food and that ore threshold. These helpers
do not spend resources or add an invented ore cost.

One hundred original CPU comparisons check gates, negative/large signed currency
inputs, fractional/negative controlled costs, row availability, source center
queries and exact height-band boundaries. Normal quote rows remain the source
values; controlled overrides only establish arithmetic behavior. Numeric codec
continuation is checked separately. Five whole construction-start captures now
run the actual quote without a cost adapter, including first-house waiver,
settlement waiver and paid allocation failure. Native captures and pure tests
compare settlement queries in order: actor position for the start's attachment
choice, then plot center for the quote. Currency mutation and settlement coverage
remain explicit services, not proof of a complete campaign economy.

`tools.action_sequences` now recovers 108 native action identities from the
original registration instructions and preserves all 446 authored rows from
`balance/actionstates.csv`, alongside their original action descriptions. The
native IDs distinguish `BuildPlot` (102), `BuildHouse` (103), `BuildFarm` (108)
and `BuildMine` (111). Their source build sequences begin with `Move`; selecting
that state is not equivalent to arrival or active work. Source names and animation
references remain original strings rather than replacement art or clips.

`source_action_sequence.gd` ports the native selector (`0x10065a10`). A positive
skip probability consumes the original 15-bit random sample and skips only when
the float32 sample is strictly below the float32 probability. Equality reaches
the validity check. Rejected/skipped entries use `SkipToState` when nonnegative,
then `NextState` when nonnegative, then the following index. The native loop
allows 21 attempts across a 20-slot action. A latched lost flag forces the raw
return index to zero. Validity receives a by-value state record; local control
changes can affect this selection but cannot mutate the source table.

The random step reproduces the actual CRT routine (`0x1035f7f0`) with supplied
32-bit state, multiply/add wrap, upper-word shift and 15-bit mask. The native
oracle executes that routine itself, adapting only its thread-record lookup.
It does not use a replacement random-word stub. The per-call native state
constructor independently confirms unspecified slots' default selection controls.

The 438 CPU comparisons cover available authored entry points and controlled
branch cases: strict probability equality, zero/negative probabilities, loops,
jumps, lost-flag persistence, unsigned seed wrap and by-value control changes.
Exact-number saves preserve both controls and random continuation. Full validity
predicates, the complete action runner, path navigation, animation-time rules, work counters
and lifetime are still unported dependencies. Four authored rows with blank
numeric controls remain explicitly unavailable until the native CSV default
handling is recovered; their raw source text is preserved. This does not enable
the private first-abode handoff or establish any additional complete campaign.

`tools.action_entry` additionally recovers all 52 action-update type identities,
including `MoveTo` (4) and `AnimationEndFaceTarget` (51), from their original
registrations. It resolves 443 authored state entries' update/loop fields; three
empty Astari rows retain explicit unavailable records. This is independent of
the four unresolved numeric sequence-control rows described above.

`source_action_entry.gd` ports the entire native entry routine (`0x10067620`). It
sets the state index and clears byte `+0x69` before resolving a clip. It preserves
the original missing-clip test: the resolved ID must be at least 347 and the
update type at least 200 to make this helper return false. That branch skips
heading delivery, but still requests clip duration and, when an animation
channel exists, the playback intent. Both clip timing accumulators reset even
on this failure path. A missing channel skips visual delivery without suppressing
the authoritative clip/duration state. These are the native helper's raw results,
not permission to display replacement animation or enable unavailable models.

The 459 native comparisons execute the full helper and real stack-cookie check,
adapting only clip resolution, duration and heading/playback delivery. They cover
443 authored rows plus boundary IDs/update types, missing channels, source float32
orientation scaling, zero/negative supplied durations, resolver changes to its
by-value state copy and exact-number continuation. Inputs and actor snapshots
remain plain data. Original clip/variant resolution, duration-table lookup,
state updates, navigation, working-counter registration and lifetime remain
separate dependencies before complete source follower execution.

`source_action_controller.gd` now ports the original advancement controller
(`0x1006ae00`) and composes the selector and entry helpers above. A normal
continuation takes the current row's nonnegative `NextState`, otherwise the next
row; an initial call keeps its current row. A failed terminable state ends
directly. Other failed states can use `EndSkipState`, but only when it is strictly
positive: zero does not jump back to the first state. The original state is
restored on the end path. When an unfailed action loops, the controller retries
selection from zero and ignores that entry helper's boolean result.

Successful entry returns the controller's raw false result and can emit a facing
intent in native phase 3. Ending sets native phase 2 and slot byte 255, then queues
a follower decision. This raw true result does not complete a building. End-sound
delivery preserves channel/phase gates and the original house-state suppression
for actions 103/108/111. Controlled target records also verify the distinct
114/115 state-six branch; this does not recover actual temple references or their
lifetime. Actor targets of unported reference kinds reject before mutation.

Only after queuing the decision does the controller compare a cached path target
with the current reference. Matching targets reset navigation and path timing,
clear the cache, select the original invalid reference and set the failed flag.
The distinct-record comparison (`0x1016acd0`) preserves native pointer identity
as typed stable pool IDs, then usable exact float32 positions, then nonzero UID
equality. It does not treat equal positions at the invalid (-1,-1) sentinel as a
match by themselves. Stale-reference invalidation and event ordering survive
the exact-number save codec; restored actors own detached target dictionaries.

The 133 comparisons execute the actual controller, selector, entry, seeded CRT
RNG, reference validation/comparison and default-state constructor. Only validity,
clip resolution/duration, target-position lookup, decision queuing, navigation
reset and presentation sinks are adapted. Captures include 106 available action
definitions' initial states and controlled fallback, cache, audio and failure
branches. Original default flags are checked against the constructor's actual
bytes. The scope excludes an original out-of-row looping retry and unsupported
reference kinds, plus full clip binding, navigation, state updates, active-work
registration and follower dispatch/lifetime. The first-abode handoff remains
unavailable until those dependencies are implemented and played together.

`test_campaign_opening_ui.gd` checks original clip roles, source messages,
readability after resize and command forwarding. `capture_campaign_opening.gd`
renders source rescue/embrace/worship/obstacle states in an isolated native
viewport and follows the real trail to capture the authored first rock;
captures are presentation evidence, not campaign completion evidence.

To reproduce the offline initial-layout recovery (optional research dependency):

```
python3 -m pip install --target build/research-tools -r tools/requirements-native-oracle.txt
PYTHONPATH=build/research-tools python3 -m tools.native_scenery_oracle --bounds 0 0 1024 1024 --skip-zero-density --output build/native-homeworld6-scenery-current.json
python3 -m tools.scenery_layout build/native-homeworld6-scenery-current.json
```

The optional emulator requires JIT access on macOS; it is absent from the game,
normal source extraction and standard test dependencies.
