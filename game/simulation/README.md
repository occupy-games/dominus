# Simulation boundary

`world.gd` owns the fixed-tick terrain, followers, construction, belief,
progression, validated model placement and versioned detached state.
`example_layout.gd` deterministically lays out injected usable model descriptors
by category, source group and component family without accessing assets.

Both extend `RefCounted` and use plain data and explicit inputs. Nodes, scenes,
resource loading, input, rendering, audio, databases and wall clocks stay outside
this directory. See [architecture](../../docs/ARCHITECTURE.md).
