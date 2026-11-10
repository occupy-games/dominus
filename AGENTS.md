# Dominus architecture

Read `docs/ARCHITECTURE.md` before implementing gameplay.

- All art, models, textures, fonts, animation, music and sound effects must come
  from `data/godus2_4/`. Do not create replacement assets or procedural stand-ins.
  Preserve source provenance when converting. Leave unsupported content unavailable.
  Runtime terrain deformation and UI layout are implementation, not new art assets.

- Keep authoritative state, game rules, terrain topology, follower decisions,
  navigation decisions, resources, and progression in `game/simulation/`.
- Simulation GDScript extends `RefCounted` and uses plain data and value types.
  It must run without a scene tree, renderer, audio device, input devices, assets,
  database, or wall clock. Pass configuration and a seeded RNG explicitly.
- Put Godot nodes, scenes, meshes, shaders, camera, picking, UI, animation,
  audio, and visual interpolation in `game/presentation/`.
- Put coordination in `game/application/` when needed. It translates input to
  commands, advances simulation at fixed ticks, and hands detached snapshots
  and events to presentation. Presentation never mutates simulation state.
- Keep SQLite and filesystem access in infrastructure adapters; persist
  simulation data, never the presentation scene tree.
- Run `python3 -m unittest discover -s tests -v` after architectural changes.
  Add headless simulation tests as gameplay is introduced.
