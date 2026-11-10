extends SceneTree

const World = preload("res://simulation/world.gd")
const Session = preload("res://application/game_session.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func make_world() -> RefCounted:
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	world.initialize({"world_seed": 2026}, random)
	return world


func buildable(world: RefCounted) -> Dictionary:
	for z in range(10, 24):
		for x in range(10, 24):
			var command := {"type": "home", "x": x, "z": z}
			if world.inspect(command)["ok"]:
				return command
	return {}


func run() -> void:
	var world := make_world()
	# Grab a real shoreline edge, preview without mutation, then extend one layer.
	var edge: Dictionary = world.find_edge(16, 3, 1)
	check(edge.get("ok", false), "A shoreline layer must expose a grabbable edge")
	var sculpt := edge.duplicate(true)
	sculpt.merge({"type": "sculpt_drag", "distance": 1, "radius": 0}, true)
	var untouched: Dictionary = world.export_state()
	var preview: Dictionary = world.inspect(sculpt)
	check(preview.get("ok", false) and world.export_state() == untouched, "Layer preview must leave state and RNG unchanged")
	world.step([sculpt])
	check(world.snapshot()["sculpted"] == 1 and world.snapshot()["belief"] == 80 - int(preview.get("cost", 0)), "A layer drag must atomically charge its exact edit cost")
	for edit: Dictionary in preview.get("edits", []):
		check(world.snapshot()["terrain"][edit["cell"]] == 1, "Extending a shoreline must keep the grabbed layer height")
	var retract := sculpt.duplicate(true)
	retract["x"] += int(edge.get("nx", 0))
	retract["z"] += int(edge.get("nz", 0))
	retract["distance"] = -1
	world.step([retract])
	check(world.snapshot()["terrain"] == untouched["state"]["terrain"], "Retracting the extended shoreline must restore its geometry")
	var detached: Dictionary = world.snapshot()
	detached["terrain"][500] = 7
	detached["followers"][0]["x"] = -99
	check(world.snapshot()["followers"][0]["x"] >= 0 and world.snapshot()["terrain"][500] != 7, "Snapshots must be detached")
	var before: Dictionary = world.snapshot()
	var events: Array = world.step([{"type": "home", "x": 0, "z": 0}])
	check(events[0]["type"] == "rejected" and world.snapshot()["belief"] == before["belief"] and world.snapshot()["homes"].is_empty(), "Rejected actions must not spend belief or create entities")
	var command := buildable(world)
	check(not command.is_empty(), "Starting followers must have reachable building plots")
	world.step([command])
	check(world.snapshot()["homes"].size() == 1, "Valid construction must reserve a home")
	var home: Dictionary = world.snapshot()["homes"][0]
	check(not world.inspect({"type": "lower", "x": home["x"], "z": home["z"]})["ok"], "Sculpting must protect occupied plots")
	# Force a retract sweep toward this occupied plot; validation must roll back all cells.
	var protected_before: Dictionary = world.snapshot()
	var blocked_edge: Dictionary = world.find_edge(home["x"], home["z"], world.height_at(home["x"], home["z"]))
	if blocked_edge.get("ok", false):
		var blocked: Dictionary = blocked_edge.duplicate(true)
		blocked.merge({"type": "sculpt_drag", "distance": -8, "radius": 2}, true)
		if not world.inspect(blocked)["ok"]:
			world.step([blocked])
			check(world.snapshot()["terrain"] == protected_before["terrain"] and world.snapshot()["belief"] == protected_before["belief"], "Rejected sculpt sweeps must be atomic")
	for i in range(250):
		world.step()
	check(world.snapshot()["completed_homes"] == 1, "A follower must reach the plot and finish building")
	check(world.inspect({"type": "sheep", "x": 16, "z": 16})["ok"], "A completed home must unlock sheep")
	world.step([{"type": "sheep", "x": 16, "z": 16}, {"type": "collect"}])
	check(world.snapshot()["sheep"].size() == 3 and world.snapshot()["collected"] > 0, "Sheep spawning and collecting belief must affect simulation")
	var exported: Dictionary = world.export_state()
	var clone := World.new()
	var json_round_trip: Dictionary = JSON.parse_string(JSON.stringify(exported))
	check(clone.restore(json_round_trip, RandomNumberGenerator.new()), "Versioned JSON state must restore")
	for i in range(200):
		world.step()
		clone.step()
	check(world.export_state() == clone.export_state(), "Restored RNG and state must continue deterministically")
	check(not clone.restore({"schema_version": 99}, RandomNumberGenerator.new()), "Unknown save versions must be rejected")
	var store := Store.new()
	store.database_path = "/private/tmp/dominus-test-world-%d.sqlite3" % OS.get_process_id()
	var saved := store.save_world(exported)
	check(saved.get("ok", false), "SQLite save must succeed: " + str(saved))
	var loaded := store.load_world()
	check(loaded.get("ok", false) and loaded.get("data", {}).get("state", {}).get("tick") == exported["state"]["tick"], "SQLite must round-trip simulation data")
	DirAccess.remove_absolute(store.database_path)
	# Different frame schedules, same tick count: scene and renderer are never created.
	var a := Session.new()
	var b := Session.new()
	a.new_world()
	b.new_world()
	for i in range(200):
		a.advance_elapsed(0.05)
	for i in range(50):
		b.advance_elapsed(0.2)
	check(a.world.export_state() == b.world.export_state(), "Rendering schedule must not affect simulation")
	a.free()
	b.free()
	# Complete the objective using the same player commands as the UI.
	for i in range(2):
		command = buildable(world)
		check(not command.is_empty(), "The island must support three reachable homes")
		if not command.is_empty():
			world.step([command])
	for i in range(300):
		world.step()
	world.step([{"type": "collect"}, {"type": "sheep", "x": 16, "z": 16}, {"type": "sheep", "x": 16, "z": 17}])
	check(world.snapshot()["won"], "Player must be able to finish the sanctuary objective")
	print("Simulation and SQLite integration: %d failures" % failures)
	quit(1 if failures else 0)
