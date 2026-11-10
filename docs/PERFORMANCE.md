# Memory and CPU check

Measured locally with Godot 4.8.beta2 on the same saved 66-follower Homeworld
and `game/tests/profile_memory.gd`. These are one-run headless measurements of
Godot-managed memory and fixed-work elapsed time, not total process RSS, GPU
memory, frame rate or a guarantee for every map/population. MB means 1,000,000
bytes. Raw records are `build/memory-before.json` and `build/memory-after.json`.

| Workload | Before | After |
| --- | ---: | ---: |
| Main-menu managed memory | 888 MB | 150 MB |
| Campaign managed memory | 1,108 MB | 233 MB |
| Peak managed memory during this run | 3,111 MB | 367 MB |
| Campaign opening | 3,464 ms | 373 ms |
| 60 detached snapshot/query pairs | 161 ms | 43 ms |
| 60 populated fixed ticks | 2,717 ms | 707 ms |

Runtime map loading no longer parses the million-entry plot-rotation JSON
field, expands submerged scenery, or copies the complete map provenance to
each consumer. The original field bytes, height hashes and offline provenance
remain intact. Model metadata loads separately from the full media library.
Rule/model tables are recursively immutable and shared across detached query
copies. Occupancy, reservation, route-topology and house-specification caches
are invalidated at changes rather than rescanned for every candidate cell.

Card metadata is independent of texture residency. In the native rendering
check, the 2.4 advances, resources and powers galleries held 9–12 visible card
images at a time and released all gallery illustrations when closed. Only small
source-derived thumbnails are used in the grid; one full original image is
used for the detail view. `test_current_cards.gd` also verifies bounded residency
after scrolling and closing galleries.

The full check covers fixed-tick determinism, threaded ownership, terrain
drags, continued campaign growth, SQLite continuation, live CSV reload,
navigation and all source model/animation playback checks. Native screenshots
are in `build/screenshots/cards-24-*.png`.
