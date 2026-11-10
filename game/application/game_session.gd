extends Node
## Fixed-tick scheduling and persistence coordination; presentation gets copies.

signal changed(snapshot: Dictionary, events: Array)

const World = preload("res://simulation/world.gd")
const Store = preload("res://infrastructure/world_store.gd")
var world := World.new()
var store := Store.new()
var threaded := false
var worker := Thread.new()
var query_world: RefCounted
var latest_snapshot: Dictionary = {}
var staged_commands: Array = []
var last_batch_usec := 0
var paused := false
var speed := 1.0
var accumulator := 0.0
var model_definitions: Dictionary = {}
var scenery_snapshot: Array = []
var scenery_cached := false


func new_world(world_seed: int = 2026) -> void:
	finish_worker()
	staged_commands.clear()
	world = World.new()
	var random := RandomNumberGenerator.new()
	random.seed = world_seed
	world.initialize({"world_seed": world_seed, "models": model_definitions}, random)
	scenery_cached = false
	paused = false
	accumulator = 0.0
	refresh_queries()


func new_campaign(definition: Dictionary) -> void:
	finish_worker()
	staged_commands.clear()
	world = World.new()
	var config := definition.duplicate(true)
	config["models"] = model_definitions
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	world.initialize({"campaign_data": config, "models": model_definitions}, random)
	scenery_cached = false
	paused = false
	accumulator = 0
	refresh_queries()


func submit(command: Dictionary) -> void:
	if threaded: staged_commands.append(command.duplicate(true))
	else: world.queue_command(command)


func inspect(command: Dictionary) -> Dictionary:
	return query_world.inspect(command) if threaded and query_world!=null else world.inspect(command)


func inspect_building(id: Variant,entity: String="home") -> Dictionary:
	return query_world.inspect_building(id,entity) if threaded and query_world!=null else world.inspect_building(id,entity)


func find_edge(x: float, z: float, layer: int) -> Dictionary:
	return query_world.find_edge(x,z,layer) if threaded and query_world!=null else world.find_edge(x,z,layer)


func advance_elapsed(delta: float) -> void:
	finish_worker()
	if not staged_commands.is_empty():
		for command: Dictionary in staged_commands: world.queue_command(command)
		staged_commands.clear()
	if paused:
		return
	accumulator += minf(delta, 0.5) * speed
	var events: Array = []
	var ticks := 0
	while accumulator + 0.000001 >= World.TICK_SECONDS and ticks < 20:
		events.append_array(world.step())
		accumulator -= World.TICK_SECONDS
		ticks += 1
	if ticks > 0:
		refresh_queries()
		changed.emit(presentation_snapshot(), events)


func presentation_snapshot() -> Dictionary:
	if threaded and not latest_snapshot.is_empty(): return latest_snapshot.duplicate(false)
	# Scenery is static simulation data. Freeze a detached copy once; it can be
	# shared safely by later snapshots without copying thousands of dictionaries.
	if not scenery_cached:
		scenery_snapshot = world.snapshot()["trees"]
		for tree: Dictionary in scenery_snapshot: tree.make_read_only()
		scenery_snapshot.make_read_only()
		scenery_cached = true
	var result := world.snapshot(false)
	result["trees"] = scenery_snapshot
	return result


func _process(delta: float) -> void:
	if threaded: advance_threaded(delta)
	else: advance_elapsed(delta)


func save_game(path: String = "") -> Dictionary:
	finish_worker()
	for command: Dictionary in staged_commands: world.queue_command(command)
	staged_commands.clear()
	var target := Store.new()
	target.database_path=path if not path.is_empty() else store.database_path
	var result := target.save_world(world.export_state())
	if result.get("ok",false): store=target
	return result


func load_game(path: String = "") -> Dictionary:
	finish_worker()
	var target := Store.new()
	target.database_path=path if not path.is_empty() else store.database_path
	var result := target.load_world()
	if not result.get("ok", false):
		return result
	var candidate := World.new()
	if not candidate.restore(result.get("data", {}), RandomNumberGenerator.new()):
		return {"ok": false, "message": "The saved world is incompatible or invalid."}
	var saved := candidate.snapshot(false)
	if saved.has("voyage") and preload("res://infrastructure/adventure_content.gd").for_state(saved).is_empty():
		return {"ok":false,"message":"Original voyage island data is unavailable."}
	if saved.has("voyage") and int(saved["voyage"]["definition"].get("script_version",0))<1:
		candidate.migrate_voyage(preload("res://infrastructure/adventure_content.gd").for_state(saved))
	if saved.has("campaign") and not saved.has("voyage") and not saved.has("opening") and int(saved.get("progression",{}).get("rules",{}).get("version",0))<preload("res://simulation/progression.gd").RULES_VERSION:
		var content := preload("res://infrastructure/campaign_content.gd").for_state(saved)
		if content.is_empty(): return {"ok":false,"message":"Original campaign map data is unavailable."}
		candidate.migrate_progression(content["progression_rules"],content["rock_field"])
	if saved.has("campaign") and not saved.has("voyage") and not saved.has("opening") and (not saved.has("rock_heights") or int(saved.get("rock_density_version",0))<1):
		var content := preload("res://infrastructure/campaign_content.gd").for_state(saved)
		if content.is_empty(): return {"ok":false,"message":"Original campaign map data is unavailable."}
		candidate.migrate_rocks(content["terrain"],content["rock_field"])
	world = candidate
	store=target
	scenery_cached = false
	world.set_model_definitions(model_definitions)
	accumulator = 0.0
	paused = false
	staged_commands.clear()
	refresh_queries()
	return {"ok": true}


func apply_constants(changes: Array) -> Dictionary:
	finish_worker()
	var result := world.reconfigure(changes)
	if result.get("ok",false):
		refresh_queries()
		changed.emit(presentation_snapshot(),[])
	return result


func receive_voyage_rewards(profile: Dictionary, rules: Dictionary) -> Dictionary:
	finish_worker()
	var result := world.receive_voyage_rewards(profile,rules)
	refresh_queries()
	return result


func refresh_queries() -> void:
	query_world=world.query_copy()
	if not scenery_cached:
		scenery_snapshot=world.snapshot()["trees"]
		for tree: Dictionary in scenery_snapshot: tree.make_read_only()
		scenery_snapshot.make_read_only()
		scenery_cached=true
	latest_snapshot=world.snapshot(false)
	latest_snapshot["trees"]=scenery_snapshot


func advance_threaded(delta: float) -> void:
	if worker.is_started() and not worker.is_alive(): finish_worker()
	if paused: return
	accumulator+=minf(delta,0.5)*speed
	if worker.is_started() or accumulator+0.000001<World.TICK_SECONDS: return
	var ticks := mini(4,floori((accumulator+0.000001)/World.TICK_SECONDS))
	accumulator-=ticks*World.TICK_SECONDS
	var commands := staged_commands
	staged_commands=[]
	worker.start(advance_batch.bind(ticks,commands))


func advance_batch(ticks: int,commands: Array) -> Dictionary:
	var started := Time.get_ticks_usec()
	for command: Dictionary in commands: world.queue_command(command)
	var events: Array=[]
	for tick in range(ticks): events.append_array(world.step())
	return {"snapshot":world.snapshot(false),"query":world.query_copy(),"events":events,"usec":Time.get_ticks_usec()-started}


func finish_worker(publish: bool = true) -> void:
	if not worker.is_started(): return
	var result: Dictionary=worker.wait_to_finish()
	query_world=result["query"]
	latest_snapshot=result["snapshot"]
	latest_snapshot["trees"]=scenery_snapshot
	last_batch_usec=result["usec"]
	# Always publish a completed boundary, including when paused. No simulation
	# writes are allowed until this thread hands ownership back to application.
	if publish: changed.emit(presentation_snapshot(),result["events"])


func _exit_tree() -> void:
	finish_worker(false)
