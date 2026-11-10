# Dominus implementation plan

## Goal and scope

Build a God game in Godot 4.8 using the mechanics and digital resources described in the README. Start with a playable vertical slice, then expand toward the broader the original game-inspired experience. The README does not specify the complete rules, platform, or content scope; record discoveries and decisions as implementation proceeds rather than assuming the resource files document every mechanic.

## Architecture requirement: separate simulation and presentation

The implementation follows `docs/ARCHITECTURE.md`. Authoritative world state and
rules live in `game/simulation/` as headless `RefCounted` classes. Godot nodes,
scenes, meshes, UI, camera and audio live in `game/presentation/`. Application
coordination submits commands and advances fixed ticks; presentation receives
detached snapshots and events. SQLite and filesystem access live in adapters.

- [x] Separate the existing Asset Lab into presentation and establish dependency checks.
- [x] Implement simulation contracts and headless rule tests with the first gameplay feature.
- [x] Inventory the original large-map packs and offer eight distinct campaign starts, with Homeworld first; persist selected map identity and resolve its water/scenery on load. Keep maps without recovered starts or event rules unavailable.

## 1. Extract and catalog assets

- [x] Keep `data/godus2_4/` as a read-only source; put scripts, manifests, reports, and converted outputs in separate project directories.
- [x] Generate a reproducible inventory of paths, sizes, hashes, file signatures, and extensions. Group likely textures, meshes, animations, audio, UI, localization, configuration, and unknown files; identify duplicates and files without extensions by signature. Initial detector and SQLite catalog implemented; unresolved content stays explicitly unknown.
- [ ] Inspect representative files from each group. The source currently includes PNG and TGA images, MP3 audio, CSV and Lua files, and formats such as `.group.bin`, `.pack`, `.gfx`, `.datz`, and extensionless files. Determine actual encodings and relationships before choosing converters; do not assume extensions describe their contents.
- [x] Build and document repeatable extraction/conversion tools, starting with assets needed for the vertical slice: terrain textures, vegetation, a follower, a dwelling, UI, and basic audio. Preserve source paths and provenance in a manifest, including conversion settings and any unresolved dependencies.
- [ ] Inspect converted samples in Godot for scale, orientation, materials, transparency, animation, and sound. Record unsupported formats and blockers; leave unsupported content unavailable where extraction remains uncertain. All assets must come from the original game.
- [ ] Establish the rights and distribution status of the supplied resources before packaging or sharing them; keep the pipeline capable of working with locally supplied assets.

**Done when:** the inventory and conversion steps can be rerun from the source, a manifest maps a minimal usable asset set to its origins, and representative assets render or play correctly in a Godot test scene. Unknown formats and gaps are documented.

## 2. Define the first playable slice

- [x] Examine available game data and reference material to document the intended camera, terrain editing, follower behavior, construction, belief economy, and progression. Separate observed behavior from assumptions.
- [x] Specify a compact scenario: sculpt land, give followers space to build dwellings, generate and spend belief, and unlock one subsequent action. Define inputs, rules, feedback, win or stopping condition, and initial balance values.
- [x] Choose target platform and input scheme, and identify which assets and mechanics are essential for this slice.

**Done when:** the slice has an agreed, testable rules description and a prioritized asset list.

## 3. Establish the Godot project

- [x] Add the main menu and a searchable, category-filtered full asset library with on-demand media previews, text/hex fallbacks and missing-catalog guidance. Keep routing in application, catalog I/O in infrastructure, and screens in presentation.
- [x] Replace the flat catalog with source-folder and assembled-object trees. Reconstruct the supported Christmas tree from all four text geometry parts and their material/texture dependencies; add orbit, zoom, visibility, turntable and exploded inspection views. Recover 335 binary building families with source anchors and whole-building lifecycle playback.

- [x] Create a Godot 4.8 project, repository layout, import settings, and a runnable main scene. Document the exact engine version and setup commands.
- [x] Organize features within simulation, presentation, application, and infrastructure boundaries; keep source assets separate from generated imports and exclude caches from version control.
- [x] Add a development test map, basic logging, and a repeatable headless project smoke check.

**Done when:** a clean checkout with the required local assets imports and launches the test scene, and the setup steps are documented.

## 4. Build the core interaction loop

- [x] Implement a constrained 3D camera, picking, and clear hover/selection feedback.
- [x] Implement terrain topology, sculpt commands, buildability and navigation rules in simulation; derive terrain meshes, collision views and visual feedback in presentation. Measure performance independently of rendering.
- [x] Add follower movement/tasks, dwelling construction and belief accounting in simulation; present their snapshots and events with Godot nodes. Keep parameters data-driven.
- [x] Connect a minimal HUD and contextual feedback for actions, costs, progress, and blocked operations.

**Done when:** a player can complete the documented slice in the test map without developer intervention.

## 5. Persistence and validation

- [x] Save and restore versioned simulation data through infrastructure adapters, including tick and RNG state; recreate presentation from restored state and handle invalid saves gracefully.
- [ ] Test the core rules, terrain boundaries, resource accounting, follower recovery after terrain changes, and save/load round trips. Add an end-to-end manual playthrough and record performance on the target platform.
- [x] Test simulation headlessly without presentation, ensure snapshots cannot mutate live state, and verify equal results for the same seed/commands/tick count under different render schedules.
- [ ] Resolve blockers, tune controls and readability, and finish verifying original material and shader behavior. Procedural stand-ins have been removed.

**Done when:** the slice survives save/reload, passes its automated checks and manual playthrough, and meets documented performance targets.

## 6. Expand iteratively

- [ ] Prioritize additional powers, building types, follower needs, progression, environments, audio, and UI based on the slice and verified source material.
- [ ] Deliver each feature with its assets, rules, feedback, persistence, and tests; profile and optimize as world size and population grow.
- [ ] Prepare packaging and distribution only once asset rights and target-platform requirements are resolved.

## Open decisions and risks

Implementation progress: playable terrain-layer drags, follower navigation and
construction, belief, sheep, progression, SQLite saves, source animation/audio,
main menu, asset library and the large example world are implemented. Automated
checks cover deterministic simulation, transactions, save continuation, original
assets, every usable model, exhibit clearance and surface-relative navigation.
The installed engine is Godot `4.8.beta2.official.cafc17a19`.

- [x] Recover original male/female follower meshes, 32-bone rig and three clips.
- [x] Recover original sheep, trees, tents and 612 bank audio files.
- [x] Recover 3,050 model records (3,046 binary plus four text components).
- [x] Populate the example plane with all 3,041 models with recovered materials,
  arranged by ten categories, original group and component family.
- [x] Implement close/wide zoom, orbit, plane-relative pan, search, framing and
  component inspection; verify every usable mesh and placement clearance.
- [ ] Resolve nine model materials and one unsupported VFX geometry record.
- [ ] Recover remaining shader/material parameters and verified multipart transforms.
- [ ] Implement spherical/toroidal surface mappings when requested.
- [ ] Expand game rules/content beyond the current playable scenario.

- The complete mechanics and desired fidelity to the original game are unspecified; research and user decisions in phase 2 set the scope.
- Proprietary asset formats, missing dependencies, or animation data may require substantial reverse engineering or replacement assets; assess these in phase 1 before committing to a full content pipeline.
- Terrain deformation, collision, and navigation at scale are likely technical risks; validate them early in phase 4.
- Confirm the availability of the specified Godot 4.8 build and any compatibility constraints during project setup.

## Example habitats and detail playback

- [x] Assign source units land, water, shoreline and underwater exhibit surfaces.
- [x] Match reference land with smooth original-palette sand and muted uplands, without diffuse grain. Port original ocean flow/caustic and glint texture formulas into world and detail views.
- [x] Retain whole building assemblies throughout construction, including source-positioned chunks, scaffold/shadow stages and nonembedded final attachments. Verify all 335 recovered families.
- [x] Recover and expose 371 original clips with their source skins/rigs.
- [x] Add building component-stage and rank-sequence playback from HouseModels.h.
- [x] Add play/pause, restart, loop, speed, scrub and explicit unavailable states.
- [x] Validate every supported clip and native building/boat detail renders.
- [ ] Resolve four wolf slope-clip control transforms and nonmatching seasonal rigs.


## Original progression and influence

- [x] Use explicitly requested Roboto Condensed for UI and world labels, retaining font provenance.
- [x] Parse source chest, card/component, house, power-cost, shrine and unlock tables.
- [x] Implement chest exposure/rewards, card completion, supported abode upgrades and power gates in simulation.
- [x] Render recovered chest clips, whole building stages, card images and original power icons.
- [x] Enforce influence in simulation and tint all world content outside it using source parameters.
- [x] Grow influence through source population levels and repaired expansion shrines; persist earned areas.
- [x] Reverse horizontal trackpad panning, retaining vertical pan and Shift orbit/tilt.
- [ ] Resolve complete legacy-table/current-map registration and original object variant mappings.
- [ ] Port remaining card effects, powers, particle systems and late-game systems from verified source behavior.

## Runtime management and continuing growth

- [x] Remove used chest presentation; keep opened state for single-use rewards.
- [x] Recover and port original storm chest area budgets, bounded disk sampling,
  generation ordering and burial rounding; compare against original x86 routines.
- [x] Port source chest placement restriction/height gates and ordinary scenery
  and building clearances, including corner/radius rules (213 native cases).
- [x] Port the original chest factory protocol, type thresholds, story odds,
  reward identifiers and post-construction notification order (43 native cases).
- [x] Port original numeric chest construction, burial/clamping, spatial intent
  and buried-effect interval (106 native cases); compose it with the actual
  original factory (7 cases) and verify saved-record/RNG continuation.
- [ ] Connect renewable storm chests after porting the original scheduler,
  custom authored shape membership and source reward
  redemption. The runtime still
  has fixed chest placements; verified kernels alone do not replenish them.
- [x] Port chest exposure (`0x101520c0`), opening (`0x10152a30`) and lifetime
  update (`0x10153370`), including one-time reward dispatch at phase one-to-two,
  source open/disappearance timing and pool release. Keep authored ID `0x04`
  separate from opening phase `0x60`; ID-zero chests count until removal.
  Compare 44 original cases/68 transitions, including restoration between steps.
- [x] Port original reward availability (`0x10001600`), stock/acquisition limits,
  acquired and owned counts, default writes and unsigned arithmetic. Compare
  67 native cases/268 queries and compose actual capacity with the original
  chest lifetime (7 cases/21 transitions), including save continuation.
- [x] Port original weighted reward draw (`0x1004da90`) and era conversion
  helpers, preserving unsigned multiplication, explicit roll overrides and RNG
  consumption, including empty bags (320 draws/11 era values).
- [x] Port the complete original sticker selector (`0x1004de10`): reward-kind
  and era pools, rare/gem branches, source card/owned-stock category deficits,
  useful/equal fallback and ordered sticker selection (544 native cases).
  Card completion/remaining queries are explicit services; queue/inventory
  composition is verified separately below. The legacy runtime path is not yet replaced.
- [ ] Port the actual chest reward service (`0x100514f0`), including source
  sticker/pack selection and redemption; lifecycle dispatch comparisons still
  adapt the final grant service.
- [x] Port the complete shared reward dispatcher (`0x10050930`) and original
  chest/temple wrappers: story selection, independent card/sticker registries,
  recursive five-slot packs, silent/power flags and selector dispatch. Compare
  266 native cases including all 14 original packs, and three 28-step sequences
  using the actual Homeworld6 story rows with save continuation. These captures
  adapt final credit; queue/inventory composition is verified below. Event-reward
  selection and story display remain separate services.
- [x] Port original reward admission (`0x10050170`), collection query/acknowledgement
  and stack consumption (`0x10051080`), including queued-copy limits, actual
  acquired/spent writes, gems, signed deferred resource counters, research-service
  ordering and source follower seed consumption. Compare 327 native cases/1,147
  transitions, including all 14 original packs through the actual dispatcher,
  queue and inventory writes, with saved continuation. Supply a reusable pure
  composition in `source_rewards.gd`. Currency-helper/effect internals,
  event selection, source catalog registration and public runtime integration
  remain separate work; selection is an explicit service in these pack cases.
- [x] Port original card research registration, hashes, progress/remaining,
  eligibility, sticker assignment and completion against shared inventory.
  Preserve two ordered sticker categories, lifetime-versus-owned gates,
  non-atomic failure ordering and completion notifications/cache/effect intents.
  Compare 624 native cases/4,920 transitions, including every recovered advance
  across seven scopes, and continuation after every saved mutation.
- [x] Compose actual reward consumption with source research in the same
  inventory, including manual assignment and automatic internal stickers.
  Compare 108 native cases/351 transitions with full storage/research helpers,
  including all 56 Homeworld6 advances. Inject the recovered source catalog into
  the private campaign; keep unsupported old type rows explicitly unavailable.
  Downstream advance effects, other startup registries and public runtime
  integration remain incomplete.
- [x] Compose source sticker selection with actual research, dispatcher, queue
  and shared inventory. Recover the original era field and non-null detail-link
  gate; retain duplicate source card/sticker rows with last-registered lookup.
  Compare 432 native cases/2,451 transitions, including seven scoped catalogs,
  all fourteen shared packs, research changing the next reward, resource credit,
  explicit roll overrides and shared RNG/save continuation. These cases retain
  controlled era context; source-era composition is verified separately below.
  Outer startup registration and remaining effect services stay explicit.
- [x] Port original fresh pack/sticker/card binding (`0x101ab265` onward),
  detail links and zero-row resets. Register both capacity tables from the
  original shared limits and each card's signed `Max Collectable` bits; retain
  existing registered limits and first-capacity/last-row duplicate behavior.
  Compare 71 native cases/142 bindings with actual fixed-map insertion and saved
  continuation. Provide source catalog injection and a pure preparation factory.
- [x] Compare registered Homeworld6 catalogs through complete reward dispatch,
  selection, research and redemption: 70 native cases/904 transitions cover all
  56 advances with repeated requests and all 14 packs. The registry and reward
  kernels transfer detached records/counters across an explicit data boundary.
  This does not establish outer application startup, source era progression,
  unresolved older table types, downstream effects or full campaign completion.
- [x] Port original period/sticker-era cache refresh (`0x100f5c30`) and getter:
  descending source unlock scans, valid/dirty caching, decreases, global-cache
  reentry and period notification order. Compare 259 native cases/1,035 queries
  with actual hashes/unlock-set membership and saved continuation. Persist the
  derived fields with shared research-cache invalidation and migrate old flags.
- [x] Compose the actual source-era cache with reward selection, research and
  redemption (15 cases/98 transitions), including Homeworld6 Bronze/Iron and
  Homeworld7 Imperial with explicit prior unlock state. Do not invent an Imperial
  card in Homeworld6. Unlock-set population is a controlled service here.
- [x] Port original dependency registration and recursive claim propagation
  (`0x1015c7f0`/`0x1015c640`), compound activation, fixed capacities, first-seen
  timestamps and temporary-claim deadlines/queries. Recover 1,182 authored rows
  and preserve zero-duration and x87/SSE2 query behavior. Compare 155 native
  cases/931 transitions, including native and simulation save continuation.
- [x] Compose actual acquisition dependencies with shared rewards/research/era
  state (79 native cases/638 transitions). Read era from the real unlock set,
  verify Homeworld6 Bronze/Iron and Homeworld7 Imperial, and preserve original
  callback order without controlled acquisition-to-unlock maps.
- [x] Port original persistent rebuild and temporal expiry, explicit saved map
  insertion order, hash-bucket replay, phase-reset ordering, one due timer per
  update and forced refresh. Compare 89 native cases/403 transitions and saved
  continuation; keep numeric effect/configuration reset services explicit.
- [x] Compose expiry with the shared reward/research/inventory/era owner in six
  native cases/116 transitions, including all ten original temporary claims.
  Reuse validated acquisition context during automatic research credits.
- [ ] Port unlock startup indices/registered sets, CSV achievement callbacks,
  numeric effect/configuration reset internals, notification services and period-change effects.
  Verified graph dispatch does not establish every domain effect or full startup.
- [x] Recover 192 authored temple-site records across seven campaign scopes,
  including model/type chains, coordinates, heights, builder caps and costs.
  Show Homeworld6's 27 sites in its private source port and correct legacy
  beacon models, repair payment, worker caps and source completion unlocks.
  Preserve jobs, edited repair time and payment through saved-game migration.
- [x] Port original temple affordability and raw repair start, then the complete
  native work-state block (`0x10141204`), preserving callback/payment order,
  Ark action requests, completion hooks and deferred reward flags. Compare 236
  native cases and restored state. Keep unported service internals explicit.
- [x] Use original float32 temple work arithmetic in playable repairs, with
  `Config.templeFixerFalloff` reloadable from Update.csv. Compare ten actual
  two-worker ticks against the original at both default and edited exponents;
  verify save continuation and duration reload without losing fractional work.
- [x] Inspect dormant, working and repaired temple sites from the map using
  original type-specific illustrations, localized titles and descriptions.
  Show repair resources and builder requirements before explicit repair;
  preserve live detached queries and paused inspection without duplicate payment.
- [x] Keep authored temple centers/elevations stable through repair and completed
  component batching; resolve legacy shrine info from its original 2.4 class.
  Reject inert, already completed and unresolved model sites before payment.
- [x] Port the deferred Temple of Discovery reward branch (`0x10140b9c`),
  preserving flag clearing before unlocks, post-callback reward/ID reads and
  source temple-wrapper dispatch. Compare 74 native cases, including all
  recovered packs, repeat updates and restoration between updates.
- [x] Compose actual completion-marker registration/claim/credit (`0x1015cd60`)
  with deferred discovery delivery and shared inventory/rewards/research/era.
  Compare 59 native cases/242 transitions, all 27 Homeworld6 marker IDs and all
  fourteen packs; preserve stock limits, rejected marker gates and saved flags.
- [ ] Port full native temple worker/lifecycle mechanics, occupancy/burial,
  special-site effects, rewards and activation visuals/audio. The current
  compatibility repair loop does not establish full source behavior.
- [x] Port pre-work blocked/restored phases, construction/decay conversion,
  removal requests and expansion-shrine audio-handle release. Compare 312
  native cases and 32 sequence steps with save continuation. Keep final removal
  and public runtime integration pending.
- [x] Compose the original worker-presence ramp, passive work, forced decay,
  footprint transitions, cooldown and elevation targeting. Compare 276 native
  cases and 96 saved continuation steps. Compose actual repair/completion after
  that frame in a further 99 native cases and 48 steps, preserving shared slot
  identity and the completion sound's updated position. Keep spatial services,
  downward interpolation, final removal and full campaign wiring explicit.
- [x] Port original timed temple affiliation and circle/sphere containment.
  Verify 191 geometry cases, 101 affiliation cases and 64 saved continuation
  steps, including exact deadline boundaries, last-match ownership and source
  radius-column binding. Keep active-pool ownership and frame composition pending.
- [x] Restore single-click home belief collection and source-gated drag sweeps;
  validate each spend in simulation and avoid repeated commands per gesture.
- [x] Prefer exposed, affordable, reachable shrine repairs over automatic homes.
  Preserve source footprint dimensions and elevation, reserve builder approaches,
  migrate existing jobs without repaying, and let covering objects receive input
  before the shrine. Verify clearing with the original Finger of God power.
- [x] Reconcile map temple models, standalone completion stages, streaming and
  saved-site removal; require displayed recovered geometry for selection.
- [x] Split advances/resource gallery from the powers explanations and controls.
- [x] Add named SQLite save/load dialogs and JSON preference groups, defaults,
  individual/group/all resets, and live camera/audio/display/game settings.
- [x] Add OpenOffice opening and atomic reload of Adobes.csv, Followers.csv and
  Update.csv, with wide original unit columns and hundreds of balance values,
  including spreadsheet delimiters, in-flight build progress and saved rules.
- [x] Remove campaign home-count limits and reserve existing access paths.
- [x] Verify original-map ordinary-command growth to 66 followers/35 homes and
  controlled larger growth to 140 followers/81 homes with saved continuation.
- [ ] Implement the remaining original settlement/farming/mining/voyage systems
  and verify complete source campaign progression; continued growth alone does
  not establish the original endgame.

## Full the original game parity work

The active scope includes complete campaign progression, functional cards and
powers, distinct source campaigns, functional units/buildings, adventure parity,
original presentation/audio and end-to-end playthroughs. None of those broad
requirements is established by source extraction or a controlled fixture alone.

- [x] Recover seven separate 2.4 setup scopes and typed sticker research with
  source provenance, retaining the previously playable opening contracts.
- [x] Add supported settlement advances, community membership, specialized
  field/mine construction, harvest transport, collection and resource costs.
- [x] Persist research and economy and retain the player's saved CSV values
  during content migration.
- [x] Use the reference's additional research milestones and source production
  advances, construction modifiers and separate resource-spending gates.
- [x] Select larger source field/mine assemblies when space, resources and routes
  permit; require explicit tree/rock clearing instead of hiding scenery in plots.
- [x] Recover the authored manual Homeworld6 spawns and 14 trail checkpoints;
  implement and verify the source rescue, original animation roles and source
  callback/save continuation without enabling an incomplete campaign.
- [x] Execute source camera observer and leading-follower/sculpt callbacks with
  plain view commands, original pause/resume and guarded catch-up; verify the
  real rescue/stair gestures through the first land-assessment pause.
- [x] Play all 14 authored trail checkpoints with ordinary layer drags and no
  teleports; continue exactly through SQLite reload, source final-follower
  waiting, arrival schedules and the native config-backed sunset freeze.
- [x] Execute the original Promised Land arrival and first-rock callbacks with
  localized object explanations, native midnight timing and current tap balance;
  verify save/load without the older map's first-card reward.
- [x] Recover the native house multiplication stage and resolve known numeric
  fields for all 62 source records, retaining provenance and unresolved columns.
- [x] Recover the authored first rock's native type/model and full footprint;
  route picking, clearing, saved masks and independent source rendering through
  its single identity, separately from packed scenery-density bytes.
- [x] Recover native initial density/hash placements and authored loading order
  for Homeworld6; retain all 42 authored objects, original types/poses/footprints,
  compact provenance-backed data and immutable rendering descriptors.
- [x] Recover native flat/clear plot-capacity masks and radius-query semantics;
  compare current simulation geometry against original before/after clearing
  and sculpting outputs (12,288 coordinates). Allocation/claiming is separate.
- [x] Port native fresh-region plot allocation with whole-footprint reservations,
  descending size and row/column order; compare nine original CPU captures with
  explicit clipped eligibility inputs. Global AOI and existing plots remain.
- [x] Recover native biome scheme/type lookup and current height bands; inject
  source Homeworld6 data and compare 704 Homeworld/Weyworld queries.
- [x] Port existing-plot cell eligibility and full/interior ownership validation;
  compare 456 original CPU cases covering claimed neighbors, masks, origin
  rotation/biome gates and candidate blight. Resizing, merging and claims remain.
- [x] Port single-plot growth/repair layout, footprint ownership and ordered
  neighbor revisits; compile all 768 growth/4,096 repair branch combinations and
  compare 64 complete original maintenance iterations. Wider neighbor
  arrangements and follower claims remain.
- [x] Compose the enabled native region loop, LIFO revisits and fresh allocation
  with stable 1,024-slot identities and source transition/release timing; compare
  18 original CPU cases including window boundaries, overlapping regions and
  freed-slot reuse, and check detached snapshots and save-codec continuation.
- [x] Port adjacent dirty-region marking, availability/biome invalidation and
  row-major dispatch; compare 49 native neighborhoods and eight scheduler cases.
  Plot-clearing modes and campaign claims still need wiring.
- [x] Port the native registered-circle influence raster, byte quantization and
  distinct construction/power gates; compare 17 scenarios/191,000 field bytes
  and 49 native gates. Apply native border sampling and source unlocks to the
  private campaign's action queries; check its 13,500 initial-area cells,
  detached fields and save continuation. Dynamic building influence and the
  follower claim assignment remain.
- [x] Port the authored-area expansion/conversion/rebuild controller with source
  DesktopHigh timing, ordered dirty regions and the original completion event;
  compare 12 native scenarios/135,360 field bytes. Run it in the private campaign
  at fixed ticks, preserve mid-expansion SQLite continuation and rebuild on live
  area edits. Dynamic house influences, global callback consumers, shrine
  activation routing and follower claim integration remain.
- [x] Connect the native plot registry to private Homeworld6 terrain, scenery,
  quantized influence and biome/availability fields. Preserve source tick order,
  dirty propagation, persistent pool identities and transition timing. Verify
  original rotation-field provenance, ordinary-command trail/rock/sculpt plot
  allocation, SQLite continuation, influence shrink and controlled interior
  damage/release. Follower claims and abode construction remain separate.
- [x] Port the native builder's plot-candidate branch with actual inherited
  house priorities/capacities, worker-count and influence gates, source height
  conversion, exact scoring and strict native-order ties. Compare 59 original
  CPU cases and compose read-only offers with played campaign fields, detached
  queries and SQLite. Spatial candidate ordering, non-plot choices, follower
  dispatch and construction execution remain unported.
- [x] Port the native plot-to-building request: source selection, moved-point
  ground sampling, original-center biome, float32 placement/rotation and exact
  random-word consumption. Port successful creation's immediate footprint/pool
  release and dirty marking; compare 20 original CPU cases, including allocation
  failure and reconstruction. The full house constructor and follower job remain
  separate; a request alone cannot create a campaign building.
- [x] Port the original follower construction-start service protocol and compose
  it with native plot conversion in 15 CPU comparisons: pre-allocation payment,
  failed-allocation semantics, stored/queried settlements, specialized next-action
  selection, native type-one target requests and ordered effect/rectangle intents.
  Verify save-codec continuation. The full constructor, cost evaluator, reference
  counters and action/path executor are still required for campaign execution.
- [x] Port core house/base-entity initialization using all 62 resolved source
  rows: identities, capacities, clocks, flags, source slots, nearby-object
  categories, circular surroundings sampling, rotation override and exact
  footprint rounding/clipping. Compare 83 original CPU cases and saved-state
  continuation. Model lookup, dynamic modifiers, house lifetime, reference
  counters and the follower action/path executor still require composition.
- [x] Compose original house allocation, plot conversion and core initialization
  in a pure factory with authoritative occupancy and immediate plot release.
  Compare 15 whole native transactions, including exhaustion, reconstruction,
  stale-slot rotation, freed-slot order, farm/mine initialization and both-pool
  save continuation. Recover the 4,096-slot world allocation and compare the
  complete native initial free list. Logical follower references/actions,
  source spatial membership, global identity startup and model/lifetime services
  remain before campaign construction can execute.
- [x] Port native house/plot target validation, assignment and clearing, with
  distinct worker/skill arrays, home/settlement conditions and local profession
  conversion. Compare 33 cases and 44 transitions, including stale handles,
  distance boundaries, raw underflow and exact-number save continuation.
- [x] Compose the ordinary follower start with complete allocation, core house
  initialization and target reservation in pure simulation. Compare 25 whole
  native transactions, including paid exhaustion, fractional/zero skill,
  specialized actions, settlement membership, freed slots, identity wrap and
  prior plot targets. Action/path execution, dynamic stats/model resolution,
  original follower startup and full job lifetime still gate campaign use.
- [x] Recover all 62 source Wheat Consumed values and port the original plot
  quote and separate/combined currency predicates. Compare 100 native cases:
  source row/height selection, settlement and counted-house waivers, spending
  unlocks, signed 64-bit inventories and float32 boundaries. Compose actual
  native cost evaluation into five of the whole construction-start comparisons;
  preserve pre-allocation charging and distinguish actor/plot settlement queries.
- [x] Recover 108 native action identities and preserve all 446 authored state
  rows. Port native state selection and the original seeded CRT random step;
  compare 438 native cases, including authored entry points, strict probability
  equality, fallback jumps, lost flags, by-value checks and the iteration guard.
  Preserve unsupported blank controls explicitly. Validity predicates, action
  entry, movement, work counters and follower lifetime remain separate work.
- [x] Recover all 52 source action-update types and port the complete native
  state-entry timing protocol. Compare 459 native cases, including 443 authored
  entries, missing-clip/update gates, absent animation channels, timing resets,
  exact source call order, by-value resolver changes and save continuation.
  Clip/variant resolution, source clip-duration lookup, state updates, navigation
  and active-work bookkeeping remain required for complete follower execution.
- [x] Port the original action-advancement controller and compose actual state
  selection, entry, seeded random draws and target validation/comparison. Compare
  133 native cases: first/next states, terminable failure, strict fallback gates,
  looping retries, raw decision results, end-sound suppression, facing intents
  and ordered cached-path cleanup. Validate original defaults and restored actor
  continuation. Clip/validity services, navigation, active work and complete
  follower dispatch/lifetime still gate the first-abode campaign handoff.
- [x] Recover native building-choice fields/enumerations and availability scan;
  port size/order/unlock/height/biome/production filters and connect the tutorial's
  plot-claim key. Compare 4,608 native choices plus eight availability profiles,
  detached queries and persistence. Construction/claim assignment is separate.
- [x] Port the original default discrete four-corner terrain query and its Lua
  GetStepAtPoint binding, preserving contour medians, fractional coordinates,
  native float boundaries and saved submerged edits; compare 30,976 corner
  cases, 192 source points, Lua results, map edges and SQLite restoration.
- [x] Port native rock-only dirty refresh and the twelve-slot height motion pool,
  preserving original timing, retargeting, overflow and save continuation;
  compare eight native captures and update existing source mesh instances with
  visual interpolation. Runtime regeneration remains separate.
- [x] Port initial source trees' native terrain activation/occupancy changes and
  planted-height preservation; compare seven CPU captures and 162 scale cases.
  Keep clearing permanent, persist sparse transitions, and animate existing
  near meshes/distant sprites without rebuilding scenery tiles. Planted growth
  records and runtime density regeneration remain separate.
- [x] Recover native cooperative construction work arithmetic, apply source
  builder exponents/job skills to current campaign work, and persist/reload
  partial work and the editable abode contribution column. Compare 12 native
  cases and actual multi-builder construction; source reaction assignment remains.
- [ ] Port runtime scenery regeneration/resampling and source first-plot/abode
  construction; the first-house handoff remains unavailable.
- [ ] Finish the global sculpt pre-tutorial and
  Promised Land/story stages; register current abode/biome/NPC/temple rules and
  enable the complete source opening as the first campaign.
- [ ] Complete source settlement compression, merging, worker/breeder/buffer
  assignment, fatigue, biome rules and settlement upgrade effects.
- [ ] Expose the newly recovered economy unit definitions in the three live
  OpenOffice tables without replacing existing edits.
- [ ] Port every supported source advance/power effect and its feedback.
- [x] Restore resource-completion controls and command routing in the powers
  gallery, preserve original power identifiers, link locked powers to their
  actual prerequisite advances, and honor recovered source power unlocks.
  Verify earned sticker spending, two playable upgrades, typed settlement
  research, a real cast, duplicate rejection and save/load continuation.
- [x] Match the observed resource-assignment interaction: a bottom sticker
  strip, native drag previews, valid advance-portrait targets, on-card progress
  previews and retained resource artwork. Simulation owns per-card partial
  payments and completion; actual viewport drags cover invalid/partial/final
  assignments, upgrade/power effects and SQLite continuation. The complete
  original animated chronology layout remains separate presentation work.
- [x] Show selected buildings' live occupancy, construction, belief and
  production statistics through detached simulation queries. Reuse original
  info illustrations, localized explanations, pale panels, action icons and
  dotted separators; keep the responsive Info window inside the viewport.
  This displays current supported state, not missing follower housing/job rules.
- [ ] Register original setup scopes, events and story progression to each map.
- [ ] Implement remaining original society, jobs, Ark and endgame systems.
- [ ] Win every original adventure using ordinary commands and compare against
  original gameplay, including combat/hazard and navigation timing.
- [ ] Recover the eight unavailable islands without replacement terrain.
- [ ] Finish original effects, audio mixing, animations and material mappings.
- [ ] Verify fresh campaigns through every original milestone, save/reload,
  campaign transitions and the original ending.

Implementation evidence and current fidelity boundaries for the economy are in
`docs/CAMPAIGN_ECONOMY.md`.
