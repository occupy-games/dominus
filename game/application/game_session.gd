extends Node
## Fixed-tick scheduling and persistence coordination; presentation gets copies.

signal changed(snapshot: Dictionary, events: Array)

const World = preload("res://simulation/world.gd")
const Store = preload("res://infrastructure/world_store.gd")
var world := World.new()
var tutorial_home: RefCounted
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


func new_world(world_seed: int = 2026) -> void:
	finish_worker()
	tutorial_home=null
	staged_commands.clear()
	world = World.new()
	var random := RandomNumberGenerator.new()
	random.seed = world_seed
	world.initialize({"world_seed": world_seed, "models": model_definitions}, random)
	paused = false
	accumulator = 0.0
	refresh_queries()


func new_campaign(definition: Dictionary) -> void:
	finish_worker()
	tutorial_home=null
	staged_commands.clear()
	world = World.new()
	var config := definition.duplicate(true)
	config["models"] = model_definitions
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	world.initialize({"campaign_data": config, "models": model_definitions}, random)
	paused = false
	accumulator = 0
	refresh_queries()


func begin_leash_lesson() -> bool:
	finish_worker()
	if tutorial_home!=null or not presentation_snapshot().get("opening",{}).get("leash_mission_pending",false): return false
	var source:=preload("res://infrastructure/leash_lesson_content.gd").definition()
	if source.is_empty(): return false
	tutorial_home=world
	world=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"leash_lesson":source,"models":model_definitions},random)
	staged_commands.clear()
	accumulator=0.0
	refresh_queries()
	return true


func return_from_leash_lesson() -> bool:
	finish_worker()
	if tutorial_home==null or not world.snapshot(false)["won"]: return false
	world=tutorial_home
	tutorial_home=null
	staged_commands.clear()
	accumulator=0.0
	var events:=world.step([{"type":"campaign_leash_lesson_completed"}])
	refresh_queries()
	changed.emit(presentation_snapshot(),events)
	return true


func finish_first_voyage(won: bool) -> void:
	finish_worker()
	var command:={"type":"campaign_first_voyage_returned","won":won}
	if not world.inspect(command)["ok"]: return
	var events:=world.step([command])
	refresh_queries()
	changed.emit(presentation_snapshot(),events)


func sail_ark() -> Dictionary:
	finish_worker()
	var crew:=world.ark_manifest()
	if crew.is_empty(): return {"ok":false,"message":"The Ark is not ready to sail."}
	var destination:=preload("res://infrastructure/campaign_content.gd").map_definition("homeworld7")
	if not destination.has("arrival"): return {"ok":false,"message":"The original Weyworld arrival data is unavailable."}
	destination["ark_passengers"]=crew
	destination["ark_research"]=world.ark_research()
	var next:=World.new()
	var rng:=RandomNumberGenerator.new()
	rng.seed=2026
	next.initialize({"campaign_data":destination,"models":model_definitions},rng)
	var target:=Store.new()
	target.database_path=preload("res://infrastructure/save_paths.gd").weyworld()
	var home_saved:=store.save_world(world.export_state())
	if not home_saved.get("ok",false): return home_saved
	var saved:=target.save_world(next.export_state())
	if not saved.get("ok",false): return saved
	world=next
	store=target
	staged_commands.clear()
	accumulator=0
	refresh_queries()
	return saved


func submit(command: Dictionary) -> void:
	if threaded: staged_commands.append(command.duplicate(true))
	else: world.queue_command(command)


func inspect(command: Dictionary) -> Dictionary:
	return query_world.inspect(command) if threaded and query_world!=null else world.inspect(command)


func inspect_building(id: Variant,entity: String="home") -> Dictionary:
	return query_world.inspect_building(id,entity) if threaded and query_world!=null else world.inspect_building(id,entity)


func find_edge(x: float, z: float, layer: int, cliff: bool=false) -> Dictionary:
	return query_world.find_edge(x,z,layer,cliff) if threaded and query_world!=null else world.find_edge(x,z,layer,cliff)


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
	var result := world.snapshot(false)
	scenery_snapshot=world.shared_trees()
	result["trees"] = scenery_snapshot
	return result


func _process(delta: float) -> void:
	if threaded: advance_threaded(delta)
	else: advance_elapsed(delta)


func save_game(path: String = "") -> Dictionary:
	finish_worker()
	if tutorial_home==null:
		for command: Dictionary in staged_commands: world.queue_command(command)
	staged_commands.clear()
	var target := Store.new()
	target.database_path=path if not path.is_empty() else store.database_path
	var result := target.save_world((world if tutorial_home==null else tutorial_home).export_state())
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
	var opening: Dictionary=saved.get("opening",{})
	var needs_chest: bool=opening.get("promised_step") in [7,8,9] and not opening.get("definition",{}).has("first_chest")
	var needs_timeline: bool=not opening.is_empty() and not opening.get("definition",{}).has("timeline_steps")
	var needs_housing: bool=not opening.is_empty() and not opening.get("definition",{}).has("mud_hut")
	var needs_shrine: bool=not opening.is_empty() and not opening.get("definition",{}).has("first_shrine_id")
	var needs_belief: bool=not opening.is_empty() and not opening.get("definition",{}).has("belief_steps")
	var needs_discovery: bool=not opening.is_empty() and not opening.get("definition",{}).has("discovery_site_id")
	var needs_leash: bool=not opening.is_empty() and not opening.get("definition",{}).has("leash_population_card")
	var needs_dock: bool=not opening.is_empty() and not opening["definition"].get("constants",{}).has("FIRST_VOYAGE_RETURN")
	var needs_farming: bool=not opening.is_empty() and (not opening["definition"].has("farming_population_card") or not opening["definition"].has("housing_advances") or not opening["definition"].has("sticker_advances") or not opening["definition"].get("source_chest_stickers",false))
	var needs_storms: bool=not opening.is_empty() and not opening["definition"].has("storm_timing")
	var needs_pack_chests: bool=not opening.is_empty() and not opening["definition"].has("authored_pack_chests")
	var needs_environment: bool=not opening.is_empty() and not opening["definition"].has("environment_advances")
	var needs_grain: bool=not opening.is_empty() and (not opening["definition"].has("grain_building_card") or not opening["definition"].has("grain_advances") or not opening["definition"].has("mining_core") or not opening["definition"].has("stone_abodes"))
	var needs_ark: bool=not opening.is_empty() and not opening["definition"].get("ark",{}).has("sail_labels")
	var needs_gem_prices: bool=not opening.is_empty() and not opening["definition"].has("construction_gems")
	var needs_pit: bool=not opening.is_empty() and not opening["definition"].has("pit_sacrifice")
	var needs_rain: bool=not opening.is_empty() and not opening["definition"].has("rain")
	var needs_fountain: bool=not opening.is_empty() and not opening["definition"].has("fountain")
	var needs_mud_lodge: bool=not opening.is_empty() and not opening["definition"].has("mud_lodge")
	var stone_abodes: Dictionary=opening.get("definition",{}).get("stone_abodes",{})
	var needs_later_housing: bool=not opening.is_empty() and (not opening["definition"].has("beach_lodge") or not stone_abodes.has("StoneHouse_Rank_3") or not stone_abodes.has("StoneHouse_Rank_4"))
	var needs_cliff: bool=not opening.is_empty() and not opening["definition"].get("cliff_sculpt",{}).has("upgrades")
	var needs_later_powers: bool=not opening.is_empty() and (not opening["definition"].has("underwater_sculpt") or not opening["definition"].has("capacity_shrine") or not opening["definition"].has("swamp") or not opening["definition"].has("meteor") or not opening["definition"].has("speed_shrine") or not opening["definition"].has("settlement_upgrades"))
	var needs_belief_advances: bool=not opening.is_empty() and (not opening["definition"].has("rock_belief") or not opening["definition"].has("belief_collector"))
	var needs_god_seed: bool=not opening.is_empty() and not opening["definition"].has("god_seed")
	var needs_finger: bool=not opening.is_empty() and not opening["definition"].has("finger_of_god")
	var needs_raids: bool=not opening.is_empty() and not opening["definition"].has("astari_raids")
	var needs_village: bool=not opening.is_empty() and not opening["definition"].has("astari_village")
	var needs_core_stats: bool=not opening.is_empty() and not opening["definition"].get("farming_core",{}).has("belief_modifier")
	if needs_ark or needs_gem_prices or needs_belief_advances or needs_god_seed or needs_finger or needs_raids or needs_village or needs_core_stats or needs_cliff or needs_later_powers or needs_mud_lodge or needs_later_housing or needs_fountain or needs_rain or needs_pit or needs_grain or needs_farming or needs_storms or needs_pack_chests or needs_environment or needs_dock or needs_leash or needs_discovery or needs_belief or needs_shrine or needs_housing or needs_timeline or opening.get("phase")=="promised_land" and (opening.get("promised_step") in [3,6,9,10] and not opening.get("handoff",{}).get("available",true) or needs_chest):
		var content := preload("res://infrastructure/campaign_content.gd").for_state(saved)
		if content.has("story"): candidate.resume_opening_handoff(content["story"])
	candidate.prepare_loaded_opening()
	if saved.has("voyage") and preload("res://infrastructure/adventure_content.gd").for_state(saved).is_empty():
		return {"ok":false,"message":"Original voyage island data is unavailable."}
	if saved.has("voyage") and int(saved["voyage"]["definition"].get("script_version",0))<1:
		candidate.migrate_voyage(preload("res://infrastructure/adventure_content.gd").for_state(saved))
	if saved.has("campaign") and not saved.has("voyage") and not saved.has("opening") and int(saved.get("progression",{}).get("rules",{}).get("version",0))<preload("res://simulation/progression.gd").RULES_VERSION:
		var content := preload("res://infrastructure/campaign_content.gd").for_state(saved)
		if content.is_empty(): return {"ok":false,"message":"Original campaign map data is unavailable."}
		candidate.migrate_progression(content["progression_rules"],content["rock_field"])
	if saved.get("progression",{}).get("rules",{}).get("registered_scope")=="initialworldsetup7" and not saved.has("weyworld"):
		var content:=preload("res://infrastructure/campaign_content.gd").for_state(saved)
		if content.has("progression_rules"): candidate.install_weyworld_tutorial(content["progression_rules"].get("weyworld",{}))
	if saved.has("campaign") and not saved.has("voyage") and not saved.has("opening") and (not saved.has("rock_heights") or int(saved.get("rock_density_version",0))<1):
		var content := preload("res://infrastructure/campaign_content.gd").for_state(saved)
		if content.is_empty(): return {"ok":false,"message":"Original campaign map data is unavailable."}
		candidate.migrate_rocks(content["terrain"],content["rock_field"])
	world = candidate
	tutorial_home=null
	store=target
	world.set_model_definitions(model_definitions)
	accumulator = 0.0
	paused = false
	staged_commands.clear()
	refresh_queries()
	return {"ok": true}


func apply_constants(changes: Array) -> Dictionary:
	finish_worker()
	var target := world if tutorial_home==null else tutorial_home
	var result: Dictionary=target.reconfigure(changes)
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
	latest_snapshot=world.snapshot(false)
	scenery_snapshot=world.shared_trees()
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
	var snapshot:=world.snapshot(false)
	snapshot["trees"]=world.shared_trees()
	return {"snapshot":snapshot,"query":world.query_copy(),"events":events,"usec":Time.get_ticks_usec()-started}


func finish_worker(publish: bool = true) -> void:
	if not worker.is_started(): return
	var result: Dictionary=worker.wait_to_finish()
	query_world=result["query"]
	latest_snapshot=result["snapshot"]
	scenery_snapshot=latest_snapshot["trees"]
	last_batch_usec=result["usec"]
	# Always publish a completed boundary, including when paused. No simulation
	# writes are allowed until this thread hands ownership back to application.
	if publish: changed.emit(presentation_snapshot(),result["events"])


func _exit_tree() -> void:
	finish_worker(false)
