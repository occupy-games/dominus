# Simulation and presentation

The simulation owns the authoritative world. Presentation displays that world
and collects player intent. Their code and data dependencies are separate from
the first gameplay feature onward. The fixed-tick gameplay simulation is headless. The asset library and example
world are separate presentation screens; their deterministic exhibit layout is
computed from injected bounds by a plain simulation class.

## Code boundaries

| Directory | Owns | May depend on |
| --- | --- | --- |
| `game/simulation/` | World state, terrain cells/layers, follower tasks and routes, construction, belief, progression, command validation | Other simulation classes, plain data, Godot value types and `RefCounted` |
| `game/presentation/` | Nodes/scenes, camera, picking, terrain meshes/colliders, animation, audio, HUD, interpolation, development previews | Godot presentation APIs, detached snapshots and events |
| `game/application/` (when needed) | Command routing, fixed-tick driver, snapshot/event delivery, pause/speed control, save/load coordination | Simulation, presentation, infrastructure adapters |
| `game/infrastructure/` (when needed) | SQLite, files, content/config loading, versioned save encoding | Simulation data contracts and external I/O APIs |
| `game/tests/` | Godot integration and headless simulation checks | The layer under test |
| `tools/`, `assets/` | Offline asset discovery, extraction, selection, provenance | Source files, Python and SQLite |

Simulation classes extend `RefCounted`, not scene nodes or Resources. Use
explicitly supplied configuration, integer ticks and a seeded random generator.
Avoid global state and all input, physics-server, navigation-server, rendering,
audio, asset-loading, filesystem, database, and wall-clock dependencies. Godot
value types such as `Vector2i` are allowed; engine independence here means
independence from scene and device services, not a separate language runtime.

## Runtime contract

1. Presentation translates screen input into player intent. Picking produces
   logical world coordinates or stable entity IDs. Application submits a plain
   command such as a terrain edit or construction request.
2. Application advances simulation at 0.1-second fixed ticks, independent of
   rendering frame rate. Pause and speed controls change tick scheduling. They do not
   change rule implementations or inject frame deltas into them.
3. Simulation validates commands and applies them in a documented, stable order
   at tick boundaries. Costs, buildability, reachability and success are decided
   here. Rejected commands return explicit reasons without partial mutations.
4. Simulation publishes detached snapshots and ordered events using plain data
   and stable IDs. Copy mutable containers at the boundary; never expose live
   dictionaries, arrays or mutable entity objects. Renderers cannot write back
   through a snapshot. Keep presentation coordinates derived from simulation
   coordinates through an explicit mapping.
5. Presentation consumes snapshots and events to update meshes, UI, animation
   and sound. It may interpolate visuals between ticks. Completion of an
   animation, an audio callback or a collision callback cannot determine game
   outcomes. Application routes any new player intent through commands again.

Do not add separate competing copies of gameplay rules to the HUD or terrain
renderer. UI previews can consume simulation query results, but simulation
rechecks all conditions when applying a command.

Building inspection follows the same boundary. `building_stats.gd` reads current
occupancy, worker assignments, construction and stored resources without changing
them. Its birth/belief timing helpers are shared with the tick update, so the UI
does not maintain another set of rules. Application routes inspection to the
detached query owner while a simulation worker is active. Presentation receives
only plain numeric results and separately resolved original info artwork/text.
Opening or updating the Info window cannot collect resources or upgrade a house.
An ordinary click on a home submits its validated belief collection immediately;
the selection dock remains available for inspection. A held collection gesture
uses the source BeliefLeashing unlock and submits per-building commands, with
simulation rechecking that gate. Presentation tracks visited IDs until release
and intersects the full pointer segment so fast drags do not skip houses.
Card research in either gallery sends the same validated simulation commands;
recovered discovery and completion conditions remain distinct power gates.
Resource drag previews never debit inventory. Dropping onto a portrait submits
one assignment command, revalidated at the tick boundary. Simulation owns typed
research, per-card component assignments, stock consumption and completion.
Assigned resources persist separately from unspent inventory; compatibility
completion commands pay only the remaining recipe. Presentation receives numeric
progress and assigned resource IDs, and resolves their original sticker images.

Resource research keeps both original contribution categories; a drop consumes
one resource and credits only the selected card's matching category. Presentation
uses the recovered category icons and a detached command query to mark usable
stock. Belief production uses the original discovery-based GenerateBelief gate,
shared with the read-only building statistics query.

`campaign_chests.gd` supplies repeatable resources in compatibility campaigns.
It projects source storm-area budgets by unlock identity onto the active map,
uses the recovered disk sampler and original offline-storm delay range, and
keeps a bounded live supply. This compatibility refill clock is not the full
original weather controller. Source authored chest positions/history remain
separate. Its clock, serial, generated chests and seeded RNG are simulation
state and continue across saves; presentation cannot spawn or reward a chest.

## Terrain, movement and persistence

Campaign selection is presentation over detached map descriptors loaded by the
campaign infrastructure adapter. The adapter validates source height hashes and
injects the selected terrain, starts and shared rule data into simulation.
Simulation persists map ID/name and height fingerprint. Application resolves
that identity on load for bathymetry and legacy migrations; presentation never
chooses or changes authoritative terrain. Unsupported source maps have no
start action.

Voyages use the same terrain and command contract with pure expedition rules
in `simulation/voyage.gd`. The adapter injects verified island crops, mission
configuration and offline-parsed source-script instructions. A bounded pure
interpreter and explicit challenge API own conditional events and scheduled
callbacks, hazards, combat, shrines, powers and influence. They execute no I/O,
general code or scene services. Immutable definitions can be shared across
detached snapshots; mutable script variables, schedules and hazard fields cannot.
Missing source terrain leaves a mission unavailable.

The authored Homeworld6 rescue/trail is a separate, currently unpublished
campaign port. Infrastructure recovers the manual Lua spawns and inert source
callbacks; simulation owns rescue, source schedules, UI acknowledgement and
navigation. Presentation only draws source clips/messages and submits commands.
Camera-dependent callbacks consume a commanded orthographic projection as eight
plain numbers and a camera-movement-end flag. Simulation owns screen-margin tests,
offscreen pause/resume, tutorial persistence and the original guarded catch-up;
it never queries a camera or renderer. Headless self-play defaults to an explicit
all-seeing observer and can replay the same camera commands. The campaign remains
unpublished while later stages are ported. See `docs/AUTHORED_OPENING.md`.

The original final-follower waiting and arrival callbacks run in the same pure
interpreter. A config-backed day clock uses recovered native midday/sunset
expressions and fixed ticks; source schedules, plot-claim unlocks and cosmetic
effect intents persist as plain state. Missing particle/audio mappings remain
unavailable in presentation. The self-player searches hypothetical terrain routes
and emits ordinary validated commands; it cannot mutate the world to force a
playthrough. Promised Land's supported arrival/first-rock steps use original
callbacks, namespaced UI acknowledgements and an explicit object exception.
Authored CSV rocks have a source-derived center, footprint and native model
dispatch. Simulation owns their clearing and publishes detached visibility and
placement descriptors; rendering and picking consume those descriptors. Homeworld6's
initial placements are recovered offline by its original bounded x86 kernel,
including coordinate hashing, terrain sampling and authored-before-generated
loading. Infrastructure validates compact records and injects initial plain state.
Simulation owns footprint indices, clearing and cached visibility; presentation
receives shared immutable descriptors and detached byte masks. The optional CPU
emulator is never a game dependency. Runtime regeneration/resampling and the
older campaigns' packed scenery expansion remain provisional.
The pure source-plot query derives flat/clear square capacity from current
terrain vertices and authoritative scenery/building occupancy. Offline original
CPU comparisons validate this geometry independently of plot maintenance and
claims. The fresh-region allocation phase is pure code with explicit loaded,
capacity, height-band and eligibility callbacks; its controlled CPU comparisons
do not establish global AOI initialization or existing-plot behavior. Infrastructure
injects original biome/configuration rows and resolved house-selection records.
Simulation owns biome queries, native footprint/order/type selection and available
plot-size limits. Tutorial script keys participate in dependent source unlocks.
Detached query results cannot change those records or enable construction.
No emulator or fixture is a runtime dependency.
The existing-plot growth/repair branch kernels are compiled offline into small
source-derived decision tables; infrastructure validates and injects their plain
values. Simulation owns predicate evaluation, layout choices, footprint changes
and neighbor revisit ordering. The pure plot registry now owns the full enabled
region loop, stable pool identities, delayed slot release and stored geometry.
Its pure scheduler owns adjacent dirty regions, availability invalidation and
row-major dispatch. Explicit simulation callbacks supply loaded/AOI/biome/terrain
fields; the private campaign supplies its authoritative quantized influence,
source rotation bytes, biome rules, current terrain and scenery. Campaign
follower claims remain pending.
The native builder's plot-candidate branch is a separate pure query over explicit
candidate order and decision parameters. Infrastructure injects resolved source
capacities/priorities. Simulation owns house choice, distinct worker-cap and
influence gates, height weighting and float32 scoring. World composes these
rules with current follower coordinates, terrain and plot identities; query
results cannot claim a plot or start a job. Source spatial candidate collection,
non-plot candidates and follower dispatch/execution remain separate work.
The plot-to-building factory protocol is also pure: injected source constants,
house rows, unlocks, ground sampling and an explicit random-word callback determine
its constructor request. Successful new construction immediately unregisters
and frees the plot and dirties adjacent regions; allocation failure and reuse
retain it. The full house constructor must succeed before callers release the
plot. Request generation alone cannot publish a building or advance the campaign.
The ordinary follower construction-start protocol is pure coordination over
explicit simulation callbacks for settlement/cost lookup, payment, building
creation, target assignment and action transition. Its source ordering includes
food payment before factory allocation; allocation failure does not refund it.
It publishes source effect/rectangle intents after successful creation. These
callbacks must not reach presentation or I/O. The composed constructor and
reference service are described below; source dispatch and action/path execution
remain dependencies before the private campaign can run a complete job.
Core house/base-entity initialization now lives in `source_house_constructor.gd`.
Infrastructure supplies all 62 source rows and recovered constants; the caller
supplies simulation clock values, identity-counter state, resolved stats and
nearby/field samples. The initializer owns identity consumption and the resulting
plain building record. Its origin and size define authoritative occupancy;
clipped footprint cells are a pure query. Source registration/event intents do
not give presentation permission to change that footprint. Float32 state,
half-up origin rounding, source slot initialization and restored counter
continuation are checked against native captures. Model resolution, dynamic
modifier evaluation and the remaining unit/job lifetime are separate dependencies.
`source_house_factory.gd` composes the house pool, source constructor request,
core initialization, settlement-attachment service and immediate plot release.
The house pool retains stable slot identities, active/free ordering and the old
slot body until initialization replaces it. This matters to the native rotation
scan after allocation. Infrastructure recovers the 4,096-slot world allocation;
controlled smaller capacities test exhaustion and reuse. Production save
validation requires every active slot to contain a complete initialized record.
Restoration detaches bodies and normalizes their numeric identities. Occupancy
queries use the stored source origin/size without consulting presentation.
The factory remains a simulation service, not a player command or a substitute
for follower dispatch, source spatial membership, global
identity startup, model availability or the building lifetime.
`source_target_references.gd` owns house/plot handle validation and logical
follower target reservations, including separate worker/skill and settlement
bookkeeping. Its supplied skill evaluator is a pure simulation callback.
House settlement membership is stored explicitly, independent of any model.
`source_construction_start.gd` now composes the ordinary start, full factory and
target reservation against the same simulation-owned pools and counters. It
validates available dependencies before payment, but preserves the original
charge on allocation exhaustion. `source_plot_cost.gd` owns the original
food quote and affordability predicates using injected source costs, unlocks,
settlement coverage and counted-house totals. The priced construction entry
point composes this evaluator without moving it ahead of the original settlement
lookup or payment boundary. Explicit services supply currency writes,
settlement attachment and action transition. A reserved worker has not arrived
and does not increment the active-work count. These composed rules still need
the source follower startup, dispatcher, action/path and lifetime services before
the private campaign can execute its first complete construction job.
`source_action_sequence.gd` owns the original state-selection control flow over
plain, source-derived action entries. Infrastructure injects action identities,
authored controls, original defaults and CRT random constants. Validity and the
random stream are explicit simulation services; a state check receives a detached
entry, and its local control changes cannot alter immutable definitions. State
selection does not enter an action, move an actor or add active construction work.
The seeded random step owns only its explicitly supplied integer stream state;
it does not invent the original global startup seed or consumption order.
`source_action_entry.gd` owns the native entry flag, state index, clip identity
and simulation timing resets. Its explicit simulation services supply clip
resolution and duration; heading/playback services emit presentation intents
without controlling completion. A resolver receives a detached entry copy, with
its local changes retained for that invocation. Infrastructure recovers source
update types and looping flags. Missing numeric source fields remain unavailable.
The native entry helper itself does not increment active-work counters; movement,
state updates and work registration still belong to their own simulation ports.
`source_action_controller.gd` composes state selection and entry with original
failure, retry and end-of-action rules. Plain actor state owns phase, source
target values and cached-path bookkeeping. Reference validation can invalidate
a stale target; the distinct-record comparison uses stable pool identities and
source value predicates in place of native pointers. Decision requests are
queued intents, not immediate presentation callbacks or building completion.
Clip resolution, validity and duration remain explicit simulation services;
heading, facing and audio delivery remain presentation intents. Unsupported
reference kinds and out-of-row restart behavior remain unavailable. This does
not enable the unported movement, work update or complete campaign job.
Registry snapshots detach mutable state, and restore validates pool partitions,
footprints and float32 progress before normalizing JSON identities. The tables contain original rule
decisions, never meshes, UI state or renderer callbacks.
Original influence-circle registration, byte quantization and construction/power
gates are pure rules in `source_influence.gd`. Infrastructure injects recovered
constants and preserves source power-only/sculpt-unlock columns. The private
campaign owns its current authored-area radii, circle cache, quantized fields and
pending plot dirty regions in plain state. Fixed ticks run the original area
controller; source unlocks and the injected DesktopHigh expansion flag determine
growth and power-only conversion. Presentation receives detached fields and
derived area radii. CSV area edits force the original field rebuild at a
zero-delta configuration boundary, while persistence preserves in-flight growth.
Construction queries use the distinct source field gate. The campaign advances
plot lifetimes and dirty-region maintenance before each authored-area update.
Terrain edits and scenery clearing dirty the same registry. Existing plots
remain subject to native geometry repair when fresh origins leave influence;
influence gates apply to fresh allocation. A coarse influence-tile test skips
only fresh scans proven ineligible, never existing-plot maintenance. The uniform
Homeworld6 rotation field has a lossless default/override representation; its
adapter remains unavailable for nonzero fields pending the full blight state.
Dynamic building influences and global Lua callback dispatch remain separate
work; a completion event alone cannot advance an unported stage.
The private campaign's discrete surface queries also live in simulation: raw
vertices come from current terrain and submerged edits with an immutable source
floor fallback. The original corner/median decisions and Lua float conversion
are pure functions. Camera meshes, active-sculpt previews and the separate
continuous geometry query do not determine these authoritative callback results.
Source rock motion follows the same boundary. Simulation owns dirty-region
decisions, the native twelve-slot motion pool, sampled targets and fixed-tick
height changes. Config/provenance is recovered offline and injected through
infrastructure. Presentation receives detached motion snapshots, retains source
mesh transforms, and interpolates only moving MultiMesh instances; interpolation
never decides occupancy, clearing or plot validity. Native source rock identities
survive terrain height changes. The private campaign's initial trees retain their
planted positions. Simulation owns a sparse terrain-response mask and transition
timestamps: a changed sampled height releases plot occupancy, and restoring the
original height re-enables it. Presentation evaluates the recovered source scale
curve and updates existing near-mesh or distant-sprite instances. Disabled trees
cannot intercept picking; permanently cleared trees cannot be re-enabled.
Runtime density regeneration and planted growth records remain unported.
Removing that rock does not run the older map's card/reward bridge. The following
abode stage remains an explicitly unavailable handoff while source unit and plot
behavior is ported. Native house inheritance is recovered offline; its plain
resolved values and provenance are injected without scene/asset dependencies.

The application parks Homeworld during a visit. Island saves include the timer,
boat population, agents, hazards, script variables, scheduled callbacks and
outcome. Simulation also owns best results, native score calculations, reward
selection, claimed thresholds, RNG continuation and Homeworld redemption rules.
Infrastructure atomically persists a detached reward-entitlement profile before
application transfers its delta to Homeworld. SQLite saves redeemed totals with
inventory, so spending or loading cannot re-grant a consumed sticker. Presentation
only displays the rewards and forwards player commands.

Campaign research and economy follow the same boundary. Infrastructure injects
source sticker contributions, thresholds, settlement and production definitions.
The original storm-end chest budget, bounded disk sampler and generation batch
are pure kernels in `source_storm_chests.gd`. Infrastructure injects recovered
per-area limits and numeric constants; simulation callbacks supply unlocks,
seeded random words, spatial collections, candidate acceptance and construction.
The kernels preserve a pre-spawn count pass, overlapping-area counts, intervening
RNG consumption, retry bounds, burial rounding and collection lifetime. They do
not infer a storm schedule or grant chest rewards. Runtime storm scheduling,
custom authored scenery membership and reward execution remain pending;
the existing campaign still has no renewable storm chest loop.
`source_chest_placement.gd` owns the original byte/strength restriction gates,
height/unlock decisions, ordinary scenery footprint, building footprint/corners
and extra circular clearances. Explicit pure callbacks supply source field
storage, sampled ground and authored custom-shape membership. Unresolved custom
shapes block candidates instead of receiving replacement geometry.
`source_chest_factory.gd` owns the original allocation, height classification,
story probability, constructor request, generated source-ID/reward assignment and
notification order. The core constructor supplies its final stored position to
the notification; presentation cannot change that position or choose rewards.
The numeric chest constructor now lives in `source_chest_constructor.gd`.
It owns source burial/clamping, stored positions, rotation/kind, initialized
source slots, the randomized buried-effect interval and a plain spatial
registration intent. Renderer resource factories and matrices stay outside
simulation. Core initialization does not overwrite the factory's source-ID/reward
fields. Restore validates the record and spatial ownership and normalizes
integer/float slots without changing their values. The actual factory and
constructor execute together in the offline comparison; device/resource
services are adapters. Custom authored shapes, source reward redemption and the
storm scheduler remain separate work. Native
offset `0x04` is the authored chest ID; `0x60` is the separate opening phase.
Storm budgeting counts ID-zero chests regardless of opening phase until their
removal, and excludes authored nonzero IDs. These fields must not be conflated.
`source_chest_lifetime.gd` owns source exposure, opening, height response, phase
timing, ordered reward dispatch, destruction/pool release and numeric totals.
Services receive stable handles and detached arguments; renderer/audio intents
cannot control timer transitions or grant inventory. The ordinary opening query
composes influence, phase and exposure gates before mutation. Source bonus,
availability and mode gates remain separate from the reward service's actual
redemption. Saved active arrays validate unique identities and restore typed
core data, so continuing at a timer boundary cannot repeat a dispatched reward.
`source_availability.gd` owns the original stock/lifetime capacity and acquired
and owned counts in six plain tables. Missing limits initialize the native
default and emit diagnostic intents; an unknown key is not an existence test.
Subtractions and the minimum use unsigned 32-bit arithmetic, including native
wraparound. Infrastructure injects the recovered default. Queries that must not
change authoritative tables operate on detached state. Offline comparisons run
the actual fixed-map insertion, registration walks and arithmetic in the primary
capacity comparison, adapting only diagnostics. The composed chest lifetime
comparison retains a storage adapter with the same verified insertion semantics.
This verifies fallback decisions; queue admission and inventory writes have
separate comparisons described below.
`source_weighted_rewards.gd` supplies the original weighted-bag and era conversion
helpers for the reward selector. Explicit nonzero roll overrides consume no RNG,
even when their low sixteen bits are zero. Ordinary empty draws still consume
one CRT word. Multiplication wraps to 32 bits before shifting. Source comparisons
cover 320 draws and all conversion boundaries.
`source_sticker_selection.gd` owns the complete original selector: distinct
reward-kind pools, era weights, rare/gem exits, outstanding-card category totals,
owned-resource subtraction, useful/equal fallback and ordered sticker selection.
Infrastructure injects source config and symbolic hashes. Pure callbacks supply
current era, card completion/remaining and acquired/owned counts; the counts
compose with `source_availability.gd`. The comparison executes the entire native
selector and count helpers in 544 controlled cases. Completion/remaining-card
helpers and the combined selector/research pipeline have the additional source
comparisons described below. Queue admission and inventory credit
are described below; the legacy campaign reward path has not been replaced by
these kernels yet.

`source_reward_dispatch.gd` owns the full original shared dispatch protocol,
including NextStory priority, nonessential/essential story selection, independent
story/card/sticker registries, five-slot recursive packs and inherited silent/
power flags. Story ownership and pack counters are plain persisted state;
random words are supplied explicitly. Source-hash ordering, zero/negative pack
counts, nested counter resets and callback order are retained. Validated catalogs
reject cyclic or unbounded pack definitions before RNG or grants. Infrastructure
injects source constants and retains original pack/story rows with provenance;
duplicate authored story IDs are not renamed. Pure services perform story
delivery, current acquisition queries, selector calls, final credit and refresh.
Those service internals are not established by the dispatcher comparison.
The original chest and temple wrappers preserve distinct reason values seven
and eight and refresh only after dispatch. The offline comparison covers 266
cases, all fourteen source packs, and three 28-step Homeworld6 story sequences
with restored continuation. The enabled compatibility reward path is unchanged
until the remaining domain services and source catalog/runtime registrations
are ported.

`source_reward_queue.gd` owns original reward admission, collection queries and
acknowledgement, then last-in-first-out consumption. Admission counts all queued
copies of a reward before checking limits. It preserves immediate gems and the
separate mode-dependent resource path; signed 64-bit deferred counters use two
32-bit words so saves cannot round them. The queue stores original kind, reason,
source ID, flags and the two independent taken/display booleans. Padding bytes
from the native record are not authoritative state. Collection is an ordinary
simulation action, independent of whether its presentation animation exists.
Consumption removes a taken tail entry before attempting actual inventory credit;
discard flags and failed credit cannot retry it. `source_availability.gd` owns
the exact unsigned request/acquire/spend arithmetic and dynamic-claim exemption
gates, retaining default-limit writes, diagnostic ordering and native wraparound.
Source special records, gem/extra hashes and internal research-sticker mappings
are recovered with instruction/table provenance. Follower creation retains the
original extra RNG word and seed flag, not a guessed profession from its unused
special-card field. Currency helpers and unit/name effects remain explicit pure
simulation services. Research composition is described below.
`source_rewards.gd` composes dispatch, queue and inventory against the same plain
state and the caller's shared source RNG; it owns no independent random stream.
Its optional observer receives detached arguments and cannot determine credit.
The 327-case/1,147-transition native comparison executes actual inventory helpers,
gem writes, totem increments and follower seed generation. All fourteen original
packs run through the actual dispatcher and admission/consumption routines; only
their selector result remains a controlled service. Restoring the composed state
between every transition verifies continued ownership, flags and RNG consumption.
The private campaign receives the recovered queue constants and special rows,
but this does not register missing source catalogs/domain services or publish it.

`source_card_research.gd` owns original advance eligibility, remaining research,
float32 progress, one-sticker assignment and completion against shared inventory.
`source_hash.gd` preserves the case-sensitive text hash and binary little-endian
card/sticker combination hash; it does not use the lowercase asset hash.
Derived research, combination and completion counters use the original limit
registration protocol, including its early return for an existing stock key.
Eligibility uses lifetime acquisition; actual assignment additionally requires an
unspent card and sticker. Ordered category slots retain first-match behavior,
including zero contributions. Failed later credits do not refund earlier writes.
Completion spends research and the card before granting its persistent completion
counter, then emits the original notification, cache invalidation, acquisition
and happiness-effect services in order. These services never depend on animation.
Queries can register counters, so presentation queries must run on detached state.
The native comparison executes actual map storage, hashes, lookups and inventory
helpers in 624 cases/4,920 transitions, including every recovered advance from
seven source scopes and restoration after every step. Legacy source rows whose
types are absent from the supplied executable enum remain explicitly unavailable.
The source reward composition can route automatic and manual research through
this implementation instead of host-supplied research stubs. Its research cache
flag persists with the same queue and inventory; older composed saves migrate
the missing flag. A separate 108-case/351-transition native comparison executes
the actual queue and research helpers together, including all 56 Homeworld6
advances. Formatting, notifications, happiness effects and unrelated domain
services remain adapters. Infrastructure injects source research definitions into
the private campaign. This does not port each completed advance's downstream
power/economy effect or replace the enabled compatibility campaign's card system.

When numeric selection rules are supplied, `source_rewards.gd` routes selector
queries to the same research and inventory state. Current era can come from the
source cache described below; older controlled callers can supply it as a pure
simulation service. The shared caller RNG also supplies every
weighted draw; fixed nonzero roll overrides consume no words. Infrastructure
binds original reward names to source hashes and retains source `Era Available`
values for the card selection gate. Sticker detail pointers are represented only
by their non-null predicate: the original binder supplies a fallback record
before resolving details, so this gate does not require rendering or art loading.
The supplied Homeworld6/Homeworld7 tables repeat `Card_Gems_50`; array scans keep
the original rows while registry lookups resolve the last registered row. The
special-resource table retains its separate first-match lookup semantics.
A 432-case/2,451-transition comparison executes original dispatch, selector,
research, queue and fixed-map inventory instructions together. It covers seven
source catalogs, all fourteen shared packs with actual special-resource rows,
research completion changing the next reward, duplicate registry entries and
restoration at every boundary. Input counters and current era are explicit
controlled state; this does not establish the full source startup registry,
era progression, currency/effect service internals or a complete campaign run.

`source_reward_catalog.gd` owns fresh pack/sticker/card registry construction,
source detail-row references and original zero-ID resets. It registers stock and
lifetime capacities in source group/row order. Packs and stickers use the original
99,999 limit; cards use the unsigned bits of their signed `Max Collectable`
column. Registration preserves earlier limits even when a later duplicate row
has another capacity; lookup binding still moves to the last row. Missing source
details retain the original non-null fallback as an index sentinel, without
loading an asset or manufacturing artwork. Infrastructure validates table/native
provenance and keeps startup catalogs with unresolved old enum types unavailable.
`source_rewards.gd` prepares the complete injected reward graph only after
validation, so a cyclic pack cannot partially register inventory. Supplied
definitions remain detached from bound output. A 71-case/142-binding comparison
executes the actual original binding block, resets, tree walks, hashing and
fixed-map insertion; only tree insertion/allocation is adapted. An additional
70-case/904-transition comparison passes those original registered records and
counters into the original reward pipeline, covering every Homeworld6 advance,
repeated acquisition limits and every shared pack. It uses two bounded CPU
instances across an explicit plain-data boundary, not the original application
entrypoint. Saved counter continuation is compared after each transition.
This establishes the reward registry pass, not the outer startup/job registries,
source-era cache, per-advance gameplay effects or a verified campaign playthrough.

`source_era.gd` owns the original dirty-cache refresh and sticker-era getter.
Period (`ERA_MASTER_%d`) and sticker era (`ERA_STICKER_%d`) remain separate
values. Descending scans preserve original query order and the valid-cache fast
path. A period change refreshes the global cache before emitting its notification,
including when a distinct local cache initiated the refresh. The shared reward
owner stores these fields beside the existing research-cache flag, which original
card completion invalidates. Research-only saves invalidate missing derived
values on first use; malformed half-present caches reject. Source-era inspection
must query detached state because it can refresh this cache and emit effect intents.
Infrastructure supplies original scan bounds/templates with provenance. The
259-case/1,035-query comparison executes the full native cache and actual hash-set
membership, adapting only string storage/formatting and period-change delivery.
The 15-case/98-transition reward comparison executes that cache inside original
selection/research/redemption. Authored Bronze/Iron completion invalidates and
refreshes Homeworld6's era; the Imperial advance exists in Homeworld7 and is
checked with explicit prior unlock input. Unlock-set population on acquisition
remains a controlled simulation service in this comparison. The native dependency
dispatcher now has the additional composition described below. Startup indices,
period effects and complete world-to-world progress transfer remain unported;
the cache alone cannot prove later-age campaign progression.

`source_unlock_dispatch.gd` owns original ordered dependency registration,
recursive propagation, immediate claims and temporary-claim deadlines. Source
phase-one duplicates may replace their phase; other phases retain it. Compound
hash activation can replay an earlier received condition, and phase-two rows
still propagate on repeated claims. Explicit frames preserve depth-first callback
order without a host call-stack limit. Acyclic definitions validate before
mutation; cyclic graphs would recurse indefinitely in the original and remain
unavailable. Bulk preparation preserves registration order and duplicate behavior
without revalidating the growing graph after each authored row.
Four distinct sets and first-seen timestamps retain the original fixed-capacity
behavior. Temporary claims are a separate table and do not enter received events
or first-seen timestamps. The native duration sentinel is minus one: zero is a
temporary claim too. Clocks are explicitly injected integer seconds and pairs of
millisecond words; no simulation wall clock is read. Remaining-time queries retain
the native unsigned subtraction and both explicit MSVCRT x87/SSE2 conversion modes,
including wrapped/expired results. This query is not an expiry/removal controller.
The separate original expiry/rebuild protocol is described below.
Infrastructure recovers all 1,182 authored dependency rows from seven scopes,
their separate achievement columns and all fifty dynamic-claim slots with byte/
table provenance. It never treats achievement names as release conditions.
A 155-case/931-transition comparison runs actual registration, string/binary
hashes, fixed-map insertion, recursive claims and timer arithmetic, with native
and simulation save continuation. Notification delivery, clocks and timer-tree
allocation are adapters. Source startup sets, CSV/achievement callbacks and the
notification service's internal temple/advance effects remain separate work.

The same simulation owner now runs original persistent-claim rebuild and
temporary-claim expiry. Rebuild invokes modifier undo and configuration reset
before clearing all four sets, retains first-seen times, and replays bucket heads
in ascending bucket order with newest entries first within each chain. Explicit
persisted insertion order reproduces that traversal after save/load; older saves
migrate their existing dictionary order without changing timestamps. The replay
iterator can observe later bucket heads inserted by a simulation service. All
dependency phases reset to one only after persistent replay. Definitions that
would become cyclic after that reset reject before any effect or mutation.
Expiry compares full unsigned millisecond words, removes at most one due timer
in key order, rebuilds persistent claims and reapplies all remaining timers.
Other already-due timers remain active until later updates remove them; forced
refresh follows the same rebuild without requiring expiry. An 89-case/403-transition
comparison executes the actual rebuild, expiry, claim helpers and tree traversal,
with native and simulation saved continuation. Timer-tree storage, explicit clocks
and modifier/configuration reset internals are adapters; those reset services
must be supplied by simulation domain owners, never by presentation.

`source_rewards.gd` can own this dispatcher beside its shared inventory, queue,
research context and era cache. Acquisitions and completed-card claims execute
the dispatcher against that same persisted state; era scans read its actual
unlocked set. Missing/bad clock inputs reject before inventory mutations. Source
definitions are injected into the private campaign but do not initialize or
replace the compatibility campaign's startup on their own. An additional
79-case/638-transition comparison executes actual acquisition wrappers, unlock
propagation, research, reward selection, queue redemption and era refresh together.
It needs no supplied acquisition-to-unlock mapping and verifies save continuation,
all researched advances in Homeworld6/7, source temple-completion keys, Homeworld6
Bronze/Iron and Homeworld7's distinct Imperial advance. Notifications, unrelated
currency/unit/effect services and outer startup remain explicit adapters; this
does not establish complete campaigns or the downstream behavior of each power.
An additional six-case/116-transition comparison runs expiry and forced rebuilds
inside that same reward/research/inventory/era owner, including all ten authored
temporary claims and both current campaign catalogs. Research progress, stock,
shared RNG and cache state continue through repeated refresh and restoration.
The reward context validates its complete inputs once before mutation; internal
acquisition callbacks reuse that validated context rather than rebuilding the
dependency validation graph for every automatic research sticker.

Authored temple descriptors retain their original scope, IDs, positions,
optional height, rotation, model chain, worker caps, resource costs and reward.
Infrastructure resolves only recovered assembled models and keeps ambiguous
duplicate IDs unavailable. The private Homeworld6 snapshot now owns its 27
authored records. Presentation uses exact source centers/heights for these
records; compatibility sites keep their earlier registration. It selects the
corresponding supplied 2.4 power/expansion shrine class for legacy site names.
The dormant, repairing and completed renderers share the same site anchor;
authored heights use the snapshot's sea level. Completed component batches
invalidate when their resolved transforms change. Legacy site inspection resolves
the same source class without requiring saved simulation data to be rewritten.
Missing assembled content cannot start repair and never receives a tent stand-in.
Temple repair charges site food/ore and uses its worker cap; it never charges
the house belief cost. Simulation owns one-time completion, the original
`TEMPLE_COMPLETE_` unlock predicate and site inspection, including required
resources and arrived builders.
Selecting a map site opens its recovered type-specific illustration, localized
title and description without starting repair. A separate builder action submits
the ordinary validated repair command. Started and completed sites retain their
site identity for live inspection, including while paused; fractional work comes
from the authoritative temple accumulator rather than rounded construction ticks.
Version-nine migration updates models/caps
and initializes source work without repaying costs or discarding saved CSV repair
time and job progress. Temple work retains its own float32 seconds accumulator;
the original worker/skill arithmetic uses `Config.templeFixerFalloff` from
Update.csv, independently of ordinary abode construction. Reload preserves work
and rescaling a repair duration preserves its completion fraction.
`source_temple_repair.gd` separately owns original affordability, raw repair start
and the work/completion protocol. Phases five, six and seven mean ready, working
and complete. Pure simulation services supply ordered payment, hooks, type
queries, Ark action requests, reference effects, notifications and deferred reward
flags. Presentation cannot satisfy these services or grant inventory. The native
comparison covers 236 cases and save restoration. The enabled compatibility
campaigns use the verified work arithmetic with their existing arrived-worker
assignment; that assignment is not the original follower dispatcher. Full native
temple jobs, footprint/burial transitions, special temple behaviors, reference
effect internals, other temple-specific reward paths and activation effects remain unported;
recovering placements does not enable the private campaign.
The original deferred Temple of Discovery branch runs before that temple's work
update. `source_temple_repair.gd` owns its pending/ready flag clearing and unlock
ordering, then submits the current reward and source ID to the shared temple
wrapper. It reloads both values after the unlock callback, as the original does.
It imposes no invented phase/reward-presence gate and cannot repeat a consumed
pending grant after restoration. Seventy-four native comparisons compose the
actual branch, discovery type predicate, wrapper and dispatcher, adapting final
credit and presentation services. This does not enable other special temple
reward paths or the private campaign's unported worker/lifetime dispatcher.
The completion-marker wrapper (`0x1015cd60`) now composes actual inventory limit
registration, claim dispatch and final credit. It rejects only the source
registered-but-not-unlocked gate, registers one-unit limits before dispatch, and
returns true even when the later credit fails. Repeated markers may notify again;
the temple's consumed pending flag supplies its one-time reward protection.
`source_rewards.gd` routes deferred discovery completion through this wrapper and
the same queue/research/era state. A further 59-case/242-transition comparison
executes the original marker wrapper and deferred branch together with actual
inventory and dependency helpers, covering all 27 Homeworld6 marker IDs and all
fourteen shared packs. Saved temple flags and reward state continue together.
Clock/RNG/typed-reward validation occurs before pending flags can be cleared.
Other temple kinds, source worker execution, full activation effects and the
notification service's temple/configuration changes remain separate work.
The pre-work obstruction/decay state block now lives independently in
`source_temple_terrain.gd`. It preserves the native blocked phase, conversion
between repair work and decay time, restored phases and removal requests.
The three original expansion-shrine classes use their recovered 60-second
duration; other classes use four seconds. Simulation emits effect/audio service
intents and clears released audio handles without consulting presentation.
The adapter injects executable-verified constants into the private campaign.
312 bounded native comparisons and 32 continuation steps cover these decisions
and saves at each sequence boundary. `source_temple_footprint.gd` now owns the
original scan bounds, half-up rounding, strict height tolerance and row-major
sample order. Its injected query reads raw terrain steps. A further 162 native
scans, 56 composed transition cases and 96 continuation steps verify that actual
terrain obstruction drives blocked/restored work without a controlled count.
`source_temple_frame.gd` composes that scan with the earlier worker-presence
ramp, passive repair increment, forced-decay clock, cooldown, native height cap,
boat height override and upward motion. It preserves spatial-refresh ordering
and emits downward motion requests to an explicit simulation service. A further
276 native cases and 96 continuation steps cover the contiguous pre-work frame.
The same class composes that frame with `source_temple_repair.gd`: 99 further
native cases and 48 continuation steps execute terrain transitions, elevation
and actual worker/completion instructions together. Completion sound positions
use the newly updated authoritative height. Both names for native slot +0x3c4
must agree before composition, and invalid work totals reject before advancing
terrain. The original timed settlement-affiliation pass, spatial registration,
downward interpolation and final removal remain separate caller dependencies;
this lifecycle is not enabled by the compatibility repair loop.
`source_temple_membership.gd` separately owns the original timed affiliation
pass. It preserves strict deadline comparison, both clock reads, seeded random
consumption, source active-list order and last-containing-settlement ownership.
Its direct circular and inherited spherical range checks retain their distinct
boundaries and float storage points. 191 geometry cases, 101 affiliation cases
and 64 restored sequence steps compare actual native instructions. The original
type-radius column is injected by infrastructure. Modifier refresh and active
pool ownership remain explicit services; full lifecycle composition is pending.
Map rendering now reconciles dormant site models, source completion stages and
streamed visibility on snapshots. Picking requires displayed source geometry;
unavailable or removed saved sites cannot retain old meshes or invisible click
targets. Completed construction batches keep their existing selection anchors.
The compatibility director fills existing shrine jobs and queues affordable,
clear, reachable shrine repairs before new housing. It uses the recovered site
dimensions rather than shelter dimensions, reserves approach space and keeps
authored elevation fixed. Covering trees, rocks and ordinary buildings intercept
shrine picking; buried terrain reaches sculpting. Original clearing powers take
priority over inspection and validate the selected covering house ID. Saved
repair footprint migration preserves progress and payment while releasing stale
worker targets for normal reassignment. This does not implement the private
campaign's unported native follower dispatcher.
Pure simulation validates research spending and owns community membership,
specialized construction, field work, carried harvest, delivery and resource
collection. Snapshots expose derived sticker counts for galleries; presentation
does not calculate payment or mutate research. A source animation or audio cue
cannot complete construction, harvest or delivery. Versioned content migration
preserves saved CSV balance alongside mutable economy and reward state.

Currency milestone intervals and tribe happiness are simulation snapshots.
The HUD draws the original atlas regions and positions the markers from those
values. Corner background opacity, layout and number abbreviation belong to
presentation. Happiness currently includes source starting values and passive
decay; this does not implement Astari festivals or full tribal society.

Terrain topology, surface height, valid building plots and follower routes are
simulation data. Godot meshes, collision shapes and navigation visualizations
are derived views. Gameplay must remain correct with those views absent or
still rebuilding after an edit. Physics-based picking can help map input to a
cell; it does not establish authoritative buildability or reachability.

Save/load adapters serialize versioned simulation state, including tick,
random-generator state, terrain, entity IDs, resources, progression and any
queued commands required by the chosen save boundary. Restore a simulation
before recreating its views. Camera and UI preferences are separate presentation
settings. SQLite is accessed through adapters, never from simulation rules.

## Verification

`python3 -m unittest discover -s tests -v` checks the current directory and
dependency boundaries, including known scene/device/I/O APIs and resource
paths. The check is a dependency lint, not a full GDScript type checker;
reviews must preserve these contracts for new APIs as well.

As gameplay is added, headless simulation tests must cover commands, rejected
commands, detached snapshot ownership, and save/load round trips without
instantiating presentation. The same seed, initial state and ordered commands
must produce the same state after the same tick count regardless of render
rate. Rendering and audio get separate integration checks. Asset validation
remains in `game/tests/validate_assets.gd`.

## Example world and navigation

`simulation/example_layout.gd` receives model IDs, categories and source bounds
as plain data. It assigns every usable source record one non-overlapping plot
and returns detached category regions and item positions. It reads no assets
and creates no scene nodes. Unresolved material records are explicitly excluded.
Application obtains descriptors from infrastructure and injects layout data and
a model-resolving callable into presentation.

`presentation/world/example_world.gd` streams actual source meshes around the
camera. Loading, culling, model inspection and UI cannot change layout ownership
or gameplay state. Model placement in the playable scenario is a validated
simulation command, persists plain model IDs/positions, and derives render nodes.

`plane_surface.gd` provides base coordinates and a local tangent frame. The
example camera uses that frame for orbit and pan, preserving its offset from
the base during navigation. It does not follow terrain heights. Only the plane
mapping exists; spherical and toroidal mappings remain future work.

`tools/check_game.py` runs Python checks and all Godot integration suites,
including every usable mesh, exhibit coverage/clearance, camera invariants,
original rig/clip/audio import, terrain gestures and SQLite continuation.
Each check receives a fresh `DOMINUS_SAVE_DIRECTORY`; the infrastructure save
path adapter redirects default world, voyage and entitlement files there. This
keeps automated front-end/reward checks independent of the player's saved world.
Normal runs retain their existing save locations.


## Presentation streaming

Application freezes a detached copy of static scenery once per loaded world.
Later snapshots reuse that immutable array; mutable simulation state still gets
copied at each boundary. Terrain height arrays use copy-on-write value semantics.
Tree positions and variants also stay shared while a sparse, detached removal
mask records player clearing. Simulation rejects obstructed construction and
owns clearing taps/rewards; a shared immutable cell index lets query owners
validate the same plots without copying the forest. The renderer invalidates
only the affected tree tile, retaining pending invalidations across snapshots.
Presentation builds terrain mesh arrays on a worker thread from detached height
data, then installs mesh resources on the main thread. Tile caches and detail
levels affect rendering only. Workers never access live simulation objects.
Tree instancing reuses recovered source meshes and materials.

Runtime map manifests load packed tree/rock byte fields and a small shared
opening-rule table; unused gem/plot-rotation object dictionaries stay in offline
provenance rather than runtime memory. Simulation expands only dry tree cells
for the older campaigns. The private source opening uses recovered native initial
instances instead, preserving fractional positions and sampled dry coastal trees
whose integer root is water.
Model metadata is loaded independently of the full media-library catalog and
sealed once by infrastructure. Simulation seals its own plain model definitions
and rule tables recursively. Snapshots/query copies share only those immutable
tables; mutable entities remain detached. Reconfiguration replaces a complete
immutable rule version, so prior snapshots keep the old one.

Simulation caches derived occupancy, navigation topology, reservations and
house specifications. Successful geometry/house commands and restore/reload
invalidate the relevant caches. These caches do not alter authoritative state,
RNG use, route neighbor order or save continuation.

The recovered 2.4 card catalog contains text/path metadata, never eagerly loaded
illustrations. Presentation requests small source-derived thumbnails only when
they intersect the visible gallery, and a full crop for the detail view.
Closing/scrolling releases references. Weak caches do not pin textures in memory.

## Runtime preferences and balance

`infrastructure/settings_store.gd` reads/writes JSON preferences and validates
against `config/settings.defaults.json`. Application applies presentation/device
preferences and scheduler speed; the settings tree receives detached definitions
and values. Saved simulations retain no camera nodes or UI objects.

`infrastructure/unit_tables.gd` reads wide Adobes.csv and Followers.csv unit
columns. `infrastructure/live_constants.gd` reads remaining Update.csv keys and
combines all three into typed plain-data changes,
accepting desktop spreadsheet delimiters without executing formulas. Application
calls `World.reconfigure` between fixed ticks. Simulation validates a complete
candidate first, then commits atomically, refreshes progression/influence, and
adjusts active build timers while preserving completion fractions. This does
not advance ticks or RNG. Rule tables and runtime rates persist as simulation
data; preferences and CSV paths do not. Existing plot footprints remain stable.
Cooperative construction aggregates arrived workers after their movement and
advances each building once using the source count exponent and job skills.
The pure work arithmetic is independently compared with the original CPU case;
animation callbacks do not contribute work or complete a building. The exponent
is a reloadable abode CSV value, not a JSON presentation preference.
The JSON transport preserves floating-point IEEE-754 bits using a versioned
plain-data encoding, avoiding decimal parser rounding across Godot and Python
for deterministic movement continuation after SQLite reload. Legacy numeric
JSON saves remain readable.

Interactive sessions schedule fixed-tick batches on one application-owned worker.
Only that worker touches the authoritative world until application joins a
completed batch; the rendering thread keeps the last detached snapshot and a
separately owned query copy. Commands arriving during a batch are staged for the
next boundary. Save/load, balance reload and new-world transitions join the
current boundary first. The synchronous driver remains available for headless
checks and deterministic playback. Worker completion never calls presentation.

Presentation streams persistent scenery batches instead of recreating all trees
and rocks after camera movement. Completed source building components batch by
model/material while lifecycle/detail assemblies retain their individual parts.
Source follower mesh/skin resources are shared; pose sampling can slow for tiny
figures without slowing their interpolated movement. Source tree-imposter art
and recovered atlas rectangles provide distant tree rendering. Terrain merges
coplanar caps and samples the height field more coarsely at distant zoom levels;
this changes presentation geometry only, never simulation terrain or picking.
