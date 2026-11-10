# Source campaign research and economy

`python3 -m tools.campaign_rules` recovers the supplied 2.4 research, sticker,
population, grain, ore, unlock, house, temple and job records. Its manifest is
`game/assets/original/campaign/research-rules.json`. Each table and the containing
archive retain SHA-256 evidence. Executable float defaults retain initializer,
value, name and configuration-slot addresses; authored CSV values override them.
Seven original setup scopes are preserved separately. They have not yet been
registered to the eight large-map campaigns. Additional runtime research now
uses `initialworldsetup6`, which matches the supplied 2.4 video milestones.
The older opening/map/influence bridge still needs replacement by the original
scope-specific story; changing research does not establish that registration.

The existing playable opening retains its component contracts. Additional
advances use the original typed research requirements. Matching source stickers
contribute their actual points, including rare stickers. Wrong types, absent
stock, undiscovered cards and already completed cards reject without spending.
The last contribution activates a supported advance. Unported advances remain
unavailable even when their artwork and research requirements are recovered.
Prayer now keeps its own original portrait instead of aliasing Generate Belief.

The supported additional advances include Builder Settlement, Farming Settlement,
Mining Settlement, Super Fast Building and Advanced Farming. Farming is discovered
at 165 followers and Mining at 550 followers in setup6; both have zero sticker
requirements, and their original power gates activate on discovery. Wheat and
ore spending have separate source gates. Super Fast Building enables wheat
spending and applies the source 0.1 build-time multiplier. Advanced Farming uses
its original 1.5 production multiplier across all six source field ranks.
The scope7 Crop Rotation and Superior Pickaxes effects are also implemented;
Weyworld campaign/Ark registration and transition remain incomplete.
Select the corresponding original power in the powers
gallery and click a completed abode. The simulation groups nearby eligible
abodes under one community, charges its source placement cost and enforces the
source population limit. Original town-centre and profession-statue models mark
the settlement. Clicking it collects delivered wheat, ore and member belief;
otherwise it sends an available worker to a reachable nearby plot.

Farmers and miners construct original field/mine assemblies. Their jobs retain
the source construction times, plot sizes, harvest limits and production formula
documented in the source house table:

```
production per second = Max Belief * Belief Modifier
```

The specialized worker must actually reach the field, work, harvest and return
to a member abode's entrance before resources become collectable. Resource
transport is authoritative simulation state, not an animation callback. Farm
and mine plots do not breed followers, generate belief or upgrade as abodes.
Wheat and ore construction costs come from the source house rows and activate
through the corresponding source spending unlocks. Collected resources discover the corresponding
source grain/ore research milestones. Original male body, profession components,
tools, wheat and selected source clips present the job; only active professions
load these resources.

`python3 -m tools.shaders` extracts 74 original shader records, exact vertex and
fragment text, and retained parameter payloads. The healthy crop shader ports
the original alpha tint mask, grain/pumpkin colors, ripeness curve and direct
diffuse/ambient lighting from `shdrCropsGrain`. Per-field growth is MultiMesh
instance data; harvest does not rebuild building batches. Blight/beautify crop
branches, fog and original crop vertex deformation remain unported. Original
worker body/tool meshes share resources across follower IDs.

Research points, spent stickers, settlement membership, stored harvest, field
work and carried resources persist in the ordinary SQLite world. Content
migration preserves saved CSV values and prior rewards. Reloading CSV balance
preserves field identity and construction progress instead of applying abode
statistics to fields.

## Remaining fidelity work

This is not complete original campaign progression. Settlement geometry
compression, expanding/merging communities, breeder/buffer assignment, worker
fatigue, the full source biome rules and all settlement upgrades still need
ports and original-game comparison. Current communities preserve the existing
abode layouts. Automatic deployment now chooses the largest reachable, affordable
source field or mine footprint; clearing more flat space makes larger plots viable.
The newly recovered economy unit rows still need integration with the three
OpenOffice tables. Later card effects, original campaign story registration,
Astari society, the Ark and the endgame remain incomplete.

`test_campaign_economy.gd` uses a clearly controlled flat map with source rules.
It checks typed research, real construction/harvest/transport, wheat-to-mining
unlocking, resource costs, detached snapshots, deterministic continuation,
SQLite, malformed membership rejection and saved-balance migration. The mining
unlock fixture uses original quantified wheat rewards to reach its threshold;
it does not establish a full campaign playthrough. Native capture uses a
separate build profile and save, never the player's campaign.
`test_economy_interface.gd` additionally applies an earned sticker through the
real gallery, selects the original power, places a settlement through world
input and sends a farmer out through the same click controls as normal play.
`test_render_batches.gd` checks separate crop growth values on the native GPU
backend and shared source meshes across worker IDs; its headless run checks
batch ownership/reuse but cannot read GPU custom data from the dummy renderer.

`test_production_advances.gd` additionally checks runtime scope6 milestones,
zero-cost cards, real research spending, the worker's next production tick,
source multipliers and stacking, construction timers, resource gates and
deterministic migration. Its high-population scope7 preconditions are controlled
fixtures, not a completed Weyworld campaign.

Trees and standing rocks obstruct new and enlarged building footprints. Trees
are cleared explicitly by the player, not consumed as timber by construction.
The original tree tap count and belief values come from the current balance and
map-object table. A sparse saved removal mask prevents regrowth after demolition
or load; tree position/variant data and the query index remain shared immutable
data. Only the affected scenery tile rebuilds on removal. Legacy scenery already
hidden under old houses migrates as cleared, without granting another reward.

Selected abodes now expose a the original game-style selection row and Info window, using
source illustrations, localization, icons, pale panel artwork and dotted rules.
Read-only simulation queries supply the existing resident/capacity values,
construction/worker progress, belief capacity/rate and next scheduled birth;
farm/mine queries expose their worker/harvest values, and settlement queries
aggregate their member buildings and stored cargo. These numbers describe the
currently implemented economy; they do not establish complete original housing,
breeder/worker allocation or native follower lifetimes. No missing stat is
replaced with an invented original-game value. Selection no longer automatically
upgrades an abode: the available upgrade is an explicit selection-row action.
The building integration check covers selection without mutations, live tick
updates, exact-number restoration, detached threaded queries and resized layout.

Both card galleries route resource research into the same simulation owner.
Locked powers link to their recovered prerequisite advance, including when
viewed from the powers book. Current source power IDs override legacy spellings
for presentation commands. Supported power gates now consult source unlock
conditions as well as the legacy table, preserving discovery-versus-completion
semantics. `test_card_completion_ui.gd` spends earned sticker aliases on actual
larger-abode/digging upgrades, completes typed settlement research from the powers
view, restores the world and creates a real farming settlement through its card.
Unsupported effects remain unavailable; this is not a full-catalog parity claim.

The referenced 2.4 resource-assignment sequence (3:47–3:53) and the supplied
`OBJ_TimelineSticker_Slot.as` / `OBJ_Card.as` show a bottom resource strip,
dragged sticker previews, application to advance portraits, stock depletion and
on-card progress. The galleries now expose that interaction on both gallery and
detail portraits. Valid drop previews show prospective progress; cancelling or
rejecting a drop cannot spend resources. Source sticker artwork remains on the
card after assignment. Resource advances complete on their final assignment,
without a separate completion button; zero-resource advances retain their
existing claim action. The current gallery layout is still not the complete
original animated chronology screen.

Typed research retains original per-type sticker contributions. Existing saves'
component recipes additionally retain partial, card-owned assignments, so moving
one resource cannot pay another card or charge again on completion. The source
commands and backwards-compatible claims share the same remaining-recipe query.
Chest reward weighting now excludes already-provided components. Historical spent
assignments remain valid when a live CSV edit removes or reduces a requirement;
they contribute only against the current recipe. The UI integration check drives
real viewport drags, verifies invalid previews, partial assignment and SQLite
restoration, then finishes digging and a settlement advance. Compatibility
completion after partial payment and malformed saved counts are checked separately.

The private Homeworld6 source port additionally follows the original initial
trees' dirty-terrain response (`0x10260e90`). Nonzero sampled ground differing
from the original planted height disables a tree and clears its plot-block bit;
matching height (or the original routine's raw-zero special case) re-enables it.
The spatial identity and planted Y remain unchanged. This temporary suppression
does not award clearing belief or erase a permanently cleared tree. Source
configuration and instruction provenance are in `tree-response.json`.
`native_tree_response_oracle.py` executes the original dirty scan, occupancy bit
loops and null-growth-record scale helper: seven controlled terrain cases and
162 size cases. Runtime tests cover ordinary sculpt commands, detached queries,
SQLite continuation, migration and existing near/far render instances. These
checks do not establish runtime density regeneration, planted tree growth,
underwater initial tree destruction or full campaign availability.

Cooperative construction now advances once per building after follower movement.
The original `New builder contribution` column controls the count exponent:
working builders raised to that exponent, multiplied by their average job skill.
Four workers at exponent 0.5 contribute twice one worker's work. Walking followers
do not contribute, and builders retain the building state at their work positions.
Completion releases the whole team at the same simulation boundary. Fractional
work persists through save/load. Version-seven content migration supplies absent
source exponents while preserving saved CSV timers, capacities and work progress.
The added `New Builder Contribution` column in `config/Adobes.csv` reloads through
the existing three-table control; existing columns and values are preserved.

`tools.native_construction_oracle` captures the supplied x86 construction case
at `0x100bdaa2`, including its native count/skill lookups and power function.
Only resolved unit lookup and Lua notification delivery use adapters. Twelve
controlled cases cover zero/one/multiple workers, different count and contributor
inputs, nonuniform skills, exponents and speed factors. The pure work accumulator
matches these captures. This does not establish original follower assignment,
stamina, every repair state, or a complete campaign. The current campaign adapter
uses tick-based progress and arrived-worker groups; full native reaction/pool
membership and the private Homeworld6 first-abode stage remain unported.

## Storm chest recovery

The current runtime has fixed campaign chests and voyage rewards. It still lacks
the original storm-end replenishment loop, which is a real resource scarcity
gap. `tools/storm_chests.py` preserves the archive/executable hashes, source area
tables, original native routines and numeric configuration. Three source scopes
provide explicit `maxStormChests`, `maxDepth` and `maxTotalChests` columns. Older
schemas remain unavailable here until their loader behavior is verified.

`source_storm_chests.gd` now ports the original refill budget (`0x10168d00`),
disk sampler (`0x1019f2c0`) and generation batch (`0x10153030`). Chests whose
native authored ID is zero and which lie strictly inside an area count toward
its total cap. Counts are taken once for
the whole pass, including locked areas and overlaps; newly generated chests do
not change those counts during the pass. Forced, unlocked or activated areas
draw a bounded spawn count. Placement consumes its random words before the next
area draws. Sampling uses up to the source `MaxRandPosChecks` attempts; failed
placement consumes no burial-depth word. Source burial selection rounds
`U * (maxDepth + 1)` by adding one half and flooring, preserving its endpoint
bins. Even zero/negative requested counts retain the native collection setup and
release order. No new art, weather effects or reward types are synthesized.

The isolated original CPU comparisons cover 53 refill cases, 10 disk samples
and 15 generation batches, including boundaries, overlap, lock/activation gates,
authored IDs, opening phases, caps, retries, zero counts, depth rounding and intervening random
consumption. They adapt spatial candidate acceptance and chest construction;
they do not prove the full placement predicate, source constructor, storm
scheduling, offline weather behavior or renewable chests in a played campaign.
The authored campaign infrastructure injects the recovered limits as plain data;
the remaining original services must be ported before enabling the runtime loop.

The candidate predicate (`0x101521e0`) now has a separate pure port in
`source_chest_placement.gd`. It retains both original category/restriction gates,
rounded coordinate conversion, sampled-height thresholds and separate
`DeepWaterSculpt`/`HighMountainSculpt` gates. Source ordinary scenery footprints
use rounded bounds; building footprints use floor/ceiling bounds, a minimum
half-size and the native free-corner exception. Resolved special buildings also
block the strict interior of their extra circle. The explicit native debug
override affects only the high-mountain gate. Custom authored scenery membership
remains a simulation callback; unresolved shapes block placement, without box
stand-ins. Two hundred thirteen original CPU cases verify these decisions and
their field/ground/unlock/custom-query order. The actual field storage, ground
provider and custom authored shapes are explicit inputs to that comparison.

The factory protocol (`0x10152ed0`) is ported in `source_chest_factory.gd`.
Allocation failure stops before sampling or RNG use. It classifies the buried
step height against the source water boundary and `ChestLev2`/`ChestLev3`, then
applies `StorySpawnOdds` (compiled 0.5, with no current archive override). Story
chests select native kind 4 and `RandomStory`; ordinary chests select
`Reward_RandomStickerOrGem`. This chooses an original reward identifier, not an
invented sticker reward. The core constructor runs before generated source-ID/reward
assignment, followed by notification at the constructor's actual stored position.
Forty-three original CPU cases verify type boundaries, story probability,
allocation failure, constructor RNG ordering and changed final positions.
Source story/sticker/gem redemption and storm scheduling still need
their runtime implementations before these protocols can replenish a campaign.

`source_chest_constructor.gd` now implements the numeric constructor state from
`0x101523c0`. It samples ground separately from the factory's classification
query, subtracts the source depth times height scale, clamps the result to the
source minimum and stores both current/base height. It preserves kind, rotation,
the initialized numeric source slots and the original spatial registration
intent. Registration uses the native truncated-coordinate endpoint rules. The
buried-effect interval consumes one CRT word after spatial registration and uses
the original `TimeBetweenBuriedTreasureVFXMin`/`Max` bounds. Numeric initialization
leaves source ID and reward identifier to the factory. Render resources,
matrices and particle playback remain presentation responsibilities.

The complete original constructor executes in 106 controlled comparisons,
adapting renderer/resource factories, ground storage, random words and spatial
index insertion. Seven more comparisons execute the actual factory and
constructor together. They verify two random words per successful factory
creation, the independent ground samples, final notification position and no
construction after allocation failure. Headless checks validate exact numeric
save-codec round trips, detached restored records, matching spatial ownership,
rejection of malformed saved values and continuation of the injected RNG.
These checks do not establish chest opening/disappearance transitions, custom
scenery membership, source reward redemption or storm scheduling. The runtime
renewable loop remains disabled until those services are available.

The field distinction is retained explicitly in recovered `field_layout`
metadata: the authored loader at `0x102617a1` writes the reward-chest `ID` into
offset `0x04`, while opening at `0x10152adc` writes phase one into `0x60` and
resets elapsed time at `0x58`. Storm budgeting reads the ID, not the opening
phase. Thus an opening/opened generated chest still counts until it is removed;
an authored nonzero-ID chest does not consume that cap. The native comparisons
include both cases. No runtime adapter may map the old campaign's `opened`
boolean into this source-ID field.

`source_chest_lifetime.gd` ports exposure (`0x101520c0`), raw opening
(`0x10152a30`) and the complete pool lifetime loop (`0x10153370`). Exposure uses
the active sculpt sample when present, otherwise the source ground query, with
the original strict height margin. The ordinary command checks influence and
closed phase before opening. Repeated player input cannot restart a timer;
direct invocation of the raw original helper retains its reset behavior.
Opening emits the source animation/notification intents, increments the original
counter and awards expedition chest score only in mission mode three. The
score request preserves the original four-word position record.

Fixed simulation steps retain the native height-following blend and strict
opening/disappearance comparisons. Phase one changes to two before reward
dispatch, so that grant cannot repeat after restoring. Reward availability is
queried through an explicit service; unavailable/zero identifiers fall back to
`Reward_ChestSticker`. The `CHEST_BONUS_1` gate is queried after the first reward
grant and before its explicit unlock; qualifying rewards can then dispatch
`Reward_BonusChestSticker`. The original
mode-one sentinel and mode-two service branch remain distinct. This port does
not interpret mode two as four sticker grants. Destruction unregisters spatial
ownership, marks the native source ID removed and releases the pool entry in
order. Numeric closed/influence/story totals follow the original whole-pool pass.

The original routines execute across 44 cases and 68 transitions. Ground/sculpt,
influence, animation intents, reward/progression services and storage insertion
or release are adapters; timers, height response, gates, destructor ID writes and
pool traversal execute original instructions. Headless checks repeat every case
with save/restore between every transition, verify a single reward transition
through that boundary and validate rejected duplicate identities or malformed state. They
also exercise the ordinary opening command. Actual reward availability
(`0x10001600`), reward redemption (`0x100514f0`), custom scenery shapes and storm
scheduling remain unported dependencies of the renewable runtime loop. Lifecycle
dispatch tests do not prove sticker selection or a complete played campaign.
