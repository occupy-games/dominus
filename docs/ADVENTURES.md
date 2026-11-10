# Original the original game voyages

Open **Adventures · Voyages by boat**, select an island and Bronze, Silver or
Gold, choose the boat’s followers, and set sail. Sculpt a route, avoid champions
and swamps, restore shrines, and use the island’s available powers to reach the
goal before its timer expires. Pinch to zoom, pan with two fingers and hold
Shift to change the viewing angle.

The supplied content yields 213 non-test mission records. **205 islands have
usable authored terrain, with 615 difficulty variants.** The other eight are
an obsolete Free Sculpt tutorial and seven older Halloween missions whose
supplied map revisions have no land at their authored landing or goal points.
They remain disabled with a source-recovery explanation; no replacement island
is generated. Packed, loose and downloaded stream revisions are recorded per
chunk. Two stale map references use identifiable supplied revisions: the
explicit EventMap_05_Legacy pack and the matching corrected Meteor Barrage
record in event_03a. Original coordinates remain unchanged.

`python3 -m tools.adventures` rebuilds source crops, metadata, compiled scripts
and reward rules under `game/assets/original/adventures/`. Crops are exact
source cells, without resampling. The catalog preserves archive, pack, source
member and stream-chunk SHA-256 hashes, crop origins, and native executable
configuration addresses. Binary archive members retain significant trailing
zero bytes. Text CSV/Lua members alone drop their terminator padding.

The original Lua is parsed offline into bounded, serializable instructions.
`simulation/voyage_script.gd` interprets those instructions without a scene,
assets, I/O, wall clock or general code execution. `voyage_challenges.gd` ports
the challenge APIs: scheduled callbacks, conditional ambushes, stamina and
combat, blight/swamp fields, purification, meteor deformation, shrine repairs,
power locks, chests, and influence changes. Timers, positions, conditions,
race statistics, power costs, shrine radius and speed multipliers come from
the supplied tables/scripts. The source’s optional missing tooltip coordinates
and undefined callbacks are retained as source quirks; they do not acquire
invented challenge actions. Unsupported gameplay calls report an error.

Arrival scoring follows `godus.s86:100f44dc..100f453f`:

```
truncate(base * (1 + time_multiplier * limit * pow(remaining / limit, time_power)))
```

Intermediate single-precision stores and the native default time power of two
are preserved. This replaces the introductory prototype’s linear bonus. The
original executable has not been rebuilt: the combat and meteor transitions
are simulation ports, and unsupported original particle effects have no
procedural visual replacement.

Score tracks use the original `rewarddata.csv` thresholds. Older missions use
their authored per-star rewards. Packs expand using `packdata.csv`, and sticker
IDs, eras and contributions use `stickerdata.csv`. Event sticker era weights and
the random/useful split are recovered from the native reward generator at
`1004e2ee..1004e552` and its configuration initializers. Randomness is explicit
and the reward RNG state persists. Replaying a victory or improving a score
cannot re-award an already claimed threshold or star.

Reward entitlements are atomically written to `saves/voyages.json` before
Homeworld receives them. Each Homeworld saves cumulative redeemed quantities
with its inventory in SQLite. Returning, restarting, or loading a voyage can
therefore retry delivery without duplicating a reward. Canonical the original 2.4 source
stickers appear in Homeworld’s Resources gallery and satisfy the corresponding
existing card requirements. Spending deducts the sticker, and reapplying the
reward profile does not restore it. Resource cards grant their original
quantities; gem stickers add gems. The Homeworld session waits during a voyage.
Existing introductory voyage saves migrate to the source-script configuration.

Presentation uses the original champion and wolf meshes and selected clips,
assembled shrines/obelisks and speed symbols, animated boats and chests, and the
original swamp gradient over simulation-owned fields. Large script definitions
are immutable and shared across detached snapshots. Only the current island’s
power images and actor clips load.

Headless checks cover all 615 variants at startup, shrine triggers, scheduled
callbacks and restore; this is not a claim that every puzzle has been won by
self-play. Introductory self-play uses actual geometry commands. Reward checks
complete the first island with eight passengers, receive its Wooden Carving
and Animal Furs rewards, spend Animal Furs on the Homeworld Tents card, then
verify restart/load deduplication. Native captures exercise challenge visuals,
the reward panel and the Homeworld Resources gallery using isolated test saves.

The user-supplied `game/assets/dominus.png` brands the menu, start controls,
boot splash and game icon. `python3 tools/logo.py` packages its resized copies
as `dominus.icns`; `dominus-logo.json` records provenance. This explicit user
logo and the requested Roboto Condensed font are exceptions to source-only art.
