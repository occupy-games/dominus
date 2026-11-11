extends RefCounted
## Authoritative fixed-tick world. All coordinates and decisions are plain data.

const TICK_SECONDS := 0.1
const Immutable = preload("res://simulation/immutable_data.gd")
const BUILD_TICKS := 60
const HOME_COST := 12
const SHEEP_COST := 8
const Progression = preload("res://simulation/progression.gd")
const Influence = preload("res://simulation/influence.gd")
const Voyage = preload("res://simulation/voyage.gd")
const Economy = preload("res://simulation/campaign_economy.gd")
const Research = preload("res://simulation/research.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
const LeashLesson = preload("res://simulation/leash_lesson.gd")
const CampaignLeash = preload("res://simulation/campaign_leash.gd")
const Farming = preload("res://simulation/campaign_farming.gd")
const Ark = preload("res://simulation/campaign_ark.gd")
const Weyworld = preload("res://simulation/weyworld.gd")
const Pit = preload("res://simulation/campaign_pit.gd")
const Rain = preload("res://simulation/campaign_rain.gd")
const Fountain = preload("res://simulation/campaign_fountain.gd")
const Cliff = preload("res://simulation/campaign_cliff_sculpt.gd")
const Collector = preload("res://simulation/campaign_belief_collector.gd")
const Beautify = preload("res://simulation/source_beautify.gd")
const AbodeBeauty = preload("res://simulation/campaign_abode_beauty.gd")
const LandEffectTimer = preload("res://simulation/source_land_effect_timer.gd")
const SourceRaster = preload("res://simulation/source_influence.gd")
const MAX_HEIGHT := 63
const DIRECTIONS := [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
var _state: Dictionary
var _random: RandomNumberGenerator
var _pending: Array = []
var _models: Dictionary = {}
var _dry_land := 0
var _route_cache: Dictionary = {}
var _blocked_cells: Dictionary = {}
var _navigation_stamp := 0
var _component_of: Dictionary = {}
var _plan_reserved: Dictionary = {}
var _plan_stamp := -1
var _spatial_revision := 0
var _blocked_stamp := Vector2i(-1,-1)
var _house_specs: Dictionary = {}
var _tree_cells: Dictionary = {}
var _tree_coast: Dictionary = {}
var _tree_rows: Dictionary = {}
var _tree_tiles: Dictionary = {}
var _rock_visibility_stamp := Vector2i(-1,-1)
var _rock_visibility := PackedByteArray()


func initialize(config: Dictionary, random: RandomNumberGenerator) -> void:
	_random = random
	var width := clampi(int(config.get("width", 34)), 20, 64)
	_state = {"width": width, "tick": 0, "terrain_revision": 0, "belief": 80,
		"collected": 0, "next_id": 1, "terrain": [], "followers": [], "sheep": [],
		"homes": [], "trees": [], "removed_trees":{}, "tree_taps":{}, "vegetation_revision":0, "props": [], "won": false, "sculpted": 0, "world_seed": config.get("world_seed", 2026)}
	set_model_definitions(config.get("models", {}))
	_pending.clear()
	_route_cache.clear()
	_component_of.clear()
	_blocked_cells.clear()
	_plan_stamp=-1
	_navigation_stamp=0
	_spatial_revision=0
	_blocked_stamp=Vector2i(-1,-1)
	_house_specs.clear()
	_rock_visibility_stamp=Vector2i(-1,-1)
	_dry_land = 0
	if config.has("leash_lesson"):
		LeashLesson.setup(self,_state,config["leash_lesson"])
		_index_trees()
		return
	var center := (width - 1) / 2.0
	for z in range(width):
		for x in range(width):
			var distance := Vector2(x - center, z - center).length() + sin(x * 0.45) * 0.65 + cos(z * 0.38) * 0.65
			var height := 0
			if distance < width * 0.16:
				height = 4
			elif distance < width * 0.25:
				height = 3
			elif distance < width * 0.33:
				height = 2
			elif distance < width * 0.41:
				height = 1
			_state["terrain"].append(height)
			if height > 0: _dry_land += 1
	for offset in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]:
		_state["followers"].append(_agent(int(center) + offset.x, int(center) + offset.y, false))
	for offset in [Vector2i(-4, 1), Vector2i(3, 1)]:
		_state["sheep"].append(_agent(int(center) + offset.x, int(center) + offset.y, true))
	for z in range(2, width - 2):
		for x in range(2, width - 2):
			if height_at(x, z) > 0 and Vector2(x - center, z - center).length() > 5.5 and _random.randf() < 0.065:
				_state["trees"].append({"x": x, "z": z, "variant": _random.randi_range(0, 2)})

	if config.has("campaign_data"): _initialize_campaign(config["campaign_data"])
	_index_trees()


func set_model_definitions(definitions: Dictionary) -> void:
	_models = Immutable.freeze(definitions.duplicate(true))


func _agent(x: float, z: float, animal: bool) -> Dictionary:
	var agent := {"id": _state["next_id"], "x": float(x), "z": float(z), "path": [],
		"state": "idle", "wait": _random.randi_range(5, 35), "job": -1, "variant": 0}
	_state["next_id"] += 1
	if animal:
		agent["variant"] = _random.randi_range(0, 4)
	else:
		agent["race"]="Brown Head"
		var stats := follower_values(agent)
		agent["max_health"]=float(stats.get("MaxHealth",100))
		agent["health"]=agent["max_health"]
		agent["scale"]=float(stats.get("Scale",1))
	return agent


func snapshot(include_scenery: bool = true) -> Dictionary:
	var result := detached_state(include_scenery)
	if _state.has("opening"):
		result["opening"]["cliff_status"]=Cliff.status(_state)
		result["opening"]["collector_status"]=Collector.status(_state)
		var shrine_claims: Array=[]
		for site: Dictionary in _state["progression"]["shrines"]:
			if site.get("repaired",false) and not site["complete"] and _validate({"type":"campaign_activate_shrine","id":site["id"]})["ok"]:
				shrine_claims.append(site["id"])
		result["opening"]["shrine_claims"]=shrine_claims
		var pit_clips: Dictionary=_state["opening"]["definition"].get("pit_sacrifice",{}).get("clips",{})
		for follower: Dictionary in result["followers"]:
			if not follower.has("sacrifice_due"): continue
			var ticks:=ceili(float(pit_clips[follower["state"]])/TICK_SECONDS)
			follower["sacrifice_elapsed"]=minf(float(pit_clips[follower["state"]]),float(ticks-int(follower["sacrifice_due"])+int(_state["tick"]))*TICK_SECONDS)
		if _state["opening"].has("chests"):
			var chests := preload("res://simulation/authored_chests.gd").new()
			chests.configure(self,_state,[])
			result["progression"]["chests"]=chests.snapshot()
		var rocks := preload("res://simulation/authored_rocks.gd")
		var stamp := Vector2i(_state["terrain_revision"],_state["progression"]["rock_revision"])
		if stamp!=_rock_visibility_stamp:
			_rock_visibility=rocks.visibility(_state)
			_rock_visibility_stamp=stamp
		result["authored_rocks"]=rocks.entries(_state)
		result["source_rock_cells"]=_state["opening"]["definition"]["rock_cells"]
		result["source_rock_visibility"]=_rock_visibility.duplicate()
		var growing := Opening.supports_growth(_state["opening"]) or Opening.supports_timeline_housing(_state["opening"]) or Opening.supports_shrine_housing(_state["opening"]) or Opening.supports_discovery(_state["opening"])
		if Opening.supports_expansion(_state["opening"]) or growing:
			var ready: Array=[]
			for home: Dictionary in _state["homes"]:
				if _validate({"type":"sprog","home_id":home["id"]})["ok"]: ready.append(home["id"])
			result["opening"]["sprog_homes"]=ready
		if growing: result["opening"]["growth_plots"]=promised_growth_plots().duplicate(true)
		if CampaignLeash.enabled(_state):
			result["opening"]["leash_controls"]=_state["opening"]["definition"]["leash_rules"]
			var leash_homes: Array=[]
			for home: Dictionary in _state["homes"]:
				if not Opening.release_candidate(_state,int(home["id"])).is_empty(): leash_homes.append(home["id"])
			result["opening"]["leash_homes"]=leash_homes
	var completed := _completed_homes()
	if _state.has("weyworld"): result["weyworld"]=Weyworld.presentation(_state)
	result["completed_homes"] = completed
	result["happiness"] = mini(100, 50 + _state["sheep"].size() * 3 + completed * 5)
	if result.has("progression"):
		result["currency_metrics"]=preload("res://simulation/hud_metrics.gd").snapshot(_state)
		if _state.has("opening") and Opening.supports_level_card(_state["opening"]):
			var population := int(_state["opening"]["definition"]["growth_population_card"]["population"])
			result["currency_metrics"]["followers"]={"amount":_state["followers"].size(),"previous":0,"next":population,"progress":1.0}
		result["tribe_happiness"]=result["progression"].get("happiness",preload("res://simulation/happiness.gd").initial(result["progression"]["rules"])).duplicate(true)
		result["happiness"]=roundi(float(result["tribe_happiness"]["player"])*100)
		if _state.has("opening") and not preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"Happiness"):
			result.erase("tribe_happiness")
		result["progression"]["sticker_counts"]={}
		for sticker: String in result["progression"]["rules"].get("stickers",{}): result["progression"]["sticker_counts"][sticker]=Research.stock(_state["progression"],sticker)
		for sticker: String in result["progression"]["rules"].get("sticker_aliases",{}).values():
			if not result["progression"]["sticker_counts"].has(sticker): result["progression"]["sticker_counts"][sticker]=Research.stock(_state["progression"],sticker)
		result["progression"]["resource_counts"]={}
		result["progression"]["card_progress"]={}
		for id: String in result["progression"]["discovered"]: result["progression"]["card_progress"][id]=Research.status(_state["progression"],id)
		for card: Dictionary in result["progression"]["rules"]["cards"].values():
			for resource: String in card["requirements"]:
				result["progression"]["resource_counts"][resource]=Progression.resource_count(_state["progression"],resource)
	return result


func inspect_building(id: Variant,entity: String="home") -> Dictionary:
	if entity==Collector.KIND: return Collector.inspect_building(_state,id)
	var result := preload("res://simulation/building_stats.gd").inspect(_state,id,entity)
	if entity=="home" and float(result.get("next_follower_seconds",-1))>=0:
		for home: Dictionary in _state["homes"]:
			if int(home["id"])==id and not birth_space_available(home): result["next_follower_seconds"]=-1.0; break
	return result


func birth_space_available(home: Dictionary) -> bool:
	return height_at(home["work_x"],home["work_z"])>0 and not _occupied(home["work_x"],home["work_z"])


func receive_voyage_rewards(profile: Dictionary, rules: Dictionary) -> Dictionary:
	if not _state.has("progression") or _state.has("voyage"): return {"ok":false,"count":0}
	if _state["progression"]["rules"].get("sticker_aliases",{})!=rules.get("aliases",{}):
		var updated: Dictionary = _state["progression"]["rules"].duplicate(true)
		updated["sticker_aliases"]=rules.get("aliases",{}).duplicate(true)
		_state["progression"]["rules"]=Immutable.freeze(updated)
	return preload("res://simulation/voyage_rewards.gd").transfer(_state,profile,rules)


func migrate_voyage(config: Dictionary) -> void:
	if not _state.has("voyage"): return
	var previous: Dictionary = _state["voyage"]
	var upgraded := Voyage.initialize(config["voyage"],int(_state["width"]),config.get("gem_field",PackedByteArray()))
	for key: String in ["phase","elapsed","aboard","launched","rescued","score","stars"]: upgraded[key]=previous[key]
	_state["voyage"]=upgraded
	Voyage.setup(self,_state)
	_state["voyage"]["definition"]=Immutable.freeze(_state["voyage"]["definition"])


func resume_opening_handoff(source: Dictionary) -> bool:
	var opening: Dictionary=_state.get("opening",{})
	var step: int=opening.get("promised_step",-1)
	if opening.is_empty(): return false
	var prior: Dictionary=opening["definition"]
	var needs_timeline: bool=not prior.has("timeline_steps") and source.has("timeline_steps")
	var needs_housing: bool=not prior.has("mud_hut") and source.has("mud_hut") and source.has("timeline_population_card")
	var needs_shrine: bool=not Opening.has_shrine_tutorial(opening) and source.has("first_shrine_id") and source.has("shrine_population_card")
	var needs_belief: bool=not Opening.has_belief_tutorial(opening) and source.has("belief_steps") and source.has("belief_rules")
	var needs_discovery: bool=not prior.has("discovery_site_id") and source.has("discovery_site_id")
	var needs_leash: bool=not prior.has("leash_population_card") and source.has("leash_population_card")
	var needs_dock: bool=(not prior.has("dock_site_id") or not prior.get("constants",{}).has("FIRST_VOYAGE_RETURN")) and source.has("dock_site_id")
	var needs_farming: bool=source.has("farming_population_card") and (not prior.has("farming_population_card") or not prior.has("housing_advances") or not prior.has("authored_sticker_chests"))
	var needs_grain: bool=source.has("grain_building_card") and not prior.has("grain_building_card")
	var needs_grain_advances: bool=source.has("grain_advances") and not prior.has("grain_advances")
	var needs_mining: bool=source.has("mining_core") and (not prior.has("mining_core") or source.has("stone_abodes") and not prior.has("stone_abodes"))
	var needs_ark: bool=source.get("ark",{}).has("sail_labels") and not prior.get("ark",{}).has("sail_labels")
	var needs_chest_stickers: bool=source.get("source_chest_stickers",false) and not prior.get("source_chest_stickers",false)
	var needs_pit: bool=source.has("pit_sacrifice") and not prior.has("pit_sacrifice")
	var needs_rain: bool=source.has("rain") and not prior.has("rain")
	var needs_fountain: bool=source.has("fountain") and not prior.has("fountain")
	var needs_mud_lodge: bool=source.has("mud_lodge") and not prior.has("mud_lodge")
	var needs_cliff: bool=source.has("cliff_sculpt") and not prior.get("cliff_sculpt",{}).has("upgrades")
	var needs_rock_belief: bool=source.has("rock_belief") and not prior.has("rock_belief")
	var needs_collector: bool=source.has("belief_collector") and not prior.has("belief_collector")
	var needs_chest: bool=step in [7,8,9] and not prior.has("first_chest") and source.has("first_chest")
	var adds_tutorial: bool=needs_timeline or needs_housing or needs_shrine or needs_belief or needs_discovery or needs_leash or needs_dock or needs_farming or needs_grain or needs_grain_advances or needs_mining or needs_ark or needs_chest_stickers or needs_pit or needs_rain or needs_fountain or needs_mud_lodge or needs_cliff or needs_rock_belief or needs_collector
	if not adds_tutorial and (opening.get("phase")!="promised_land" or not step in [3,6,7,8,9,10]): return false
	if opening.get("handoff",{}).get("available",true) and not needs_chest and not adds_tutorial: return false
	if prior["source_sha256"]!=source.get("source_sha256") or not source.has("growth_population_card"): return false
	var functions: Dictionary=Progression.canonical_numbers(source["program"]["functions"])
	for id: String in prior["program"]["functions"]:
		if prior["program"]["functions"][id]!=functions.get(id): return false
	var definition := prior.duplicate(false)
	for key: String in ["program","helpers","day_cycle","promised_steps","growth_population_card"]: definition[key]=Progression.canonical_numbers(source[key])
	if source.has("first_chest"): definition["first_chest"]=Progression.canonical_numbers(source["first_chest"])
	if source.has("timeline_steps"):
		definition["timeline_steps"]=Progression.canonical_numbers(source["timeline_steps"])
		definition["messages"]=Progression.canonical_numbers(source["messages"])
	if needs_shrine:
		for key: String in ["shrine_steps","first_shrine_id","shrine_population_card","constants"]: definition[key]=Progression.canonical_numbers(source[key])
		for key: String in ["FIRST_SHRINE","DISCOVERY"]: opening["globals"][key]=definition["constants"][key].duplicate(true)
	if needs_belief:
		for key: String in ["belief_steps","belief_rules","constants"]: definition[key]=Progression.canonical_numbers(source[key])
		for key: String in ["SCULPT_GRASS_POS","nrOfStartedSculpts","nrOfCompletedSculpts","nrOfFailedSculpts","needBeliefToSculptTipCounter","currentSculptPos","currentSculptPosAlt"]:
			var value: Variant=definition["constants"][key]
			opening["globals"][key]=value.duplicate(true) if value is Dictionary or value is Array else value
	if needs_discovery:
		for key: String in ["discovery","discovery_site_id","constants"]:
			definition[key]=Progression.canonical_numbers(source[key])
		for key: String in ["CARD_DISCOVERY","CLIENT_VERSION","ClientVersion"]:
			var value: Variant=definition["constants"][key]
			opening["globals"][key]=value.duplicate(true) if value is Dictionary else value
	if needs_leash:
		for key: String in ["discovery","constants","leash_population_card"]:
			definition[key]=Progression.canonical_numbers(source[key])
		opening["globals"]["EVENT_TEMPLE"]=definition["constants"]["EVENT_TEMPLE"].duplicate(true)
	if needs_dock:
		for key: String in ["dock_site_id","leash_rules","discovery","constants"]: definition[key]=Progression.canonical_numbers(source[key])
		opening["globals"]["leashCount"]=source["constants"]["leashCount"]
	if needs_farming:
		for key: String in ["discovery","constants","farming_population_card","farming_core","housing_advances","wooden_abodes","authored_sticker_chests"]:
			if not source.has(key): continue
			definition[key]=Progression.canonical_numbers(source[key])
		for key: String in ["FARM_BELIEF_COST","JOB_FARMER","JOB_BUILDER","FIELD_TYPE"]: opening["globals"][key]=definition["constants"][key]
		var updated: Dictionary=_state["progression"]["rules"].duplicate(true)
		updated["economy"]["settlements"][Farming.POWER]["cost"]=definition["constants"]["FARM_BELIEF_COST"]
		_state["progression"]["rules"]=Immutable.freeze(updated)
	if needs_grain:
		for key: String in ["discovery","authored_fields","grain_building_card"]: definition[key]=Progression.canonical_numbers(source[key])
	if needs_grain_advances:
		for key: String in ["grain_advances","wooden_abodes","builder_settlement","builder_core"]:
			if source.has(key): definition[key]=Progression.canonical_numbers(source[key])
		if definition.has("builder_core"):
			var updated: Dictionary=_state["progression"]["rules"].duplicate(true)
			updated["economy"]["settlements"][Farming.BUILDER_POWER]["cost"]=definition["builder_settlement"]["cost"]
			_state["progression"]["rules"]=Immutable.freeze(updated)
	if needs_mining:
		for key: String in ["mining_population_card","mining_settlement","mining_core","ore_advances","stone_abodes"]:
			if source.has(key): definition[key]=Progression.canonical_numbers(source[key])
		var updated: Dictionary=_state["progression"]["rules"].duplicate(true)
		updated["economy"]["settlements"][Farming.MINING_POWER]["cost"]=definition["mining_settlement"]["cost"]
		_state["progression"]["rules"]=Immutable.freeze(updated)
	if needs_ark: definition["ark"]=Progression.canonical_numbers(source["ark"])
	if needs_chest_stickers:
		if opening.get("sticker_chests_registered",false):
			opening["registered_sticker_chests"]=prior.get("authored_sticker_chests",[]).size()
		for key: String in ["authored_sticker_chests","source_chest_stickers","source_research_cards","source_research_stickers","sticker_selection_rules"]:
			definition[key]=Progression.canonical_numbers(source[key])
	if needs_pit:
		for key: String in ["pit_sacrifice","pit_clips","pit_beam"]: definition[key]=Progression.canonical_numbers(source[key])
	if needs_rain: definition["rain"]=Progression.canonical_numbers(source["rain"])
	if needs_cliff: definition["cliff_sculpt"]=Progression.canonical_numbers(source["cliff_sculpt"])
	if needs_rock_belief: definition["rock_belief"]=Progression.canonical_numbers(source["rock_belief"])
	if needs_collector: definition["belief_collector"]=Progression.canonical_numbers(source["belief_collector"])
	if needs_mud_lodge:
		for key: String in ["mud_lodge","housing_advances"]: definition[key]=Progression.canonical_numbers(source[key])
	if needs_fountain:
		definition["fountain"]=Progression.canonical_numbers(source["fountain"])
		var messages: Dictionary=definition["messages"].duplicate(false)
		for id: String in ["5602","5603","5604","5606"]: messages[id]=Progression.canonical_numbers(source["messages"][id])
		definition["messages"]=messages
	if needs_housing:
		for key: String in ["mud_hut","timeline_population_card","constants"]: definition[key]=Progression.canonical_numbers(source[key])
		if opening["phase"]=="timeline":
			# Older Timeline saves replaced the completed tents' source duration
			# with the compatibility house table when the sticker was applied.
			var tent_ticks := roundi(float(definition["first_abode_values"]["values"]["build time"])/TICK_SECONDS)
			for home: Dictionary in _state["homes"]:
				if home.get("model_id")==definition["first_abode_model"] and home["progress"]>=home["build_ticks"]:
					home["progress"]=tent_ticks
					home["build_ticks"]=tent_ticks
	opening["definition"]=Immutable.freeze(definition)
	opening["globals"].merge(definition["helpers"].duplicate(true))
	opening["globals"]["origTimeOfDaySpeed"]=definition["day_cycle"]["configuration"]["TimeOfDaySpeed"]
	if not opening["globals"].has("abodesInState0"): opening["globals"]["abodesInState0"]=0
	return true


func prepare_loaded_opening() -> void:
	if not _state.has("opening"): return
	var opening: Dictionary=_state["opening"]
	opening.erase("rain_cast")
	if opening.get("fountain_card_open",false): opening["resume_fountain_card"]=true
	_pending=_pending.filter(func(command: Dictionary) -> bool: return command.get("power")!=Rain.POWER and command["type"]!="campaign_rain_stop")
	if Opening.supports_level_card(opening) and opening["promised_step"]==8: opening["resume_card_tutorial"]=true
	if Opening.supports_timeline(opening): opening["resume_timeline"]=true
	if opening["phase"]=="shrine" and opening["shrine_step"]==1: opening["resume_shrine_card"]=true
	if opening["phase"]=="belief" and opening["belief_step"] in [1,2]: opening["resume_belief"]=true
	if Opening.supports_discovery(opening) and opening.get("pit_card_open",false): opening["resume_pit_card"]=true
	if Opening.supports_discovery(opening) and opening.get("leash_step")==1: opening["resume_leash_card"]=true
	if Opening.supports_discovery(opening) and opening.get("dock_card_open",false): opening["resume_dock_card"]=true
	if Opening.supports_discovery(opening) and opening.get("events_step")==0: opening["resume_dock_selection"]=true
	if Opening.supports_discovery(opening) and opening.get("farming_step") in [1,2,3]: opening["resume_farming"]=true
	if opening.get("farming_step",-1)>=4:
		opening.erase("farming_placing")
		opening.erase("farming_preview")
	if opening.get("superfast_step") in [1,3]: opening["resume_superfast"]=true
	opening.erase("builder_preview")
	opening.erase("mining_preview")


func initialize_authored_chests() -> void:
	var chests := preload("res://simulation/authored_chests.gd").new()
	chests.configure(self,_state,[])
	chests.initialize(_random)


func detached_state(include_scenery: bool = true) -> Dictionary:
	var source := _state.duplicate(false)
	if not include_scenery: source["trees"] = []
	var rules: Dictionary = _state.get("progression", {}).get("rules", {})
	if not rules.is_empty() and rules.is_read_only():
		source["progression"] = source["progression"].duplicate(false)
		source["progression"].erase("rules")
	var voyage_definition: Dictionary = _state.get("voyage",{}).get("definition",{})
	if not voyage_definition.is_empty() and voyage_definition.is_read_only():
		source["voyage"]=source["voyage"].duplicate(false)
		source["voyage"].erase("definition")
	var opening_definition: Dictionary = _state.get("opening",{}).get("definition",{})
	if not opening_definition.is_empty() and opening_definition.is_read_only():
		source["opening"]=source["opening"].duplicate(false)
		source["opening"].erase("definition")
	var result := source.duplicate(true)
	if not rules.is_empty() and rules.is_read_only(): result["progression"]["rules"] = rules
	if not voyage_definition.is_empty() and voyage_definition.is_read_only(): result["voyage"]["definition"]=voyage_definition
	if not opening_definition.is_empty() and opening_definition.is_read_only(): result["opening"]["definition"]=opening_definition
	return result


func queue_command(command: Dictionary) -> void:
	if _pending.size() < 128:
		_pending.append(command.duplicate(true))


func height_at(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= _state["width"] or z >= _state["width"]:
		return 0
	return int(_state["terrain"][z * _state["width"] + x])


func _index_trees() -> void:
	var cells := {}
	_tree_coast={}
	_tree_rows={}
	_tree_tiles={}
	var index := 0
	for tree: Dictionary in _state["trees"]:
		var cell := int(tree.get("cell",int(tree["z"])*int(_state["width"])+int(tree["x"])))
		cells[cell]=int(tree["variant"])
		if tree.has("source_y"):
			_tree_rows[cell]=index
			var tile := Vector2i((cell%int(_state["width"]))/32,(cell/int(_state["width"]))/32)
			if not _tree_tiles.has(tile): _tree_tiles[tile]=[]
			_tree_tiles[tile].append(cell)
		if tree.get("anchor_height",-1)==0 and float(tree.get("source_y",0))>0: _tree_coast[cell]=true
		index+=1
	cells.make_read_only()
	_tree_cells=cells
	Immutable.freeze(_tree_tiles)
	_tree_rows.make_read_only()
	_tree_coast.make_read_only()


func tree_at(x: int,z: int) -> bool:
	if x<0 or z<0 or x>=int(_state["width"]) or z>=int(_state["width"]): return false
	var cell: int = z*int(_state["width"])+x
	if _state.has("tree_response"):
		return _tree_cells.has(cell) and not _state["removed_trees"].has(str(cell)) and _state["tree_response"]["entries"].get(str(cell),{}).get("enabled",true)
	return (height_at(x,z)>0 or _tree_coast.has(cell)) and _tree_cells.has(cell) and not _state.get("removed_trees",{}).has(str(cell))


func source_tree_target(tree: Dictionary) -> float:
	return preload("res://simulation/source_terrain.gd").surface_height(source_raw_height_at(float(tree["x"]),float(tree["z"])))


func plot_obstruction(x: int,z: int) -> String:
	if tree_at(x,z): return "tree"
	var cell: int = z*int(_state["width"])+x
	if _state.has("opening") and not preload("res://simulation/authored_rocks.gd").at(_state,cell).is_empty():
		return "rock" if Opening.rock_alive(_state,cell) else ""
	var rocks: Variant = _state.get("rocks",PackedByteArray())
	if cell>=0 and cell<rocks.size() and int(rocks[cell])>0 and height_at(x,z)>0 and (not _state.has("rock_heights") or int(_state["rock_heights"][cell])==height_at(x,z)):
		if int(_state.get("progression",{}).get("rock_taps",{}).get(str(cell),0))<int(_state.get("progression",{}).get("rules",{}).get("config",{}).get("tapsToDestroyRock",2)): return "rock"
	return ""


func source_plot_capacity(x: int,z: int,limit: int=16) -> int:
	# Private source campaigns use quad terrain and the native clear-size mask;
	# the older campaigns retain their existing separate plot implementation.
	if not _state.has("source_scenery"): return 0
	return preload("res://simulation/source_plots.gd").capacity(_state["terrain"],int(_state["width"]),x,z,func(px: int,pz: int) -> bool: return plot_obstruction(px,pz)!="" or _occupied(px,pz),limit)


func source_biome_at(x: float,z: float) -> int:
	var environment: Dictionary=_state.get("opening",{}).get("definition",{}).get("plot_environment",{})
	if environment.is_empty(): return -1
	return preload("res://simulation/source_biomes.gd").biome_at(environment["biomes"],environment["configuration"],x,z)


func source_plot_band(x: int,z: int) -> int:
	var environment: Dictionary=_state.get("opening",{}).get("definition",{}).get("plot_environment",{})
	if environment.is_empty() or x<0 or z<0 or x>=int(_state["width"]) or z>=int(_state["width"]): return -1
	return preload("res://simulation/source_biomes.gd").band(height_at(x,z)+19,environment["configuration"])


func source_raw_height_at(x: float,z: float) -> int:
	if not _state.has("opening"): return -1
	var intro: Dictionary=_state["opening"]
	var vertex := func(px: int,pz: int) -> int:
		var cell := pz*int(_state["width"])+px
		var height := int(_state["terrain"][cell])
		return height+19 if height>0 else int(intro["submerged_levels"].get(str(cell),intro["definition"]["raw_floor"][cell]))
	return preload("res://simulation/source_terrain.gd").raw_at(vertex,int(_state["width"]),x,z)


func source_step_at(x: float,z: float) -> float:
	var raw := source_raw_height_at(x,z)
	return -1.0 if raw<0 else preload("res://simulation/source_terrain.gd").script_step(raw)


func source_rock_target(cell: int) -> float:
	var rock := preload("res://simulation/authored_rocks.gd").at(_state,cell)
	return preload("res://simulation/source_terrain.gd").surface_height(source_raw_height_at(float(rock["x"]),float(rock["z"])))


func _dirty_rock_tiles(tiles: Dictionary,cell: int) -> void:
	if _state.has("source_plots"):
		preload("res://simulation/source_plot_schedule.gd").mark(_state["source_plots"]["schedule"],cell%int(_state["width"]),cell/int(_state["width"]))
	if not _state.has("rock_motion") and not _state.has("tree_response"): return
	var width := int(_state["width"])
	var x := cell%width
	var z := cell/width
	# A changed vertex participates in four adjacent quads. Dirty the native
	# 32-cell regions owning those quads, including a neighboring tile at seams.
	for pz in range(maxi(0,z-1),mini(width-1,z+1)):
		for px in range(maxi(0,x-1),mini(width-1,x+1)): tiles[Vector2i(px/32,pz/32)]=true


func source_house_for_plot(x: int,z: int,size: int,kind: int=0) -> Dictionary:
	var rows: Array=_state.get("opening",{}).get("definition",{}).get("house_selection",[])
	if rows.is_empty(): return {}
	var gates := preload("res://simulation/source_unlocks.gd")
	var unlocked := func(key: String) -> bool: return gates.enabled(_state["progression"],key)
	return preload("res://simulation/source_houses.gd").choose(rows,size,source_plot_band(x,z),source_biome_at(x,z),unlocked,kind,false,gates.enabled(_state["progression"],"HousesBiomeLocked"))


func source_plot_limits() -> Dictionary:
	var rows: Array=_state.get("opening",{}).get("definition",{}).get("house_selection",[])
	if rows.is_empty(): return {}
	var unlocked := func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],key)
	return preload("res://simulation/source_houses.gd").plot_limits(rows,unlocked)


func source_build_offer(follower_id: int,ordered_plot_ids: Array,parameters: Dictionary) -> Dictionary:
	# A pure query over caller-supplied native candidate order/profile. The
	# campaign has no source construction jobs yet, so its worker counters are
	# zero. Do not invent counters for a state containing existing buildings.
	if not _state.has("source_plots") or not _state["homes"].is_empty(): return {}
	var definition: Dictionary=_state["opening"]["definition"]
	if not definition.has("build_candidate_values"): return {}
	var actor := {}
	for follower: Dictionary in _state["followers"]:
		if int(follower["id"])==follower_id: actor=follower; break
	if actor.is_empty(): return {}
	var candidates: Array=[]
	var seen := {}
	for value: Variant in ordered_plot_ids:
		if not preload("res://simulation/source_plot_schedule.gd").integer_between(value,0,1023) or seen.has(int(value)): return {}
		var id := int(value)
		if not _state["source_plots"]["active"].has(id): return {}
		seen[id]=true
		candidates.append(_state["source_plots"]["slots"][id])
	var profile := parameters.duplicate(true)
	profile["position"]=[float(actor["x"]),float(actor["z"]),preload("res://simulation/source_terrain.gd").surface_height(source_raw_height_at(float(actor["x"]),float(actor["z"])))]
	var unlocked := func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],key)
	var allows := func(x: int,z: int,power: bool) -> bool: return preload("res://simulation/source_influence.gd").allows(_state["source_influence"]["raster"],x,z,power,definition["influence_rules"])
	return preload("res://simulation/source_build_candidates.gd").choose_plots(candidates,profile,definition["house_selection"],definition["build_candidate_values"],definition["plot_environment"],unlocked,allows,source_raw_height_at)


func source_plot_eligible(x: int,z: int) -> bool:
	if not _state.has("source_influence"): return false
	return preload("res://simulation/source_influence.gd").allows(_state["source_influence"]["raster"],x,z,false,_state["opening"]["definition"]["influence_rules"])


static func _source_plot_definition_supported(definition: Dictionary) -> bool:
	var field: Variant=definition.get("plot_field")
	if not preload("res://simulation/source_plot_field.gd").valid(field): return false
	if int(field["default"])!=0 or not field["values"].is_empty(): return false
	var rules: Variant=definition.get("plot_resize_rules")
	return preload("res://simulation/source_plot_resize.gd").valid_rules(rules) and rules.has("progress_rate") and preload("res://simulation/source_biomes.gd").valid(definition.get("plot_environment")) and preload("res://simulation/source_houses.gd").valid(definition.get("house_selection"))


func _source_fresh_plot_cell(x: int,z: int,biomes: int) -> bool:
	if not source_plot_eligible(x,z): return false
	if (biomes&(1<<source_biome_at(x,z)))==0: return false
	return preload("res://simulation/source_plots.gd").map_byte_allows(preload("res://simulation/source_plot_field.gd").at(_state["opening"]["definition"]["plot_field"],x,z))


func _source_fresh_plot_region(tile: Vector2i) -> bool:
	# Every fresh footprint includes an eligible origin. The original 64-cell
	# origin window intersects only these four 32-cell influence tiles.
	var fields: Dictionary=_state["source_influence"]["raster"]["fields"]["4"]
	for z in range(maxi(0,tile.y-1),mini(31,tile.y)+1):
		for x in range(maxi(0,tile.x-1),mini(31,tile.x)+1):
			if fields.has(str(z*32+x)): return true
	return false


func _source_plot_field_at(x: int,z: int,biomes: int) -> Dictionary:
	var height := height_at(x,z)
	var flat := x>=0 and z>=0 and x<1023 and z<1023 and height>0 and height_at(x+1,z)==height and height_at(x,z+1)==height and height_at(x+1,z+1)==height
	return {"flat":flat,"scenery":plot_obstruction(x,z)!="","blocked":_occupied(x,z),
		"map_byte":preload("res://simulation/source_plot_field.gd").at(_state["opening"]["definition"]["plot_field"],x,z),
		"blight":preload("res://simulation/source_map_fields.gd").read(_state["source_influence"]["raster"],5,x,z),
		"biome_allowed":(biomes&(1<<source_biome_at(x,z)))!=0,"eligible":_source_fresh_plot_cell(x,z,biomes)}


func _advance_source_plots() -> void:
	if not _state.has("source_plots"): return
	var registry := preload("res://simulation/source_plot_registry.gd")
	var state: Dictionary=_state["source_plots"]
	var rules: Dictionary=_state["opening"]["definition"]["plot_resize_rules"]
	# Original tick order: old plot lifetimes, maintenance, then influence.
	registry.advance(state,TICK_SECONDS,float(rules["progress_rate"]))
	for key: String in _state["source_influence"]["dirty"]: state["schedule"]["dirty"][key]=true
	_state["source_influence"]["dirty"].clear()
	var limits := source_plot_limits()
	var cache := {}
	var fields := func(x: int,z: int) -> Dictionary:
		var key := z*1024+x
		if not cache.has(key): cache[key]=_source_plot_field_at(x,z,int(limits["biomes"]))
		return cache[key]
	var loaded := func(x: int,z: int) -> bool: return x>=0 and z>=0 and x<1024 and z<1024
	var height := func(x: int,z: int) -> float: return preload("res://simulation/source_terrain.gd").surface_height(height_at(x,z)+19)
	var eligible := func(x: int,z: int) -> bool: return _source_fresh_plot_cell(x,z,int(limits["biomes"]))
	registry.maintain(state,rules,limits,fields,loaded,source_plot_band,height,-1,eligible,_source_fresh_plot_region)


func _advance_source_influence(events: Array) -> void:
	if not _state.has("source_influence"): return
	var unlocked := func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],key)
	var callbacks := preload("res://simulation/source_influence_areas.gd").advance(_state["source_influence"],_state["progression"]["rules"]["influence_areas"],_state["opening"]["definition"]["influence_rules"],unlocked,TICK_SECONDS)
	Influence.refresh(_state)
	for callback: Dictionary in callbacks: events.append({"type":"source_callback","name":callback["name"],"argument":callback["argument"]})


func _occupied(x: int, z: int, ignore_home: int = -1) -> bool:
	refresh_spatial()
	var owner: int = _blocked_cells.get(Vector2i(x,z),-1)
	return owner != -1 and owner != ignore_home


func refresh_spatial() -> void:
	var stamp := Vector2i(_state["terrain_revision"],_spatial_revision)
	if stamp == _blocked_stamp: return
	_blocked_stamp=stamp
	_blocked_cells.clear()
	for home: Dictionary in _state["homes"]:
		for dz in range(int(home.get("span",2))):
			for dx in range(int(home.get("span",2))): _blocked_cells[Vector2i(home["x"]+dx,home["z"]+dz)]=home["id"]
	if _state.has("opening"):
		for prop: Dictionary in _state["props"]:
			var kind: String=prop.get("kind","")
			if not kind in ["fountain",Collector.KIND]: continue
			var rules: Dictionary=_state["opening"]["definition"][kind]
			var area:=Rect2i(prop["x"],prop["z"],rules["width"],rules["depth"])
			for z in range(area.position.y,area.end.y):
				for x in range(area.position.x,area.end.x): _blocked_cells[Vector2i(x,z)]=prop["id"]


func _completed_homes() -> int:
	var count := 0
	for home: Dictionary in _state["homes"]:
		if home.get("kind","") == "" and home["progress"] >= int(home.get("build_ticks",_state.get("build_ticks", BUILD_TICKS))):
			count += 1
	return count


func _route(start: Vector2i, target: Vector2i, ignore_home: int = -1,avoid: Rect2i=Rect2i()) -> Array:
	if start==target or height_at(target.x,target.y)<=0: return []
	# This is a derived cache. A fresh search follows exactly the same neighbor
	# order and finds the same routes after restoring a save without the cache.
	var stamp := hash(Vector2i(_state["terrain_revision"],_spatial_revision))
	if stamp!=_navigation_stamp:
		_navigation_stamp=stamp
		_route_cache.clear()
		_component_of.clear()
	refresh_spatial()
	var masking := avoid.has_area()
	if masking and avoid.has_point(target) or _blocked_cells.has(target) and _blocked_cells[target]!=ignore_home: return []
	var policy: Variant=[ignore_home,avoid] if masking else ignore_home
	if not _component_of.has(policy): _component_of[policy]={}
	var components: Dictionary = _component_of[policy]
	if components.has(start) and components.get(target,-1)!=components[start]: return []
	var key: Variant=[start,policy] if masking else Vector3i(start.x,start.y,ignore_home)
	if not _route_cache.has(key):
		if _route_cache.size()>=12: _route_cache.erase(_route_cache.keys()[0])
		_route_cache[key]={"frontier":[start],"previous":{start:start},"cursor":0}
	var search: Dictionary = _route_cache[key]
	var frontier: Array = search["frontier"]
	var previous: Dictionary = search["previous"]
	while not previous.has(target) and int(search["cursor"])<frontier.size():
		var current: Vector2i = frontier[int(search["cursor"])]
		search["cursor"]+=1
		for direction: Vector2i in DIRECTIONS:
			var next := current+direction
			if previous.has(next) or masking and avoid.has_point(next) or height_at(next.x,next.y)<=0 or (_blocked_cells.has(next) and _blocked_cells[next]!=ignore_home): continue
			if absi(height_at(current.x,current.y)-height_at(next.x,next.y))>1: continue
			previous[next]=current
			frontier.append(next)
	if not previous.has(target):
		var component: int = components.size()
		for cell: Vector2i in previous: components[cell]=component
		return []
	var path: Array = []
	var position := target
	while position!=start:
		path.push_front(position.y*int(_state["width"])+position.x)
		position=previous[position]
	return path


func inspect(command: Dictionary) -> Dictionary:
	return _validate(command).duplicate(true)


func can_act_at(x: float,z: float) -> bool:
	if _state.has("voyage"): return Voyage.can_act_at(_state,x,z)
	return Influence.contains(_state,x,z)


func find_edge(x: float, z: float, layer: int, cliff: bool=false) -> Dictionary:
	var best: Dictionary = {"ok": false, "reason": "Grab near the edge of a terrain layer, then drag."}
	if not can_act_at(x,z): return best
	var cap:=Cliff.layers(_state) if cliff else 0
	if cliff and cap==0: return best
	var nearest := 6.25
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var cell := Vector2i(roundi(x) + dx, roundi(z) + dz)
			if not can_act_at(cell.x,cell.y): continue
			var high:=mini(MAX_HEIGHT,height_at(cell.x,cell.y))
			var chosen_layer:=0
			var chosen_normal:=Vector2i.ZERO
			var cell_distance:=nearest
			for normal: Vector2i in DIRECTIONS:
				var low:=height_at(cell.x+normal.x,cell.y+normal.y)
				var candidate_layer:=mini(high,low+cap) if cliff else (low+1 if layer==0 else layer)
				if candidate_layer<=low or candidate_layer>high: continue
				var score:=Vector2(x,z).distance_squared_to(Vector2(cell)+Vector2(normal)*0.5)
				# Preserve the tie order of ascending layers within each cell.
				if score<cell_distance or score==cell_distance and chosen_layer>candidate_layer:
					cell_distance=score
					chosen_layer=candidate_layer
					chosen_normal=normal
			if chosen_layer>0:
				nearest=cell_distance
				best={"ok":true,"x":cell.x,"z":cell.y,"nx":chosen_normal.x,"nz":chosen_normal.y,"layer":chosen_layer}
	return best.duplicate(true)


func _validate_drag(command: Dictionary) -> Dictionary:
	var x := int(command.get("x", -1))
	var z := int(command.get("z", -1))
	var nx := int(command.get("nx", 0))
	var nz := int(command.get("nz", 0))
	var layer := int(command.get("layer", 0))
	var distance := clampi(int(command.get("distance", 0)), -12, 12)
	var radius := clampi(int(command.get("radius", 1)), 0, 2)
	var high:=height_at(x,z)
	var low:=height_at(x+nx,z+nz)
	var cliff: bool=command.get("power")==Cliff.POWER
	var cap:=Cliff.layers(_state) if cliff else 0
	if command.has("power") and cap==0:
		return {"ok":false,"reason":"Cliff Sculpting is locked.","cost":0}
	if absi(nx) + absi(nz) != 1 or layer < 1 or layer > MAX_HEIGHT or high < layer or low >= layer or cliff and layer!=mini(high,low+cap):
		return {"ok": false, "reason": "Grab an exposed edge of this layer.", "cost": 0}
	if distance == 0:
		return {"ok": false, "reason": "Drag outward to extend this layer; inward to retract it.", "cost": 0}
	var dx := clampi(int(command.get("dx", nx * distance)), -12, 12)
	var dz := clampi(int(command.get("dz", nz * distance)), -12, 12)
	var steps := maxi(absi(dx), absi(dz))
	var sweep: Array[Vector2i] = []
	var previous := Vector2i(x, z)
	for step_index in range(steps):
		var along := step_index + 1 if distance > 0 else step_index
		var cell := Vector2i(x + roundi(dx * along / float(maxi(steps, 1))), z + roundi(dz * along / float(maxi(steps, 1))))
		# Supercover diagonal drags so the edited land remains 4-connected.
		if cell.x != previous.x and cell.y != previous.y:
			sweep.append(Vector2i(cell.x, previous.y))
		sweep.append(cell)
		previous = cell
	var changes: Dictionary = {}
	for cell: Vector2i in sweep:
		for across in range(-radius, radius + 1):
			var px := cell.x - nz * across
			var pz := cell.y + nx * across
			if px < 1 or pz < 1 or px >= _state["width"] - 1 or pz >= _state["width"] - 1:
				return {"ok": false, "reason": "Keep the drag inside the world boundary.", "cost": 0}
			var old := height_at(px, pz)
			var height := maxi(old, layer) if distance > 0 else mini(old, layer - 1)
			if cliff: height=Cliff.target(old,high,low,cap,distance>0)
			if height == old:
				continue
			if _occupied(px, pz):
				return {"ok": false, "reason": "A home occupies this land. Drag around its plot.", "cost": 0}
			changes[pz * int(_state["width"]) + px] = height
	var edits: Array = []
	var units := 0.0
	var cliff_rules: Dictionary=_state["opening"]["definition"]["cliff_sculpt"] if cliff else {}
	for cell: int in changes:
		if not can_act_at(cell%int(_state["width"]),cell/int(_state["width"])): return {"ok":false,"cost":0,"reason":""}
		if _state.has("opening") and (Opening.supports_first_plot(_state["opening"]) or Opening.supports_expansion(_state["opening"])) and not Opening.inside_plot_sculpt_lock(_state["opening"],cell%int(_state["width"]),cell/int(_state["width"])): return {"ok":false,"cost":0,"reason":""}
		edits.append({"cell": cell, "height": changes[cell]})
		var change:=absi(int(changes[cell])-int(_state["terrain"][cell]))
		units+=Cliff.belief_units(change,cliff_rules) if cliff else float(change)
	var cost:=ceili(units*runtime_value("sculpt_cost",1.0))
	if _state.has("opening"): cost=Opening.sculpt_cost(_state,edits,cost)
	if edits.is_empty():
		return {"ok": false, "reason": "This drag does not change the selected layer.", "cost": 0}
	var dry := _dry_land
	for home: Dictionary in _state["homes"]:
		# Occupied plots cannot serve as the last refuge for mobile agents.
		dry -= int(home.get("span",2))*int(home.get("span",2))
	for edit: Dictionary in edits:
		if edit["height"] == 0 and int(_state["terrain"][edit["cell"]]) > 0:
			dry -= 1
		elif edit["height"] > 0 and int(_state["terrain"][edit["cell"]]) == 0: dry += 1
	if dry <= 0:
		return {"ok": false, "reason": "Leave some dry land for your followers.", "cost": cost}
	return {"ok": _state["belief"] >= cost, "reason": ("Extend" if distance > 0 else "Retract") + " layer %d · %d belief" % [layer, cost] if _state["belief"] >= cost else "This drag needs %d belief. Shorten it or collect more." % cost, "cost": cost, "edits": edits}


func _inspect_collection(command: Dictionary) -> Dictionary:
	var amount := 0
	var collectible: Array=[]
	for home: Dictionary in _state["homes"]:
		if command.has("home_id") and home["id"] != int(command["home_id"]): continue
		if home.get("kind","") in ["farm","mine"]:
			if not command.has("home_id") or not (home.has("awaiting_influence") or home.get("direct_harvest",false)) or not can_act_at(home["anchor_x"],home["anchor_z"]): continue
			if home["progress"]<home["build_ticks"]: continue
			var harvest := int(home["harvest_accumulator"])
			var resource := "wheat" if home["kind"]=="farm" else "ore"
			return {"ok":harvest>0 and harvest>=int(home["max_belief"]),"cost":0,"reason":"","amount":harvest,"resource":resource,"homes":[home["id"]]}
		if not can_act_at(home["x"],home["z"]): continue
		if int(home["stored"])<int(home.get("min_belief",0)): continue
		amount += int(home["stored"])
		collectible.append(home["id"])
	return {"ok": amount > 0, "reason": "Collect %d belief" % amount if amount > 0 else "Homes are still gathering belief.", "cost": 0, "amount": amount,"homes":collectible}


func _sculpt_context(command: Dictionary,edits: Array) -> Dictionary:
	var x := float(command.get("x",0))
	var z := float(command.get("z",0))
	var old := source_raw_height_at(x,z)
	var first := old
	var last := int(command.get("layer",maxi(1,old-19)))+19
	for edit: Dictionary in edits:
		var cell: int=edit["cell"]
		var previous := source_raw_height_at(cell%int(_state["width"]),cell/int(_state["width"]))
		first=mini(first,mini(previous,int(edit["height"])+19))
		last=maxi(last,maxi(previous,int(edit["height"])+19))
	return {"layers":[first,last],"position":[x,z,preload("res://simulation/source_terrain.gd").surface_height(old)]}


func inspect_source_settlement(opening: Dictionary,command: Dictionary,power: String) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var role := "mining" if power==Farming.MINING_POWER else "builder"
	if not opening["definition"].has(role+"_core") or not power in _state["progression"]["powers"]: return reject
	var draft: Dictionary=opening.get(role+"_preview",{})
	match str(command["type"]).get_slice("_",2):
		"preview":
			var plan:=Farming.inspect_placement(self,_state,command,power)
			plan["cost"]=0
			return plan
		"cancel":
			return {"ok":true,"cost":0,"reason":""}
		"confirm":
			if draft.is_empty(): return reject
			var plan:=Farming.inspect_placement(self,_state,draft,power)
			if plan.get("members",[])!=draft["members"]: return reject
			return plan
	return reject


func _validate(command: Dictionary, ignore_home: int = -1,ignore_shrine: String = "") -> Dictionary:
	var kind: String = str(command.get("type", ""))
	if _state.has("leash_lesson"): return LeashLesson.inspect(self,_state,command)
	if kind=="weyworld_release_ark": return inspect_ark_release(command.get("id"))
	if _state.has("weyworld"):
		if kind=="leash": return inspect_weyworld_leash(command)
		if kind=="campaign_ack": return {"ok":command.get("id") in _state["weyworld"]["hints"] and int(command.get("id"))>=5803,"cost":0,"reason":""}
	if _state.has("opening"):
		if kind=="campaign_view": return {"ok":Opening.valid_observation(command),"cost":0,"reason":""}
		if kind=="collect" and command.get("gesture")=="drag" and not preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"BeliefLeashing"):
			return {"ok":false,"cost":0,"reason":""}
		if kind=="campaign_ack":
			var found := false
			for message: Dictionary in _state["opening"]["messages"]:
				if int(message["id"])!=int(command.get("id",-1)): continue
				var group: String=_state["opening"]["definition"]["messages"].get(str(int(message["id"])),{}).get("group","")
				found=int(message.get("visible_tick",0))<=int(_state["tick"]) and not group in _state["opening"].get("hidden_tables",[])
				found=found and (int(message["id"])!=1005 or not Opening.first_plot_in_range(_state,message.get("anchor",{}).get("handle")).is_empty())
			return {"ok":found,"cost":0,"reason":""}
		var timeline_housing := Opening.supports_timeline_housing(_state["opening"])
		var shrine_housing := Opening.supports_shrine_housing(_state["opening"])
		var discovery := Opening.supports_discovery(_state["opening"])
		if discovery:
			var opening: Dictionary=_state["opening"]
			var leash_card: bool=opening.get("leash_step")==1 and not opening.get("leash_mission_pending",false)
			if opening.get("leash_mission_pending",false): return {"ok":kind=="campaign_leash_lesson_completed","cost":0,"reason":""}
			if kind=="campaign_rain_stop": return {"ok":true,"cost":0,"reason":""}
			if kind=="campaign_cliff_upgrade": return Cliff.inspect_upgrade(_state,command.get("id"))
			if kind=="campaign_belief_collector_upgrade": return Collector.inspect_upgrade(_state,command.get("id"))
			if kind=="use_power" and command.get("power")==Rain.POWER:
				return Rain.inspect(self,_state,command,TICK_SECONDS)
			if kind=="use_power" and command.get("power")==Collector.POWER:
				return Collector.inspect_place(self,_state,command)
			if kind=="campaign_fountain_tap" or kind=="use_power" and command.get("power")==Fountain.POWER:
				return Fountain.inspect(self,_state,command)
			var farm_step: int=opening.get("farming_step",-1)
			var farm_placement: bool=farm_step==3 or opening.get("farming_placing",false)
			if kind=="campaign_farm_card" or kind=="claim_card" and command.get("card")=="Card_Settlement_Farming":
				return {"ok":farm_step==0 and not leash_card and not opening.get("pit_card_open",false) and not opening.get("dock_card_open",false),"cost":0,"reason":""}
			if kind=="campaign_farm_select": return {"ok":farm_step==2 or farm_step>=4 and not farm_placement,"cost":0,"reason":""}
			if kind in ["campaign_farm_begin","campaign_farm_cancel"]:
				return {"ok":farm_placement,"cost":0,"reason":""}
			if kind=="campaign_farm_preview" and farm_placement:
				var preview:=Farming.inspect_placement(self,_state,command)
				preview["cost"]=0
				return preview
			if kind=="campaign_farm_confirm" and farm_placement and opening.has("farming_preview"):
				var draft: Dictionary=opening["farming_preview"]
				var plan:=Farming.inspect_placement(self,_state,draft)
				if plan.get("members",[])!=draft["members"]: plan["ok"]=false
				return plan
			if kind in ["campaign_builder_preview","campaign_builder_confirm","campaign_builder_cancel"]:
				return inspect_source_settlement(opening,command,Farming.BUILDER_POWER)
			if kind in ["campaign_mining_preview","campaign_mining_confirm","campaign_mining_cancel"]:
				return inspect_source_settlement(opening,command,Farming.MINING_POWER)
			if kind=="deploy_worker":
				var settlement:=Economy.settlement(_state,int(command.get("id",-1)))
				if settlement.get("role")=="builder":
					var release:={"type":"sprog","home_id":settlement["members"][0]}
					var worker:=_validate(release)
					worker["plot_command"]=release
					return worker
				if settlement.get("role")=="miner" or farm_step>=4: return Farming.plan_field(self,_state,int(command.get("id",-1)))
			if kind=="collect_settlement":
				if command.get("gesture")=="drag" and not preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"BeliefLeashing"):
					return {"ok":false,"cost":0,"reason":""}
				return Economy.inspect(self,_state,command)
			if kind in ["claim_card","research_card"]:
				var rock_belief: Dictionary=opening["definition"].get("rock_belief",{})
				if not rock_belief.is_empty() and command.get("card")==rock_belief["card"] or opening["definition"].has("belief_collector") and command.get("card")==Collector.CARD:
					return Research.inspect(_state["progression"],command)
				if opening["definition"].has("cliff_sculpt") and command.get("card")==Cliff.CARD:
					return Research.inspect(_state["progression"],command)
				if opening["definition"].has("fountain") and command.get("card")==Fountain.CARD:
					return Research.inspect(_state["progression"],command)
				var rain: Dictionary=opening["definition"].get("rain",{})
				if not rain.is_empty() and command.get("card")==rain["card"]:
					return Research.inspect(_state["progression"],command)
				var grain: Dictionary=opening["definition"].get("grain_building_card",{})
				if not grain.is_empty() and command.get("card")==grain["id"]:
					return Research.inspect(_state["progression"],command) if kind=="claim_card" and opening.get("superfast_step")==0 and grain["id"] in _state["progression"]["discovered"] and not grain["id"] in _state["progression"]["completed"] else {"ok":false,"cost":0,"reason":""}
				if command.get("card")==opening["definition"].get("mining_population_card",{}).get("id"):
					return Research.inspect(_state["progression"],command)
				for key: String in ["housing_advances","grain_advances","ore_advances"]:
					for level: Dictionary in opening["definition"].get(key,[]):
						if command.get("card")==level["id"]: return Research.inspect(_state["progression"],command)
			if kind=="open_chest" and opening.has("chests"):
				var chests:=preload("res://simulation/authored_chests.gd").new()
				chests.configure(self,_state,[])
				return chests.inspect(command)
			if kind in ["campaign_select_dock","campaign_dock_go"]:
				var dock:=source_dock_site()
				var step: int=opening.get("events_step",-1)
				return {"ok":(step==0 or kind=="campaign_dock_go" and step==1) and not dock.is_empty() and command.get("id")==dock["id"] and dock["complete"],"cost":0,"reason":""}
			if kind=="campaign_first_voyage_returned":
				return {"ok":opening.get("events_step")==0 and command.get("won") is bool,"cost":0,"reason":""}
			if kind=="leash": return CampaignLeash.inspect(self,_state,command)
			if kind=="campaign_show_level_card": return {"ok":opening.get("leash_step")==0 and not opening.get("pit_card_open",false),"cost":0,"reason":""}
			if kind=="campaign_dismiss_level_card": return {"ok":opening.get("pit_card_open",false) or leash_card or opening.get("dock_card_open",false) or opening.get("fountain_card_open",false) or farm_step==1 or opening.get("superfast_step")==1,"cost":0,"reason":""}
			if kind=="campaign_activate_shrine":
				var site_id: Variant=command.get("id")
				var definition: Dictionary=opening["definition"]
				var site:=source_shrine_site(str(site_id))
				var eligible: bool=site_id==definition.get("discovery_site_id") or opening.get("leash_step")==4 and site_id==definition.get("dock_site_id","") or source_land_expansion(site)
				return {"ok":eligible and not leash_card and not opening.get("dock_card_open",false) and site.get("repaired",false) and not site["complete"],"cost":0,"reason":""}
			if kind=="repair_shrine":
				var site:=source_shrine_site(str(command.get("id","")))
				if source_ark_site(site): return inspect_ark_builder(site)
			if kind=="campaign_ark_sail":
				var site:=source_shrine_site(str(command.get("id","")))
				return {"ok":source_ark_site(site) and not ark_manifest().is_empty(),"cost":0,"reason":""}
			if kind=="collect" and command.has("home_id"): return _inspect_collection(command)
		if _state["opening"]["phase"]=="belief":
			var belief_step: int=_state["opening"]["belief_step"]
			if kind in ["campaign_show_level_card","campaign_dismiss_level_card"]:
				return {"ok":belief_step==(0 if kind=="campaign_show_level_card" else 1),"cost":0,"reason":""}
			if belief_step>=4: return {"ok":false,"cost":0,"reason":""}
			if kind=="collect" and command.has("home_id"): return _inspect_collection(command)
			if kind=="sculpt_drag": return _validate_drag(command)
			return {"ok":false,"cost":0,"reason":""}
		if _state["opening"]["phase"]=="shrine":
			var shrine_step: int=_state["opening"]["shrine_step"]
			if kind in ["campaign_show_level_card","campaign_dismiss_level_card"]:
				return {"ok":shrine_step==(0 if kind=="campaign_show_level_card" else 1),"cost":0,"reason":""}
			if kind=="campaign_activate_shrine":
				var site := source_shrine_site()
				return {"ok":shrine_step==3 and command.get("id")==site.get("id") and site.get("repaired",false) and not site["complete"],"cost":0,"reason":""}
			if not shrine_housing: return {"ok":false,"cost":0,"reason":""}
		if _state["opening"]["phase"]=="timeline" and not timeline_housing:
			var opening: Dictionary=_state["opening"]
			var ready: bool=Opening.supports_timeline(opening)
			if kind=="campaign_timeline_open": return {"ok":ready and opening["timeline_step"]==0 and not opening.get("timeline_open",false),"cost":0,"reason":""}
			if kind=="campaign_timeline_close": return {"ok":ready and opening.get("timeline_open",false) and opening.get("timeline_input_lock",3)==0,"cost":0,"reason":""}
			if kind=="research_card" and ready and opening.get("timeline_open",false) and opening.get("timeline_input_lock",3)==1 and command.get("card")==opening["level_card"]: return Research.inspect(_state["progression"],command)
			return {"ok":false,"cost":0,"reason":""}
		if kind=="tap_object":
			return {"ok":Opening.can_tap_rock(_state,int(command.get("cell",-1))),"cost":0,"reason":""}
		if kind in ["campaign_show_level_card","campaign_dismiss_level_card"] and Opening.supports_level_card(_state["opening"]):
			return {"ok":_state["opening"]["promised_step"]==(7 if kind=="campaign_show_level_card" else 8),"cost":0,"reason":""}
		var growing := Opening.supports_growth(_state["opening"]) or timeline_housing or shrine_housing or discovery
		if kind=="sprog" and (Opening.supports_expansion(_state["opening"]) or growing):
			for home: Dictionary in _state["homes"]:
				if home["id"]==command.get("home_id") and home.get("settlement_core",false) and Economy.settlement(_state,home["settlement_id"]).get("role")!="builder":
					return {"ok":false,"cost":0,"reason":""}
			var ready: bool=timeline_housing or shrine_housing or discovery or _state["opening"]["promised_step"] in [4,6] and _state["opening"]["globals"].get("sprog_unlocked",false)
			var candidate := Opening.release_candidate(_state,int(command.get("home_id",-1))) if ready else {}
			ready=not candidate.is_empty()
			if ready and (shrine_housing or discovery):
				var shrine_plan := source_shrine_plan(candidate)
				if not shrine_plan.is_empty(): return {"ok":true,"cost":0,"reason":"","shrine_plan":shrine_plan}
			if ready and growing:
				var seeking := 0
				for follower: Dictionary in _state["followers"]:
					if follower.get("seeking_plot",false): seeking+=1
				var origin := Vector2i(roundi(candidate["follower"]["x"]),roundi(candidate["follower"]["z"]))
				ready=false
				if has_room_for_growth(seeking):
					var reachable := 0
					for plot: Dictionary in promised_growth_plots():
						if source_abode_wheat_cost(plot)>int(_state.get("wheat",0)): continue
						if not promised_plot_reachable(plot,origin): continue
						reachable+=1
						if reachable>seeking:
							ready=true
							break
			return {"ok":ready,"cost":0,"reason":""}
		if Opening.supports_first_chest(_state["opening"]):
			if kind=="open_chest":
				var chests := preload("res://simulation/authored_chests.gd").new()
				chests.configure(self,_state,[])
				return chests.inspect(command)
			return {"ok":false,"cost":0,"reason":""}
		if growing:
			if kind=="sculpt_drag": return _validate_drag(command)
			if kind=="tap_tree":
				var cell := int(command.get("cell",-1))
				var width := int(_state["width"])
				return {"ok":cell>=0 and cell<width*width and can_act_at(cell%width,cell/width) and tree_at(cell%width,cell/width),"cost":0,"reason":""}
			return {"ok":false,"cost":0,"reason":""}
		if Opening.supports_level_card(_state["opening"]): return {"ok":false,"cost":0,"reason":""}
		if Opening.supports_first_plot(_state["opening"]) or Opening.supports_expansion(_state["opening"]):
			if kind=="sculpt_drag": return _validate_drag(command)
			return {"ok":false,"cost":0,"reason":""}
		if _state["opening"].get("handoff",{}).get("available",true)==false:
			return {"ok":false,"cost":0,"reason":""}
		if _state["opening"]["phase"]=="trailing": return {"ok":false,"cost":0,"reason":""}
		if not kind in ["sculpt_drag","raise","lower","dig"]: return {"ok":false,"cost":0,"reason":""}
	if _state.has("voyage"):
		var voyage_check := Voyage.inspect(_state,command)
		if not voyage_check["ok"] or kind in ["start_voyage","voyage_power","voyage_temple","voyage_chest"]: return voyage_check
	if kind=="tap_tree":
		var cell := int(command.get("cell",-1))
		var valid: bool = cell>=0 and cell<int(_state["width"])*int(_state["width"]) and tree_at(cell%int(_state["width"]),cell/int(_state["width"]))
		if _state.has("progression"): valid=valid and Influence.command_allowed(_state,command)
		return {"ok":valid,"cost":0,"reason":""}
	var home_cost: int = _state.get("home_cost", HOME_COST)
	if _state.has("progression"):
		if not Influence.command_allowed(_state,command): return {"ok":false,"cost":0,"reason":""}
		if kind in ["collect","collect_settlement"] and command.get("gesture")=="drag" and not preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"BeliefLeashing"):
			return {"ok":false,"cost":0,"reason":"Belief dragging is not unlocked."}
		if kind=="collect_settlement" or kind=="use_power" and command.get("power","") in Economy.POWERS: return Economy.inspect(self,_state,command)
		if kind=="deploy_worker": return plan_worker(int(command.get("id",-1)))
		if kind in ["claim_card","research_card","open_chest","tap_object","use_power"]:
			var result := Progression.inspect(_state,command)
			if result["ok"] and command.get("power")=="GodPower_Beautify":
				return _inspect_beautify(command,result)
			return result
		if kind=="repair_shrine":
			for shrine: Dictionary in _state["progression"]["shrines"]:
				if shrine["id"]==command.get("id") and not shrine["started"]:
					if shrine.get("complete",false) or str(shrine.get("model_id","")).is_empty() or int(shrine.get("build_ticks",0))<=0: return {"ok":false,"cost":0,"reason":""}
					var reward: String = shrine["card"]
					var expansion: bool = shrine.get("expands_influence",false) or reward=="Card_Expansion"
					if not expansion and not reward.trim_prefix("Card_") in Progression.SUPPORTED_POWERS and not Progression.implemented_card(_state["progression"],reward): return {"ok":false,"cost":0,"reason":""}
					var payment := preload("res://simulation/temple_rules.gd").costs(_state,shrine)
					if not payment["ok"]: return {"ok":false,"cost":0,"reason":"","missing":payment["missing"]}
					return _inspect_shrine_repair(shrine,payment["costs"])
			return {"ok":false,"cost":0,"reason":""}
		if kind=="dig" and not "DoubleClickSculpt" in _state["progression"]["unlocks"]: return {"ok":false,"cost":0,"reason":""}
		if kind=="upgrade_home":
			for home: Dictionary in _state["homes"]:
				if home["id"]!=int(command.get("id",-1)) or home.get("kind","")!="" or home["progress"]<int(home.get("build_ticks",BUILD_TICKS)): continue
				var rank := mini(int(home.get("rank",1))+1,int(_state["progression"]["max_rank"]))
				var specification := cached_house_spec(rank)
				if specification.is_empty() or (specification["rank"]<=home.get("rank",1) and specification["family"]<=home.get("family",0)): break
				var result := _validate({"type":"home","x":home["x"],"z":home["z"],"rank":rank},home["id"])
				result["home_id"] = home["id"]
				return result
			return {"ok":false,"cost":0,"reason":""}
	if kind=="dig":
		var digging := command.duplicate(true)
		digging["type"] = "lower"
		digging["radius"] = 0
		return _validate(digging)
	if command.get("type") == "claim_card" and _state.has("campaign"):
		var card: String = command.get("card", "")
		for row: Array in _state["campaign"]["population_unlocks"]:
			if row.size() < 2 or not str(row[0]).is_valid_int() or row[1] != card: continue
			if _state["followers"].size() >= int(row[0]) and not card in _state["campaign"]["cards"]:
				return {"ok": true, "reason": "Discovered " + card.trim_prefix("Card_").replace("_", " "), "cost": 0}
		return {"ok": false, "reason": "Grow your population to discover this card.", "cost": 0}
	if kind == "sculpt_drag":
		return _validate_drag(command)
	if kind == "collect":
		return _inspect_collection(command)
	var x := int(command.get("x", -1))
	var z := int(command.get("z", -1))
	var width: int = _state["width"]
	if x < 0 or z < 0 or x >= width or z >= width:
		return {"ok": false, "reason": "Choose a place inside your world.", "cost": 0}
	if kind == "place_model":
		var identifier: String = str(command.get("model_id", ""))
		if not _models.has(identifier):
			return {"ok": false, "reason": "Choose an available original model in the library.", "cost": 0}
		if _state["props"].size() >= 4096:
			return {"ok": false, "reason": "This world has reached its model placement limit.", "cost": 0}
		return {"ok": true, "reason": "Place " + str(_models[identifier]["name"]), "cost": 0}
	if kind in ["raise", "lower"]:
		var radius := clampi(int(command.get("radius", 0)), 0, 2)
		var cells: Array = []
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dz * dz > radius * radius:
					continue
				var px := x + dx
				var pz := z + dz
				if not can_act_at(px,pz): return {"ok":false,"cost":0,"reason":""}
				if px < 1 or pz < 1 or px >= width - 1 or pz >= width - 1:
					continue
				if _occupied(px, pz):
					return {"ok": false, "reason": "Protect your homes: sculpt outside their plots.", "cost": 0}
				var height := height_at(px, pz)
				if (kind == "raise" and height < MAX_HEIGHT) or (kind == "lower" and height > 0):
					cells.append(pz * width + px)
		if cells.is_empty():
			return {"ok": false, "reason": "This land has reached its height limit.", "cost": 0}
		var sculpt_cost := ceili(cells.size()*runtime_value("sculpt_cost",1.0))
		return {"ok": _state["belief"] >= sculpt_cost, "reason": "Sculpt %d cells · %d belief" % [cells.size(), sculpt_cost] if _state["belief"] >= sculpt_cost else "Gather more belief to sculpt.", "cost": sculpt_cost, "cells": cells}
	if kind in ["home","work_plot"]:
		if ignore_home==-1 and not _state.has("campaign") and _state["homes"].size() >= 24:
			return {"ok": false, "reason": "This island supports up to 24 homes.", "cost": home_cost}
		var height := height_at(x, z)
		var rank: int=int(command.get("rank",_state.get("progression",{}).get("max_rank",1)))
		var authored:=Weyworld.house_spec(_state,rank,x,z) if kind=="home" and ignore_shrine.is_empty() else {}
		var specification := Economy.plot_spec(_state,command) if kind=="work_plot" else (cached_house_spec(rank) if authored.is_empty() else authored)
		if specification.is_empty(): return {"ok":false,"cost":0,"reason":""}
		if authored.is_empty():
			var half:=float(specification["span"])*0.5
			var land_reason:=Weyworld.placement_reason(_state,specification.get("kind","home"),x+half,z+half)
			if not land_reason.is_empty(): return {"ok":false,"cost":0,"reason":land_reason}
		if kind=="work_plot" or not ignore_shrine.is_empty(): home_cost=0
		var resource_cost := {}
		if _state.has("progression") and ignore_shrine.is_empty():
			for pair: Array in [["wheat","Farming"],["ore","Mining"]]:
				if not Economy.spends_resource(_state,pair[0]): continue
				var required := int(specification.get(pair[0]+"_cost",0))
				if int(_state.get(pair[0],0))<required: return {"ok":false,"cost":0,"reason":"","missing":{pair[0]:required-int(_state.get(pair[0],0))}}
				resource_cost[pair[0]]=required
		var span: int = specification["span"]
		_prepare_plan_reservations()
		for dz in range(span):
			for dx in range(span):
				if not can_act_at(x+dx,z+dz): return {"ok":false,"cost":0,"reason":""}
				var reserved: String = _plan_reserved.get((z+dz)*width+x+dx,"")
				if not reserved.is_empty() and reserved!="home:%d" % ignore_home and reserved!="shrine:"+ignore_shrine: return {"ok":false,"cost":0,"reason":""}
				if x + dx >= width - 1 or z + dz >= width - 1 or height <= 0 or height_at(x + dx, z + dz) != height or _occupied(x + dx, z + dz,ignore_home):
					return {"ok": false, "reason": "A home needs a free, flat 2 × 2 plot on dry land.", "cost": home_cost}
		for dz in range(span):
			for dx in range(span):
				var obstruction := plot_obstruction(x+dx,z+dz)
				if not obstruction.is_empty(): return {"ok":false,"cost":0,"reason":"Clear the %s from this plot first."%obstruction,"obstruction":{"kind":obstruction,"x":x+dx,"z":z+dz}}
		if _state["belief"] < home_cost:
			return {"ok": false, "reason": "A home needs %d belief." % home_cost, "cost": home_cost}
		var work_cells := [Vector2i(x - 1, z), Vector2i(x, z - 1), Vector2i(x + span, z), Vector2i(x, z + span)]
		for follower: Dictionary in _state["followers"]:
			if kind=="work_plot" and not Economy.worker_available(_state,follower,Economy.settlement(_state,int(command.get("settlement_id",-1)))): continue
			if follower.has("workplace") or follower.has("ark_passenger") or follower.has("weyworld_destination"): continue
			if follower["job"] != -1:
				continue
			var start := Vector2i(roundi(follower["x"]), roundi(follower["z"]))
			if start.distance_to(Vector2i(x,z))>float(specification.get("vision_radius",1000000)): continue
			if start.x >= x and start.x < x + span and start.y >= z and start.y < z + span:
				continue
			for work: Vector2i in work_cells:
				if height_at(work.x, work.y) <= 0 or _occupied(work.x, work.y,ignore_home):
					continue
				# Prospective plot cells must not be used as the approach route.
				var route := _route(start, work,ignore_home)
				var crosses_plot := false
				for cell: int in route:
					var cx := cell % width
					var cz := cell / width
					if cx >= x and cx < x + span and cz >= z and cz < z + span:
						crosses_plot = true
				if (start == work or not route.is_empty()) and not crosses_plot:
					return {"ok": true, "reason": "Build a home · %d belief" % home_cost, "cost": home_cost, "builder": follower["id"], "work_x": work.x, "work_z": work.y, "path": route,"specification":specification,"resource_cost":resource_cost}
		return {"ok": false, "reason": "No free follower can reach this plot. Try nearby or connect the terraces.", "cost": home_cost}
	if kind == "sheep":
		if _completed_homes() == 0:
			return {"ok": false, "reason": "Complete your first home to unlock sheep.", "cost": SHEEP_COST}
		if _state["sheep"].size() >= 40:
			return {"ok": false, "reason": "Your flock has reached 40 sheep.", "cost": SHEEP_COST}
		var valid: bool = height_at(x, z) > 0 and not _occupied(x, z) and _state["belief"] >= SHEEP_COST
		return {"ok": valid, "reason": "Welcome a sheep · %d belief" % SHEEP_COST if valid else "Choose free dry land and gather %d belief." % SHEEP_COST, "cost": SHEEP_COST}
	return {"ok": false, "reason": "Unknown action.", "cost": 0}


func step(commands: Array = []) -> Array:
	var events: Array = []
	var rock_tiles := {}
	var discovered_before: Array = _state.get("progression",{}).get("discovered",[]).duplicate()
	for command: Dictionary in commands:
		queue_command(command)
	for command: Dictionary in _pending:
		var result := _validate(command)
		var sculpt_context := {}
		if _state.has("opening") and _state["opening"]["phase"]=="belief" and command.get("type")=="sculpt_drag":
			sculpt_context=_sculpt_context(command,result.get("edits",[]))
			var intro := Opening.new()
			intro.configure(self,_state,events)
			intro.sculpt_started(sculpt_context)
		if not result["ok"]:
			events.append({"type": "rejected", "message": result["reason"]})
			if command.get("type")=="leash" and _state.has("opening") and result.get("shortage",false):
				var intro := Opening.new()
				intro.configure(self,_state,events)
				intro.leash_release(command,result,false)
			if _state.has("opening") and command.get("type","") in ["sculpt_drag","raise","lower","dig"]:
				var intro := Opening.new()
				intro.configure(self,_state,events)
				intro.sculpt_failed(sculpt_context)
			continue
		_state["belief"] -= result["cost"]
		for resource: String in result.get("resource_cost",{}): _state[resource]=int(_state.get(resource,0))-int(result["resource_cost"][resource])
		var kind: String = command["type"]
		if result.has("plot_command"):
			command=result["plot_command"]
			kind=command["type"]
		if _state.has("leash_lesson"):
			LeashLesson.apply(self,_state,command,result,events)
		elif _state.has("opening") and kind=="use_power" and command.get("power")==Rain.POWER:
			_state["opening"]["rain_cast"]={"x":command["x"],"z":command["z"]}
		elif kind=="campaign_rain_stop":
			_state["opening"].erase("rain_cast")
		elif kind in ["campaign_cliff_upgrade","campaign_belief_collector_upgrade"]:
			var p: Dictionary=_state["progression"]
			if not p.has("script_unlocks"): p["script_unlocks"]={}
			p["script_unlocks"][result["upgrade"]]=true
			p["revision"]+=1
		elif _state.has("opening") and kind=="use_power" and command.get("power")==Collector.POWER:
			Collector.place(_state,result,TICK_SECONDS)
			_spatial_revision+=1
			preload("res://simulation/source_plot_schedule.gd").mark(_state["source_plots"]["schedule"],result["x"],result["z"])
		elif _state.has("opening") and kind=="use_power" and command.get("power")==Fountain.POWER:
			var fountain:=Fountain.place(_state,result)
			_spatial_revision+=1
			var schedule:=preload("res://simulation/source_plot_schedule.gd")
			schedule.mark(_state["source_plots"]["schedule"],fountain["x"],fountain["z"])
			var intro:=Opening.new()
			intro.configure(self,_state,events)
			intro.fountain_placed(fountain)
		elif kind=="campaign_fountain_tap":
			Fountain.celebrate(_state,command["id"],TICK_SECONDS)
			var intro:=Opening.new()
			intro.configure(self,_state,events)
			intro.fountain_celebrated(command["id"])
			events.append({"type":"source_sound","event":"Fountain celebration"})
		elif kind=="campaign_ack" and _state.has("weyworld"):
			Weyworld.acknowledge(self,_state,int(command["id"]))
		elif kind=="leash" and _state.has("weyworld"):
			if result.has("home"):
				release_ark_passenger(result["home"],result["follower"],result["target"])
			for assignment: Dictionary in result["orders"]:
				assignment["agent"].merge({"weyworld_destination":result["destination"],"path":assignment["path"],"state":"walking"},true)
			Weyworld.first_leash(_state)
		elif kind=="leash":
			if result.has("field_plan"): deploy_source_worker(result["field_plan"],events)
			else:
				CampaignLeash.apply(self,_state,result)
				var intro := Opening.new()
				intro.configure(self,_state,events)
				intro.leash_release(command,result,true)
		elif kind in ["start_voyage","voyage_power","voyage_temple","voyage_chest"]:
			Voyage.command(self,_state,command,events)
		elif kind == "sculpt_drag":
			for edit: Dictionary in result["edits"]:
				_dirty_rock_tiles(rock_tiles,int(edit["cell"]))
				if _state.has("opening") and int(edit["height"])==0: _state["opening"]["submerged_levels"][str(edit["cell"])]=19
				if _state["terrain"][edit["cell"]] == 0 and edit["height"] > 0: _dry_land += 1
				elif _state["terrain"][edit["cell"]] > 0 and edit["height"] == 0: _dry_land -= 1
				_state["terrain"][edit["cell"]] = edit["height"]
			_state["sculpted"] += 1
			_state["terrain_revision"] += 1
			_recover_agents()
			if _state.has("opening"):
				var intro := Opening.new()
				intro.configure(self,_state,events)
				intro.sculpt_completed(sculpt_context)
		elif kind in ["raise", "lower", "dig"]:
			for cell: int in result["cells"]:
				_dirty_rock_tiles(rock_tiles,cell)
				if kind == "raise" and _state["terrain"][cell] == 0: _dry_land += 1
				elif kind in ["lower","dig"] and _state["terrain"][cell] == 1: _dry_land -= 1
				_state["terrain"][cell] += 1 if kind == "raise" else -1
			_state["terrain_revision"] += 1
			_recover_agents()
			if _state.has("opening"):
				var intro := Opening.new()
				intro.configure(self,_state,events)
				intro.sculpt_completed()
		elif kind=="deploy_worker":
			if _state.has("opening"): deploy_source_worker(result,events)
			else: Economy.staff_existing_plot(_state,result)
		elif kind=="weyworld_release_ark":
			release_ark_passenger(result["home"],result["follower"],result["target"])
		elif kind=="repair_shrine" and result.has("ark_plan"):
			for follower: Dictionary in _state["followers"]:
				if follower["id"]==result["builder"]:
					assign_source_shrine(follower,result["ark_plan"])
					break
		elif kind in ["home","repair_shrine","upgrade_home","work_plot"]:
			var home := {"id": _state["next_id"], "x": int(command.get("x",0)), "z": int(command.get("z",0)), "progress": 0, "stored": 0, "residents": 0, "builder": result["builder"], "work_x": result["work_x"], "work_z": result["work_z"], "stalled": false}
			if kind=="upgrade_home":
				for existing: Dictionary in _state["homes"]:
					if existing["id"]==result["home_id"]:
						home=existing
						home.merge({"progress":0,"builder":result["builder"],"work_x":result["work_x"],"work_z":result["work_z"],"stalled":false},true)
						break
			if _state.has("progression"): home.merge(result["specification"],true)
			if home.has("capacity"): home["capacity"]=int(home["capacity"])
			home["access_path"]=result["path"].duplicate()
			if kind=="repair_shrine":
				var shrine: Dictionary = result["shrine"]
				home.merge({"kind":"shrine","shrine_id":shrine["id"],"x":result["plot_x"],"z":result["plot_z"],"build_ticks":shrine["build_ticks"],"model_id":shrine["model_id"]},true)
				home["temple_work"]=0.0
				for field: String in ["build_capacity","build_priority","rotation"]:
					if shrine.has(field): home[field]=shrine[field]
				for item: Dictionary in _state["progression"]["shrines"]:
					if item["id"]==shrine["id"]: item["started"]=true
			if kind!="upgrade_home":
				_state["next_id"] += 1
				_state["homes"].append(home)
			if kind in ["home","upgrade_home"]: AbodeBeauty.refresh(_state,[home])
			_spatial_revision+=1
			for follower: Dictionary in _state["followers"]:
				if follower["id"] == result["builder"]:
					follower["job"] = home["id"]
					follower.erase("work_x")
					follower.erase("work_z")
					follower["path"] = result["path"]
					follower["state"] = "walking"
					if kind=="work_plot":
						follower["workplace"]=home["id"]
						follower["settlement_id"]=home["settlement_id"]
						follower["profession"]="farmer" if home["kind"]=="farm" else "miner"
			_recover_agents()
		elif kind == "sheep":
			_state["sheep"].append(_agent(command["x"], command["z"], true))
		elif kind=="tap_tree":
			var cell := int(command["cell"])
			if _state.has("source_plots"): preload("res://simulation/source_plot_schedule.gd").mark(_state["source_plots"]["schedule"],cell%int(_state["width"]),cell/int(_state["width"]))
			var key := str(cell)
			_state["tree_taps"][key]=int(_state["tree_taps"].get(key,0))+1
			var vegetation: Dictionary = _state.get("progression",{}).get("rules",{}).get("vegetation",{})
			if int(_state["tree_taps"][key])>=int(vegetation.get("taps_to_clear",1)):
				_state["removed_trees"][key]=true
				_state["vegetation_revision"]+=1
				if _state.has("progression") and preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"TreeRockBelief"):
					_state["belief"]+=int(vegetation.get("belief",{}).get(str(_tree_cells[cell]),0))
				events.append({"type":"tree_removed","cell":cell})
				if _state.has("opening") and (Opening.supports_growth(_state["opening"]) or Opening.supports_discovery(_state["opening"])):
					var intro := Opening.new()
					intro.configure(self,_state,events)
					if Opening.supports_discovery(_state["opening"]): intro.discovery_hook("onTreeDestroyed",[cell])
					else: intro.promised_hook("onTreeDestroyed",[cell])
		elif kind.begins_with("campaign_farm_"):
			var intro:=Opening.new()
			intro.configure(self,_state,events)
			intro.farming_action(kind,result)
		elif kind in ["campaign_builder_preview","campaign_mining_preview"]:
			_state["opening"][kind.trim_prefix("campaign_")]={"x":result["x"],"z":result["z"],"members":result["members"]}
		elif kind in ["campaign_builder_confirm","campaign_mining_confirm"]:
			_state["opening"].erase(kind.get_slice("_",1)+"_preview")
			Farming.merge(self,_state,result)
		elif kind in ["campaign_builder_cancel","campaign_mining_cancel"]:
			_state["opening"].erase(kind.get_slice("_",1)+"_preview")
		elif kind in ["campaign_ack","campaign_view","sprog","campaign_show_level_card","campaign_dismiss_level_card","campaign_timeline_open","campaign_timeline_close","campaign_activate_shrine","campaign_leash_lesson_completed","campaign_select_dock","campaign_dock_go","campaign_first_voyage_returned"]:
			var intro := Opening.new()
			intro.configure(self,_state,events)
			if kind=="campaign_view": intro.observe(command)
			elif kind=="campaign_leash_lesson_completed": intro.finish_leash_lesson()
			elif kind=="campaign_select_dock":
				_state["opening"]["globals"]["selectedWorldObject"]=command["id"]
				intro.dock_event_hook("onObjectSelected",[command["id"]])
			elif kind=="campaign_dock_go":
				_state["opening"]["globals"].erase("selectedWorldObject")
				intro.dock_event_hook("onObjectSelected",[null])
				events.append({"type":"campaign_start_first_voyage" if _state["opening"]["events_step"]==0 else "campaign_open_voyages"})
			elif kind=="campaign_first_voyage_returned": intro.finish_first_voyage(command["won"])
			elif kind=="sprog": intro.release_builder(int(command["home_id"]),result.get("shrine_plan",{}))
			elif kind=="campaign_activate_shrine":
				var site := source_shrine_site(str(command["id"]))
				if preload("res://simulation/temple_rules.gd").complete(_state["progression"],site["id"]):
					_give_progression_card(site["card"])
					if Opening.supports_discovery(_state["opening"]):
						var opening: Dictionary=_state["opening"]
						var dock: bool=site["id"]==opening["definition"].get("dock_site_id")
						if dock or site["id"]==opening["definition"].get("discovery_site_id"):
							opening["dock_card_open" if dock else "pit_card_open"]=true
							if not site["card"] in _state["progression"]["completed"]: Progression.complete(_state,site["card"])
							events.append({"type":"campaign_show_card","card":site["card"]})
							if dock: intro.leash_hook("onCardShown",[site["card"]])
							else: intro.discovery_hook("onCardShown",[site["card"]],"PitOfDoom")
					else: intro.shrine_hook("onCardReceived",[site["card"]])
			elif kind=="campaign_dismiss_level_card" and _state["opening"].get("pit_card_open",false):
				var card: String=_state["opening"]["globals"]["CARD_DISCOVERY"]
				intro.discovery_hook("onCardDismissed",[card])
				intro.discovery_hook("onCardDismissed",[card],"PitOfDoom")
			elif kind=="campaign_dismiss_level_card" and _state["opening"].erase("dock_card_open"):
				intro.leash_hook("onCardDismissed",[source_dock_site()["card"]])
			elif kind=="campaign_dismiss_level_card" and _state["opening"].get("farming_step")==1:
				intro.farming_hook("onCardDismissed",[_state["opening"]["definition"]["farming_population_card"]["source_id"]])
			elif kind=="campaign_dismiss_level_card" and _state["opening"].get("superfast_step")==1:
				intro.superfast_hook("onCardDismissed",[_state["opening"]["definition"]["grain_building_card"]["id"]])
			elif kind=="campaign_dismiss_level_card" and _state["opening"].erase("fountain_card_open"):
				_state["opening"]["persistent"]["HappinessProgress"]=5
				intro.clear_message(5603)
			elif kind in ["campaign_show_level_card","campaign_dismiss_level_card"]: intro.level_card_action(kind=="campaign_show_level_card")
			elif kind in ["campaign_timeline_open","campaign_timeline_close"]: intro.timeline_action(kind=="campaign_timeline_open")
			else: intro.acknowledge(int(command["id"]))
		elif kind == "place_model":
			_state["props"].append({"id": _state["next_id"], "model_id": command["model_id"],
				"x": int(command["x"]), "z": int(command["z"]), "turns": posmod(int(command.get("turns", 0)), 4)})
			_state["next_id"] += 1
		elif kind == "claim_card":
			if _state.has("opening") and command["card"]==Fountain.CARD:
				var intro:=Opening.new()
				intro.configure(self,_state,events)
				intro.show_fountain_card(command["card"])
				continue
			elif _state.has("opening") and command["card"]=="Card_Settlement_Farming":
				var intro:=Opening.new()
				intro.configure(self,_state,events)
				intro.farming_action("campaign_farm_card",result)
				continue
			elif _state.has("opening") and command["card"]=="Card_GrainToBuild":
				var intro:=Opening.new()
				intro.configure(self,_state,events)
				intro.show_grain_building_card(command["card"])
				continue
			elif _state.has("progression"):
				Progression.complete(_state,command["card"])
				_refresh_abode_timers()
			else: _state["campaign"]["cards"].append(command["card"])
		elif kind=="research_card":
			var completed: bool=Research.apply(_state["progression"],command)
			if _state.has("opening") and _state["opening"].has("chest_capacity"):
				preload("res://simulation/source_availability.gd").spend(_state["opening"]["chest_capacity"],Research.canonical(_state["progression"],command["sticker"]),1)
			if completed:
				Progression.complete(_state,command["card"])
				if not _state.has("opening"): _refresh_abode_timers()
				events.append({"type":"claim_card","card":command["card"]})
				if _state.has("opening") and Opening.supports_timeline(_state["opening"]):
					var intro := Opening.new()
					intro.configure(self,_state,events)
					intro.timeline_hook("onAdvanceComplete",[command["card"]])
		elif kind=="collect_settlement" or kind=="use_power" and command.get("power","") in Economy.POWERS:
			Economy.apply(_state,command,result)
		elif kind in ["open_chest","tap_object","use_power"]:
			if _state.has("opening") and kind=="open_chest":
				var chests := preload("res://simulation/authored_chests.gd").new()
				chests.configure(self,_state,events)
				chests.open(command)
			elif _state.has("opening") and kind=="tap_object":
				var intro := Opening.new()
				intro.configure(self,_state,events)
				intro.tap_rock(int(command["cell"]))
				if _state.has("source_plots"): preload("res://simulation/source_plot_schedule.gd").mark(_state["source_plots"]["schedule"],int(command["cell"])%int(_state["width"]),int(command["cell"])/int(_state["width"]))
			else: _apply_progression(command,events,result)
		elif kind == "collect":
			var resource: String=result.get("resource","belief")
			_state[resource]=int(_state.get(resource,0))+int(result["amount"])
			if resource=="belief": _state["collected"] += result["amount"]
			for home: Dictionary in _state["homes"]:
				if home["id"] in result["homes"]: home["stored" if resource=="belief" else "harvest_accumulator"] = 0
			if _state.has("opening") and _state["opening"]["phase"]=="belief":
				var intro := Opening.new()
				intro.configure(self,_state,events)
				for id: int in result["homes"]: intro.belief_hook("onCollectBelief",[id])
			elif _state.has("opening") and resource=="wheat":
				var intro:=Opening.new()
				intro.configure(self,_state,events)
				for id: int in result["homes"]: intro.superfast_hook("onCollectGrain",[id])
		var event := {"type":kind,"message":result["reason"]}
		if kind=="claim_card": event["card"]=command["card"]
		if kind=="use_power": event["power"]=command["power"]
		events.append(event)
	_pending.clear()
	if _state.has("tree_response") and not rock_tiles.is_empty():
		if preload("res://simulation/source_tree_response.gd").refresh(_state,rock_tiles,_tree_tiles,_tree_rows,source_tree_target,float(_state["tick"])*TICK_SECONDS):
			_state["vegetation_revision"]+=1
			_spatial_revision+=1
	if _state.has("rock_motion"):
		var motion := preload("res://simulation/source_rock_motion.gd")
		if not rock_tiles.is_empty(): motion.refresh(_state,rock_tiles,source_rock_target)
		var alive := func(cell: int) -> bool: return preload("res://simulation/authored_rocks.gd").alive(_state,cell)
		motion.advance(_state["rock_motion"],TICK_SECONDS,float(_state["opening"]["definition"]["rock_motion_config"]["duration"]),source_rock_target,alive)
	_state["tick"] += 1
	if _state.has("leash_lesson"):
		LeashLesson.advance(self,_state,events)
		return events
	_advance_land_effects(events)
	if _state.has("voyage"):
		Voyage.advance(self,_state,events)
		return events
	if _state.has("opening"):
		var intro := Opening.new()
		intro.configure(self,_state,events)
		_advance_source_plots()
		intro.advance()
		var rain:=Rain.advance(self,_state,TICK_SECONDS)
		if _state["opening"].get("farming_step",-1)>=4 or Farming.MINING_POWER in _state["progression"]["powers"]:
			for follower: Dictionary in _state["followers"]:
				if follower.has("workplace") and follower["job"]==-1: Economy.update_agent(self,_state,follower,rain)
		if CampaignLeash.enabled(_state):
			CampaignLeash.advance_walks(self,_state)
			var sacrificed:=Pit.advance(self,_state,_random,TICK_SECONDS,events)
			for id: int in sacrificed: intro.discovery_hook("onFollowerSacrificed",[id],"PitOfDoom")
			if not sacrificed.is_empty() and _state["followers"].is_empty():
				for start: Dictionary in _state["opening"]["definition"]["starts"]:
					var follower:=_agent(start["x"],start["z"],false)
					follower.merge({"rotation":start["source_args"][3],"female":start["source_args"][5]},true)
					_state["followers"].append(follower)
		if preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"Happiness"):
			preload("res://simulation/happiness.gd").advance(_state["progression"],TICK_SECONDS)
		preload("res://simulation/building_stats.gd").advance_belief(_state,int(_state.get("build_ticks",BUILD_TICKS)))
		Collector.advance(_state,TICK_SECONDS,events)
		_advance_source_influence(events)
		if _state["opening"].has("chests"):
			var chests := preload("res://simulation/authored_chests.gd").new()
			chests.configure(self,_state,events)
			if Opening.supports_discovery(_state["opening"]): chests.register_sticker_chests(_random)
			chests.advance(_random)
			if Opening.supports_first_chest(_state["opening"]) and events.any(func(event: Dictionary) -> bool: return event["type"]=="chest_opened"):
				intro.promised_hook("onStickerReceived",[])
		return events
	# Small passive income prevents a world from getting stuck after sculpting.
	if not _state.has("campaign") and _state["tick"] % 30 == 0:
		_state["belief"] += 1
	for follower: Dictionary in _state["followers"]:
		_update_agent(follower, false)
	_advance_construction()
	for sheep: Dictionary in _state["sheep"]:
		_update_agent(sheep, true)
	preload("res://simulation/building_stats.gd").advance_belief(_state,int(_state.get("build_ticks",BUILD_TICKS)))
	for home: Dictionary in _state["homes"]:
		var duration: int = home.get("build_ticks",_state.get("build_ticks", BUILD_TICKS))
		if home.get("kind","") in ["farm","mine","ark"]: continue
		if home.get("kind","")=="shrine":
			if home["progress"]>=duration: _complete_shrine(home)
			continue
		var birth_ticks := preload("res://simulation/building_stats.gd").birth_interval(_state,home)
		if home["progress"] >= duration and home["residents"] < int(home.get("capacity",2)) and _state["tick"] % birth_ticks == 0:
			if birth_space_available(home):
				var births := mini(maxi(0,int(home.get("breeder_count",1))),int(home.get("capacity",2))-int(home["residents"]))
				for birth in range(births): _state["followers"].append(_agent(home["work_x"], home["work_z"], false))
				home["residents"] += births
	if _state.has("campaign"): _update_campaign()
	if _state.has("weyworld"): Weyworld.advance(self,_state)
	if _state.has("progression"):
		preload("res://simulation/campaign_chests.gd").advance(self,_state,_random,events)
		preload("res://simulation/happiness.gd").advance(_state["progression"],TICK_SECONDS)
		for id: String in _state["progression"]["discovered"]:
			if not id in discovered_before: events.append({"type":"card_discovered","card":id})
	if not _state.has("campaign") and not _state["won"] and _state["sculpted"] > 0 and _completed_homes() >= 3 and _state["sheep"].size() >= 5 and _state["collected"] >= 20:
		_state["won"] = true
		events.append({"type": "victory", "message": "Sanctuary established. Your people and flock have a home."})
	return events


func _update_agent(agent: Dictionary, animal: bool) -> void:
	if agent.has("ark_passenger"): return
	if agent.has("weyworld_destination"):
		var goal: Array=agent["weyworld_destination"]
		var target:=Vector2i(goal[0],goal[1])
		var position:=Vector2(agent["x"],agent["z"])
		if position.distance_to(Vector2(target))<0.01:
			agent.erase("weyworld_destination")
			agent["path"]=[]
			agent["state"]="idle"
		else:
			if agent["path"].is_empty(): agent["path"]=_route(Vector2i(position.round()),target)
			finish_promised_approach(agent,target)
			advance_agent_path(agent,animal)
		return
	if not animal and _state.has("progression") and Economy.update_agent(self,_state,agent): return
	var start := Vector2i(roundi(agent["x"]), roundi(agent["z"]))
	var totem_target := Vector2i(-1,-1)
	if not animal and agent["job"]==-1 and _state.has("progression"):
		var p: Dictionary = _state["progression"]
		if p["totem"].get("active",false) and _state["followers"].find(agent)<int(p["totem_capacity"]):
			totem_target=Vector2i(p["totem"]["x"],p["totem"]["z"])
			if start==totem_target:
				agent["state"]="worshipping"
				agent["path"]=[]
				return
			if agent["path"].is_empty(): agent["path"]=_route(start,totem_target)
	if agent["job"] != -1:
		for home: Dictionary in _state["homes"]:
			if home["id"] != agent["job"]:
				continue
			var target := Vector2i(agent.get("work_x",home["work_x"]),agent.get("work_z",home["work_z"]))
			if home["progress"]>=int(home.get("build_ticks",_state.get("build_ticks",BUILD_TICKS))):
				agent["job"]=-1
				agent.erase("work_x")
				agent.erase("work_z")
				agent["state"]="idle"
				return
			if Vector2(agent["x"], agent["z"]).distance_to(Vector2(target)) < 0.05:
				agent["state"] = "building"
				home["stalled"] = false
				return
			if agent["path"].is_empty():
				agent["path"] = _route(start, target)
				home["stalled"] = agent["path"].is_empty()
				agent["state"] = "waiting" if home["stalled"] else "walking"
	elif agent["path"].is_empty():
		if totem_target.x>=0: return
		agent["wait"] -= 1
		if agent["wait"] > 0:
			return
		if animal and _random.randf() < 0.3:
			agent["state"] = "resting"
			agent["wait"] = _random.randi_range(25, 65)
			return
		var target := start + Vector2i(_random.randi_range(-4, 4), _random.randi_range(-4, 4))
		agent["path"] = _route(start, target)
		agent["wait"] = _random.randi_range(10, 35)
	advance_agent_path(agent,animal)


func advance_agent_path(agent: Dictionary,animal: bool) -> void:
	if not agent["path"].is_empty():
		var cell := int(agent["path"][0])
		var target := Vector2(cell % _state["width"], int(cell / _state["width"]))
		var current := Vector2(agent["x"], agent["z"])
		var speed := float(agent.get("leash_route_speed",0.0))
		if speed<=0.0: speed=runtime_value("sheep_speed",1.0) if animal else float(follower_values(agent).get("RouteSpeed",runtime_value("follower_speed",1.3)))
		var next := current.move_toward(target,speed*TICK_SECONDS)
		agent["x"] = next.x
		agent["z"] = next.y
		agent["state"] = "walking"
		if next.distance_to(target) < 0.001:
			agent["path"].pop_front()
			if agent["path"].is_empty():
				agent["state"] = "idle"


func _recover_agents() -> void:
	for agents: Array in [_state["followers"], _state["sheep"]]:
		for agent: Dictionary in agents:
			if agent.has("sacrifice_due") or agent.has("ark_passenger"): continue
			agent["path"] = []
			var origin := Vector2i(roundi(agent["x"]), roundi(agent["z"]))
			if _state.has("opening") and int(agent["id"]) in _state["opening"]["protected"]: continue
			# Snap before replanning so continuous positions cannot cut across cliffs.
			agent["x"] = float(origin.x)
			agent["z"] = float(origin.y)
			if height_at(origin.x, origin.y) > 0 and not _occupied(origin.x, origin.y):
				continue
			var best := Vector2i(-1, -1)
			# Search nearest Manhattan rings, preserving the old row/column tie order
			# without scanning a million-cell source map for a nearby safe tile.
			for radius in range(1,int(_state["width"])*2):
				for dz in range(-radius,radius+1):
					var dx := radius-absi(dz)
					for sx in [-dx,dx] if dx > 0 else [0]:
						var x: int = origin.x+sx
						var z := origin.y+dz
						if height_at(x,z)>0 and not _occupied(x,z):
							best = Vector2i(x,z)
							break
					if best.x>=0: break
				if best.x>=0: break

			if best.x >= 0:
				agent["x"] = float(best.x)
				agent["z"] = float(best.y)


func export_state() -> Dictionary:
	var detached := _state.duplicate(true)
	if detached.has("opening"):
		detached["opening"].erase("builder_preview")
		detached["opening"].erase("mining_preview")
	if detached.has("source_influence"): detached["source_influence"]=preload("res://simulation/source_influence_areas.gd").export_state(_state["source_influence"])
	if detached.has("map_fields"): detached["map_fields"]=SourceRaster.export_state(_state["map_fields"])
	if detached["terrain"] is PackedByteArray: detached["terrain"] = Array(detached["terrain"])
	if detached.get("rocks") is PackedByteArray: detached["rocks"] = Array(detached["rocks"])
	if detached.get("rock_heights") is PackedByteArray: detached["rock_heights"] = Array(detached["rock_heights"])
	if detached.has("opening") and detached["opening"]["definition"]["raw_floor"] is PackedByteArray: detached["opening"]["definition"]["raw_floor"]=Array(detached["opening"]["definition"]["raw_floor"])
	if detached.has("voyage"):
		for field: String in ["blight","swamp","beauty"]:
			if detached["voyage"].get(field) is PackedByteArray: detached["voyage"][field]=Array(detached["voyage"][field])
	return {"schema_version": 1, "state": Progression.canonical_numbers(detached), "rng_state": str(_random.state), "pending": Progression.canonical_numbers(_pending)}


func restore(data: Dictionary, random: RandomNumberGenerator) -> bool:
	if data.get("schema_version") != 1 or not data.get("state") is Dictionary or not str(data.get("rng_state", "")).is_valid_int():
		return false
	var state: Dictionary = data["state"]
	if state.has("map_fields") and not SourceRaster.valid(state["map_fields"]): return false
	if state.has("opening") and not Opening.valid(state["opening"]): return false
	if state.has("weyworld") and not Weyworld.valid(state): return false
	if state.has("source_influence"):
		if not state.has("opening") or not state.get("progression") is Dictionary: return false
		var area_rules: Variant=state["progression"].get("rules")
		if not area_rules is Dictionary or not preload("res://simulation/source_influence_areas.gd").valid(state["source_influence"],area_rules.get("influence_areas"),state["opening"]["definition"].get("influence_rules",{})): return false
	if state.has("source_plots"):
		if not state.has("source_influence") or state.get("width")!=1024 or not _source_plot_definition_supported(state["opening"]["definition"]): return false
		if not preload("res://simulation/source_plot_registry.gd").valid(state["source_plots"]): return false
	if state.has("rock_motion"):
		if not state.has("opening") or not state["opening"]["definition"].has("rock_motion_config"): return false
		if not preload("res://simulation/source_rock_motion.gd").valid(state["rock_motion"],state["opening"]["definition"].get("rock_objects",[]),float(state["opening"]["definition"]["rock_motion_config"]["duration"])): return false
	var width := int(state.get("width", 0))
	if width < 20 or width > 1024 or not (state.get("terrain") is Array or state.get("terrain") is PackedByteArray) or state["terrain"].size() != width * width:
		return false
	if state.has("voyage") and not Voyage.valid(state): return false
	if state.has("voyage_redeemed"):
		if not state["voyage_redeemed"] is Dictionary: return false
		for value: Variant in state["voyage_redeemed"].values():
			if not (value is int or value is float) or not is_finite(value) or value<0 or value!=int(value): return false
	for value: Variant in state["terrain"]:
		if not (value is int or value is float) or not is_finite(float(value)) or int(value) != value or value < 0 or value > MAX_HEIGHT:
			return false
	for key in ["belief", "collected", "tick", "terrain_revision", "next_id", "world_seed", "sculpted"]:
		if not (state.get(key) is int or state.get(key) is float) or float(state[key]) < 0 or not is_finite(float(state[key])):
			return false
	if not state.get("won") is bool or not data.get("pending") is Array or data["pending"].size() > 128:
		return false
	for command: Variant in data["pending"]:
		if not command is Dictionary or not command.get("type") is String:
			return false
	if state.has("runtime"):
		if not state["runtime"] is Dictionary: return false
		for key: String in state["runtime"]:
			var value: Variant = state["runtime"][key]
			if not (value is float or value is int) or not is_finite(float(value)) or value<0 or value>1000 or (key!="sculpt_cost" and value<=0): return false
	var ids: Dictionary = {}
	for key in ["followers", "sheep", "homes", "trees"]:
		if not state.get(key) is Array or state[key].size() > (65536 if key == "trees" else maxi(512,width*width)):
			return false
		for entry: Variant in state[key]:
			if not entry is Dictionary or not (entry.get("x") is float or entry.get("x") is int) or not (entry.get("z") is float or entry.get("z") is int):
				return false
			if not is_finite(float(entry["x"])) or not is_finite(float(entry["z"])) or entry["x"] < 0 or entry["z"] < 0 or entry["x"] >= width or entry["z"] >= width:
				return false
			if key == "trees":
				if not entry.get("variant") is float and not entry.get("variant") is int:
					return false
				if entry.has("source_y"):
					for field: String in ["source_y","rotation"]:
						var value: Variant=entry.get(field)
						if not (value is int or value is float) or not is_finite(float(value)): return false
					for field: String in ["cell","anchor_height"]:
						var value: Variant=entry.get(field)
						if not (value is int or value is float) or not is_finite(float(value)) or value!=int(value) or value<0: return false
					if entry["cell"]!=int(entry["z"])*width+int(entry["x"]) or entry["anchor_height"]>MAX_HEIGHT or entry["source_y"]<=0 or not entry.get("model_id") is String: return false
				continue
			if not (entry.get("id") is int or entry.get("id") is float) or ids.has(int(entry["id"])) or int(entry["id"]) >= state["next_id"]:
				return false
			ids[int(entry["id"])] = true
			if key == "homes":
				if entry.has("sacrificed_followers") and not Opening.integer(entry["sacrificed_followers"],0,1000000000): return false
				if entry.has("beauty_fraction") and not preload("res://simulation/source_house_environment.gd").valid_beauty_fraction(entry["beauty_fraction"]): return false
				if entry.has("temple_work") and (not (entry["temple_work"] is int or entry["temple_work"] is float) or not is_finite(float(entry["temple_work"])) or float(entry["temple_work"])<0 or preload("res://simulation/source_terrain.gd").f32(float(entry["temple_work"]))!=float(entry["temple_work"])): return false
				if entry.has("work_accumulator") and (not (entry["work_accumulator"] is int or entry["work_accumulator"] is float) or not is_finite(float(entry["work_accumulator"])) or entry["work_accumulator"]<0 or entry["work_accumulator"]>=1): return false
				if entry.has("new_builder_contribution") and not preload("res://simulation/construction_work.gd").valid_exponent(entry["new_builder_contribution"]): return false
				if entry.has("access_path"):
					if not entry["access_path"] is Array or entry["access_path"].size()>4096: return false
					for cell: Variant in entry["access_path"]:
						if not (cell is int or cell is float) or not is_finite(float(cell)) or cell<0 or cell>=width*width: return false
				for field in ["progress", "stored", "residents", "builder", "work_x", "work_z"]:
					if not (entry.get(field) is int or entry.get(field) is float):
						return false
				if entry["progress"] < 0 or entry["progress"] > int(entry.get("build_ticks",state.get("build_ticks", BUILD_TICKS))) or entry["stored"] < 0 or entry["stored"] > int(entry.get("max_belief",30)) or not entry.get("stalled") is bool:
					return false
				for field in ["build_ticks","birth_ticks","span","capacity"]:
					var minimum := 0 if field=="capacity" and entry.get("kind","") in ["ark","shrine"] else 1
					if entry.has(field) and (not (entry[field] is int or entry[field] is float) or not is_finite(float(entry[field])) or entry[field]<minimum): return false
			else:
				if not entry.get("path") is Array or not entry.get("state") is String:
					return false
				for field in ["wait", "job", "variant"]:
					if not (entry.get(field) is int or entry.get(field) is float):
						return false
				for cell: Variant in entry["path"]:
					if not (cell is int or cell is float) or cell < 0 or cell >= width * width:
						return false
				if entry.has("leash_goal"):
					if not entry["leash_goal"] is Array or entry["leash_goal"].size()!=2: return false
					for coordinate: Variant in entry["leash_goal"]:
						if not CampaignLeash.integer(coordinate,0) or coordinate>=width: return false
				if entry.has("leash_sacrifice") or entry.has("sacrifice_due"):
					if key!="followers" or entry.get("leash_sacrifice")!=true or not state.get("opening",{}).get("definition",{}).has("pit_sacrifice"): return false
					if entry.has("sacrifice_due"):
						if entry.has("leash_goal") or not entry["state"] in Pit.CLIPS or not CampaignLeash.integer(entry["sacrifice_due"],0): return false
					elif not entry.has("leash_goal"): return false
	var props: Variant = state.get("props", [])
	if not props is Array or props.size() > 4096:
		return false
	for prop: Variant in props:
		if not prop is Dictionary or not prop.get("model_id") is String:
			return false
		for field in ["id", "x", "z", "turns"]:
			if not (prop.get(field) is int or prop.get(field) is float) or not is_finite(float(prop[field])) or int(prop[field]) != prop[field]:
				return false
		if prop["x"] < 0 or prop["x"] >= width or prop["z"] < 0 or prop["z"] >= width or prop["turns"] < 0 or prop["turns"] > 3 or prop["id"] <= 0 or prop["id"] >= state["next_id"] or ids.has(int(prop["id"])):
			return false
		if prop.get("kind")=="fountain":
			var rules: Dictionary=state.get("opening",{}).get("definition",{}).get("fountain",{})
			if rules.is_empty() or prop["model_id"]!=rules["model"] or not CampaignLeash.integer(prop.get("reaction_until"),0): return false
			var area:=Fountain.bounds(prop,rules)
			if not Rect2i(0,0,width,width).encloses(area): return false
		if prop.get("kind")==Collector.KIND:
			var rules:=Collector.rules_for(state)
			if rules.is_empty() or prop["model_id"]!=rules["model"]: return false
			if not Rect2i(0,0,width,width).encloses(Collector.bounds(prop,rules)): return false
			if prop.has("ready_since") and not Opening.integer(prop["ready_since"],-1000000,int(state["tick"])): return false
		ids[int(prop["id"])] = true
	if state.has("progression") and not Progression.valid(state["progression"],width): return false
	if state.has("progression") and not Economy.valid_world(state): return false
	for field: String in ["removed_trees","tree_taps"]:
		if not state.get(field,{}) is Dictionary: return false
		for key: Variant in state.get(field,{}):
			if not key is String or not key.is_valid_int() or int(key)<0 or int(key)>=width*width: return false
			var value: Variant = state[field][key]
			if field=="removed_trees":
				if not value is bool or not value: return false
			elif not (value is float or value is int) or not is_finite(float(value)) or value<0 or value!=int(value): return false
	var vegetation_revision: Variant = state.get("vegetation_revision",0)
	if state.has("tree_response"):
		if not state.has("opening") or not state["opening"]["definition"].has("tree_response_config") or not preload("res://simulation/source_tree_response.gd").valid(state["tree_response"],state["trees"],int(state.get("tick",0))): return false
	if not (vegetation_revision is int or vegetation_revision is float) or not is_finite(float(vegetation_revision)) or vegetation_revision<0 or vegetation_revision!=int(vegetation_revision): return false
	if state.has("progression") and state["progression"].has("happiness") and not preload("res://simulation/happiness.gd").valid(state["progression"]["happiness"]): return false
	for resource: String in ["wheat","ore"]:
		var value: Variant = state.get(resource,0)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value!=int(value): return false
	if state.has("rocks"):
		if not (state["rocks"] is Array or state["rocks"] is PackedByteArray) or state["rocks"].size()!=width*width: return false
		for value: Variant in state["rocks"]:
			if not (value is int or value is float) or value<0 or value>255 or int(value)!=value: return false
	if state.has("rock_heights"):
		if not (state["rock_heights"] is Array or state["rock_heights"] is PackedByteArray) or state["rock_heights"].size()!=width*width: return false
		for value: Variant in state["rock_heights"]:
			if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>MAX_HEIGHT or int(value)!=value: return false
	_route_cache.clear()
	_component_of.clear()
	_blocked_cells.clear()
	_plan_stamp=-1
	_navigation_stamp=0
	_state = state.duplicate(true)
	_rock_visibility_stamp=Vector2i(-1,-1)
	_index_trees()
	# Earlier builds hid scenery under houses without persisting the clearing.
	# Keep those already-cleared old footprints clear after demolition as well.
	if not _state.has("removed_trees"):
		_state["removed_trees"]={}
		for home: Dictionary in _state["homes"]:
			for dz in range(int(home.get("span",2))):
				for dx in range(int(home.get("span",2))):
					var cell := (int(home["z"])+dz)*width+int(home["x"])+dx
					if _tree_cells.has(cell): _state["removed_trees"][str(cell)]=true
	if not _state.has("tree_taps"): _state["tree_taps"]={}
	if not _state.has("vegetation_revision"): _state["vegetation_revision"]=0
	_spatial_revision=0
	_blocked_stamp=Vector2i(-1,-1)
	_house_specs.clear()
	if _state.has("progression"):
		_state["progression"]=Progression.canonical_numbers(_state["progression"])
		_state["progression"].erase("beautified")
	if _state.has("source_influence"):
		_state["source_influence"]=preload("res://simulation/source_influence_areas.gd").restore(_state["source_influence"],_state["progression"]["rules"]["influence_areas"],_state["opening"]["definition"]["influence_rules"])
		Influence.refresh(_state)
	if _state.has("map_fields"): _state["map_fields"]=SourceRaster.restore(_state["map_fields"])
	if _state.has("source_plots"):
		_state["source_plots"]=preload("res://simulation/source_plot_registry.gd").restore(_state["source_plots"])
	if _state.has("opening"):
		_state["opening"]=Progression.canonical_numbers(_state["opening"])
		_state["opening"]["definition"]["raw_floor"]=PackedByteArray(_state["opening"]["definition"]["raw_floor"])
		preload("res://simulation/authored_rocks.gd").prepare(_state["opening"]["definition"])
		if not _state.has("rock_motion") and _state["opening"]["definition"].has("rock_motion_config"): _state["rock_motion"]=preload("res://simulation/source_rock_motion.gd").initial()
		if not _state.has("tree_response") and _state["opening"]["definition"].has("tree_response_config"):
			_state["tree_response"]=preload("res://simulation/source_tree_response.gd").initial()
			preload("res://simulation/source_tree_response.gd").refresh(_state,_tree_tiles,_tree_tiles,_tree_rows,source_tree_target,float(_state["tick"])*TICK_SECONDS)
	if _state.has("rock_motion"): _state["rock_motion"]=Progression.canonical_numbers(_state["rock_motion"])
	if _state.has("runtime"): _state["runtime"]=Progression.canonical_numbers(_state["runtime"])
	if _state.has("voyage"):
		for field: String in ["blight","swamp","beauty"]:
			if _state["voyage"].has(field): _state["voyage"][field]=PackedByteArray(_state["voyage"][field])
		_state["voyage"]["definition"]=Immutable.freeze(_state["voyage"]["definition"])
	if _state.has("gems"): _state["gems"]=int(_state["gems"])
	if _state.has("camera_start"):
		_state["camera_start"]={"x":int(_state["camera_start"]["x"]),"z":int(_state["camera_start"]["z"])}
	_dry_land = 0
	for value: int in _state["terrain"]:
		if value > 0: _dry_land += 1
	_state["props"] = props.duplicate(true)
	for prop: Dictionary in _state["props"]:
		for field in ["id", "x", "z", "turns"]: prop[field] = int(prop[field])
	for key in ["width", "belief", "collected", "tick", "terrain_revision", "next_id", "world_seed", "sculpted"]:
		_state[key] = int(_state[key])
	for key in ["home_cost","build_ticks","birth_ticks"]:
		if _state.has(key): _state[key]=int(_state[key])
	if _state.has("source_map"): _state["source_map"]=Progression.canonical_numbers(_state["source_map"])
	if _state.has("campaign"): _state["terrain"] = PackedByteArray(_state["terrain"])
	else:
		for i in range(_state["terrain"].size()): _state["terrain"][i] = int(_state["terrain"][i])
	if _state.has("rocks"): _state["rocks"]=PackedByteArray(_state["rocks"])
	if _state.has("rock_heights"): _state["rock_heights"]=PackedByteArray(_state["rock_heights"])
	for key in ["followers", "sheep", "homes", "trees"]:
		for entry: Dictionary in _state[key]:
			var fields: Array = (["variant"] if entry.has("source_y") else ["x","z","variant"]) if key == "trees" else (["id", "x", "z", "progress", "stored", "residents", "builder", "work_x", "work_z"] if key == "homes" else ["id", "wait", "job", "variant"])
			for field: String in fields:
				entry[field] = int(entry[field])
			if key=="homes":
				if entry.has("temple_work"): entry["temple_work"]=float(entry["temple_work"])
				if not entry.has("access_path"): entry["access_path"]=[]
				for field in ["family","rank","span","capacity","build_ticks","birth_ticks","min_belief","max_belief"]:
					if entry.has(field): entry[field]=int(entry[field])
				for index in range(entry.get("access_path",[]).size()): entry["access_path"][index]=int(entry["access_path"][index])
				if entry.has("work_accumulator"): entry["work_accumulator"]=float(entry["work_accumulator"])
				if entry.has("belief_accumulator"): entry["belief_accumulator"]=float(entry["belief_accumulator"])
			if entry.has("path"):
				entry["x"]=float(entry["x"])
				entry["z"]=float(entry["z"])
				for field: String in ["max_health","health","scale"]:
					if entry.has(field): entry[field]=float(entry[field])
				for i in range(entry["path"].size()):
					entry["path"][i] = int(entry["path"][i])
	_pending = data["pending"].duplicate(true)
	_random = random
	_random.state = int(data["rng_state"])
	if _state.has("progression"): Immutable.freeze(_state["progression"]["rules"])
	if _state.has("opening"): Immutable.freeze(_state["opening"]["definition"])
	return true


func _initialize_campaign(config: Dictionary) -> void:
	_state["width"] = int(config["width"])
	_state["terrain"] = config["terrain"].duplicate()
	_state["campaign"] = {"map": str(config.get("name", "Homeworld")), "map_id": str(config.get("id", "homeworld")), "cards": [], "stage": 0, "automatic_settlement": config.get("automatic_settlement",true)}
	_state["belief"] = int(config["configuration"].get("InitialBelief", "75"))
	for pair: Array in [["wheat","InitialWheat"],["ore","InitialOre"]]:
		if config["configuration"].has(pair[1]): _state[pair[0]]=int(config["configuration"][pair[1]])
	_state["home_cost"] = 0
	var shelter: Array = config["tables"]["balance/housevalues.csv"][2]
	_state["build_ticks"] = roundi(float(shelter[6])/TICK_SECONDS)
	_state["birth_ticks"] = roundi(float(shelter[16])/TICK_SECONDS)
	_state["followers"] = []
	_state["sheep"] = []
	_state["trees"] = []
	_state["next_id"] = 1
	# The loose map starts support standalone Weyworld. An Ark arrival gets
	# its own passengers plus the two followers spawned by the source script.
	if not config.has("ark_passengers"):
		for start: Dictionary in config["followers"]:
			_state["followers"].append(_agent(start["x"], start["z"], false))
	var tree_field: PackedByteArray = config.get("tree_field", PackedByteArray())
	if config.has("source_trees"):
		_state["trees"]=config["source_trees"].duplicate(true)
		_state["source_scenery"]={"sha256":config["source_scenery"]["sha256"],"counts":config["source_scenery"]["counts"].duplicate(true)}
	elif tree_field.size() == int(config["width"]) * int(config["width"]):
		for cell in range(tree_field.size()):
			if tree_field[cell] > 0 and _state["terrain"][cell] > 0:
				_state["trees"].append({"x":cell % int(config["width"]),"z":cell / int(config["width"]),"variant":int(tree_field[cell])-1})
	else:
		for tree: Dictionary in config.get("objects", {}).get("tree", []):
			if height_at(tree["x"], tree["z"]) > 0:
				_state["trees"].append({"x": tree["x"], "z": tree["z"], "variant": int(tree["value"]) - 1})
	_dry_land = 0
	for value: int in _state["terrain"]:
		if value > 0: _dry_land += 1
	if config.get("progression_rules",{}).has("registered_scope"):
		_state["campaign"]["population_unlocks"]=[]
		for level: Dictionary in config["progression_rules"]["research_levels"]:
			if not level.has("resource"): _state["campaign"]["population_unlocks"].append([str(int(level["population"])),level["card"]])
	else:
		_state["campaign"]["population_unlocks"] = config["tables"].get("balance/populationlevels.csv", []).duplicate(true)
	_state["camera_start"] = {"x":int(config["followers"][0]["x"]),"z":int(config["followers"][0]["z"])}
	_state["source_map"] = {"name": str(config.get("name", "Homeworld")), "id": str(config.get("id", "homeworld")), "sea_level": int(config["sea_level"]), "height_sha256": config["height_sha256"]}
	if config.has("progression_rules"):
		_state["gems"] = int(config["configuration"].get("InitialGems",100))
		_state["progression"] = Progression.initialize(config["progression_rules"],_state["terrain"],_state["width"])
		initialize_rocks(config.get("rock_field",PackedByteArray()),_state["terrain"])
		_state["rock_density_version"]=int(config.get("rock_density_version",0))
		if config.has("arrival"): _initialize_weyworld_arrival(config["arrival"],config.get("ark_passengers",[]))
		if config.has("ark_research"): Progression.inherit_research(_state,config["ark_research"])
		Progression.refresh(_state)
		Influence.refresh(_state)
		Weyworld.initialize(self,_state)
		if config.has("free_harvest"):
			Economy.place_free_harvest(_state,config["free_harvest"])
			Economy.fill_free_harvest(_state)
		Immutable.freeze(_state["progression"]["rules"])
	if config.has("story"):
		_state["opening"]=Opening.initialize(config["story"])
		if preload("res://simulation/source_influence_areas.gd").valid_rules(config["story"].get("influence_rules",{})):
			_state["source_influence"]=preload("res://simulation/source_influence_areas.gd").initial(_state["progression"]["rules"]["influence_areas"])
			Influence.refresh(_state)
			if int(_state["width"])==1024 and _source_plot_definition_supported(config["story"]):
				_state["source_plots"]=preload("res://simulation/source_plot_registry.gd").initial()
		if config["story"].has("rock_motion_config"): _state["rock_motion"]=preload("res://simulation/source_rock_motion.gd").initial()
		if config["story"].has("tree_response_config"): _state["tree_response"]=preload("res://simulation/source_tree_response.gd").initial()
		_state["camera_start"]={"x":int(config["story"]["constants"]["INITIAL_FOLLOWERS"]["x"]),"z":int(config["story"]["constants"]["INITIAL_FOLLOWERS"]["y"])+3}
		for index in range(_state["followers"].size()):
			var agent: Dictionary = _state["followers"][index]
			agent["female"]=bool(config["followers"][index]["source_args"][5])
			agent["state"]="drowning"
			_state["opening"]["protected"].append(int(agent["id"]))
		Immutable.freeze(_state["opening"]["definition"])
	if config.has("voyage"):
		_state["voyage"]=Voyage.initialize(config["voyage"],int(config["width"]),config.get("gem_field",PackedByteArray()))
		_state["followers"]=[]
		_state["runtime"]={"sculpt_cost":0.0 if config["voyage"]["free_sculpt"] else 1.0}
		_state["camera_start"]={"x":roundi((config["voyage"]["dock"][0]+config["voyage"]["goal"][0])*0.5),"z":roundi((config["voyage"]["dock"][1]+config["voyage"]["goal"][1])*0.5)}
		var parts := [["boats.group.bin:efa689a7","boat","boat_orientation"], ["boats.group.bin:6074dc25","boat","boat_orientation"], ["eventdock.group.bin:dff1563f","dock","dock_orientation"], ["temple.group.bin:dff1563f","goal","goal_orientation"]]
		for part: Array in parts:
			_state["props"].append({"id":_state["next_id"],"model_id":part[0],"x":config["voyage"][part[1]][0],"z":config["voyage"][part[1]][1],"turns":0,"degrees":config["voyage"][part[2]],"water":part[1]=="boat"})
			if part[0]=="boats.group.bin:efa689a7": _state["props"][-1]["clip"]="docked"
			_state["next_id"]+=1
		Voyage.setup(self,_state)
		_state["voyage"]["definition"]=Immutable.freeze(_state["voyage"]["definition"])


func _initialize_weyworld_arrival(arrival: Dictionary,passengers: Array) -> void:
	var ark: Dictionary=arrival["ark"]
	var x := int(ark["x"])
	var z := int(ark["z"])
	var span := int(ark["size"])-1
	var half := span/2
	var ticks := int(ark["build_ticks"])
	var id: int=_state["next_id"]
	_state["homes"].append({"id":_state["next_id"],"kind":"ark","x":x-half,"z":z-half,
		"anchor_x":x,"anchor_z":z,"span":span,"work_x":x,"work_z":z,"model_id":ark["model_id"],
		"name":ark["title"],"capacity":passengers.size(),"residents":passengers.size(),"stored":0,"min_belief":0,"max_belief":0,
		"build_ticks":ticks,"progress":ticks,"stalled":false,"builder":-1,"access_path":[]})
	_state["next_id"]+=1
	for passenger: Dictionary in passengers:
		var agent:=_agent(x,z,false)
		agent.merge({"state":"indoors","indoors_home":id,"ark_passenger":true,"female":passenger["female"],"race":passenger["race"]},true)
		_state["followers"].append(agent)
	for start: Dictionary in arrival["followers"]:
		var agent := _agent(start["x"],start["z"],false)
		agent["female"]=start["female"]
		_state["followers"].append(agent)


func _update_campaign() -> void:
	# Followers settle available nearby plots; player shaping remains authoritative.
	if _state.has("progression"):
		var p: Dictionary=_state["progression"]
		var revision: int=p.get("influence_revision",0)
		Progression.refresh(_state)
		Influence.refresh(_state)
		if p["rules"].has("registered_scope") and revision!=p.get("influence_revision",0): Economy.fill_free_harvest(_state)
	var repair_queued := false
	if _state["tick"]%10==0:
		if _state["campaign"]["automatic_settlement"]:
			_reassign_builders(true)
			repair_queued=_queue_shrine_repair()
		# Keep an idle builder available for the validated repair command at
		# the next tick instead of reserving them for another home meanwhile.
		if not repair_queued: _reassign_builders()
	if not repair_queued and _state["campaign"]["automatic_settlement"] and _state["tick"] % 10 == 0 and (_state.has("progression") or _state["homes"].size()<24):
		var max_rank:=Weyworld.highest_abode_rank(_state,int(_state.get("progression",{}).get("max_rank",1)))
		for follower: Dictionary in _state["followers"]:
			if follower["job"] != -1 or follower["state"]=="worshipping" or follower.has("workplace") or follower.has("ark_passenger") or follower.has("weyworld_destination"): continue
			if _state.has("progression") and _state["progression"]["totem"].get("active",false) and _state["followers"].find(follower)<int(_state["progression"]["totem_capacity"]): continue
			var placed := false
			var radius := maxi(1,mini(roundi(runtime_value("home_search_radius",4)),floori(float(follower_values(follower).get("Vision",4)))))
			for z in range(roundi(follower["z"])-radius,roundi(follower["z"])+radius+1):
				for x in range(roundi(follower["x"])-radius,roundi(follower["x"])+radius+1):
					if placed: break
					for rank in range(max_rank,0,-1):
						var command := {"type": "home", "x": x, "z": z,"rank":rank}
						if _validate(command)["ok"]:
							queue_command(command)
							placed = true
							break
				if placed: break
			if placed: break
	var population: int = _state["followers"].size()
	_state["campaign"]["stage"] = int(_state.get("progression",{}).get("player_level",0))
	# original game progression continues through its cards and expansions; the former
	# prototype's population-30 victory is not an original campaign objective.
	_state["won"] = false


func _queue_shrine_repair() -> bool:
	if not _state.has("progression"): return false
	var ordered: Array=_state["progression"]["shrines"].duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return str(a["id"])<str(b["id"]) if float(a.get("build_priority",0))==float(b.get("build_priority",0)) else float(a.get("build_priority",0))>float(b.get("build_priority",0)))
	for shrine: Dictionary in ordered:
		if shrine.get("started",false) or shrine.get("complete",false): continue
		var command := {"type":"repair_shrine","id":shrine["id"]}
		if _validate(command).get("ok",false):
			queue_command(command)
			return true
	return false


func _inspect_shrine_repair(shrine: Dictionary,costs: Dictionary) -> Dictionary:
	var reject := {"ok":false,"cost":0,"reason":"Clear the shrine and leave a reachable approach."}
	var region := preload("res://simulation/temple_rules.gd").footprint(shrine)
	var width := int(_state["width"])
	var anchor := Vector2i(shrine["x"],shrine["z"])
	var level := float(shrine["source_height"])-float(_state["source_map"]["sea_level"]) if shrine.get("source_height")!=null else float(height_at(anchor.x,anchor.y))
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if x<0 or z<0 or x>=width or z>=width or not can_act_at(x,z) or height_at(x,z)>level or _occupied(x,z): return reject
			var obstruction := plot_obstruction(x,z)
			if not obstruction.is_empty(): return {"ok":false,"cost":0,"reason":"Clear the %s above this shrine first."%obstruction,"obstruction":{"kind":obstruction,"x":x,"z":z}}
	var work_cells: Array[Vector2i]=[]
	for z in range(region.position.y,region.end.y): work_cells.append_array([Vector2i(region.position.x-1,z),Vector2i(region.end.x,z)])
	for x in range(region.position.x,region.end.x): work_cells.append_array([Vector2i(x,region.position.y-1),Vector2i(x,region.end.y)])
	for follower: Dictionary in _state["followers"]:
		if follower["job"]!=-1 or follower.has("workplace") or follower.has("ark_passenger") or follower.has("weyworld_destination") or follower["state"]=="worshipping": continue
		var start := Vector2i(roundi(follower["x"]),roundi(follower["z"]))
		if Vector2(start).distance_to(Vector2(anchor))>float(follower_values(follower).get("Vision",15)): continue
		for work: Vector2i in work_cells:
			if height_at(work.x,work.y)<=0 or _occupied(work.x,work.y) or not plot_obstruction(work.x,work.y).is_empty(): continue
			var route := _route(start,work)
			if start!=work and route.is_empty(): continue
			var crosses := false
			var outside := not region.has_point(start)
			for cell: int in route:
				var inside := region.has_point(Vector2i(cell%width,cell/width))
				if inside and outside: crosses=true; break
				if not inside: outside=true
			if crosses: continue
			var specification := cached_house_spec(1).duplicate(true)
			specification["span"]=maxi(region.size.x,region.size.y)
			return {"ok":true,"cost":0,"reason":"Repair shrine","builder":follower["id"],"work_x":work.x,"work_z":work.y,"path":route,"specification":specification,"resource_cost":costs.duplicate(true),"shrine":shrine.duplicate(true),"plot_x":region.position.x,"plot_z":region.position.y}
	return reject


func _reassign_builders(only_shrines: bool=false) -> void:
	var counts := {}
	var occupied_work := {}
	for follower: Dictionary in _state["followers"]:
		if follower["job"]==-1: continue
		counts[follower["job"]]=int(counts.get(follower["job"],0))+1
		if follower.has("work_x"): occupied_work[Vector2i(follower["work_x"],follower["work_z"])]=true
	var ordered: Array=_state["homes"].filter(func(home: Dictionary) -> bool: return not only_shrines or home.get("kind","")=="shrine")
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if (a.get("kind","")=="shrine")!=(b.get("kind","")=="shrine"): return a.get("kind","")=="shrine"
		return a["id"]<b["id"] if float(a.get("build_priority",0))==float(b.get("build_priority",0)) else float(a.get("build_priority",0))>float(b.get("build_priority",0)))
	for home: Dictionary in ordered:
		if home["progress"]>=int(home.get("build_ticks",_state.get("build_ticks",BUILD_TICKS))): continue
		var assigned: int=counts.get(home["id"],0)
		for follower: Dictionary in _state["followers"]:
			if follower["job"]==home["id"] and not follower.has("work_x"): occupied_work[Vector2i(home["work_x"],home["work_z"])]=true
		var slots := clampi(floori(float(home.get("build_capacity",1))),1,64)
		var work_cells: Array[Vector2i]=[Vector2i(home["work_x"],home["work_z"])]
		var span: int=home.get("span",2)
		for i in range(span):
			work_cells.append_array([Vector2i(int(home["x"])-1,int(home["z"])+i),Vector2i(int(home["x"])+span,int(home["z"])+i),Vector2i(int(home["x"])+i,int(home["z"])-1),Vector2i(int(home["x"])+i,int(home["z"])+span)])
		for follower: Dictionary in _state["followers"]:
			if assigned>=slots: break
			if follower.has("workplace") and follower["workplace"]!=home["id"]: continue
			if home.get("kind","") in ["farm","mine"] and follower.get("workplace",-1)!=home["id"]: continue
			if follower["job"]!=-1 or follower["state"]=="worshipping" or follower.has("ark_passenger") or follower.has("weyworld_destination"): continue
			var start := Vector2i(roundi(follower["x"]),roundi(follower["z"]))
			var reach := float(follower_values(follower).get("Vision",15)) if home.get("kind","")=="shrine" else float(home.get("vision_radius",1000000))
			if start.distance_to(Vector2i(home["x"],home["z"]))>reach: continue
			for target: Vector2i in work_cells:
				if occupied_work.has(target) or height_at(target.x,target.y)<=0 or _occupied(target.x,target.y): continue
				var route := _route(start,target)
				if start!=target and route.is_empty(): continue
				follower["job"]=home["id"]
				follower["path"]=route
				follower["work_x"]=target.x
				follower["work_z"]=target.y
				follower["state"]="walking"
				home["access_path"].append_array(route)
				if assigned==0: home["builder"]=follower["id"]
				home["stalled"]=false
				occupied_work[target]=true
				assigned+=1
				break


func _advance_construction() -> void:
	# Advance once after every follower's movement, so work does not depend on
	# array order or charge walking builders as if they were already working.
	var groups := {}
	for follower: Dictionary in _state["followers"]:
		if follower["job"]==-1 or follower["state"]!="building": continue
		var id: int=follower["job"]
		if not groups.has(id): groups[id]={"count":0,"skill":0.0,"workers":[]}
		groups[id]["count"]+=1
		groups[id]["skill"]+=float(follower_values(follower).get("JobSkill",1))
		groups[id]["workers"].append(follower["id"])
	for home: Dictionary in _state["homes"]:
		var id: int=home["id"]
		var duration: int=home.get("build_ticks",_state.get("build_ticks",BUILD_TICKS))
		if home["progress"]>=duration or not groups.has(id): continue
		var group: Dictionary=groups[id]
		if home.get("kind","")=="shrine":
			if home.get("authored_shrine",false) and not source_shrine_clear(source_shrine_site(home["shrine_id"]),id):
				home["stalled"]=true
				continue
			if home.has("ark_crew"):
				for worker: int in group["workers"]:
					home["ark_crew"][str(worker)]=true
			var exponent := float(_state["progression"]["rules"]["config"]["templeFixerFalloff"])
			var prior := float(home.get("temple_work",preload("res://simulation/source_terrain.gd").f32((float(home["progress"])+float(home.get("work_accumulator",0)))*TICK_SECONDS)))
			home["temple_work"]=preload("res://simulation/source_temple_repair.gd").work_value(prior,TICK_SECONDS*runtime_value("build_rate",1.0),int(group["count"]),int(group["count"]),float(group["skill"]),exponent)
			if float(home["temple_work"])>=preload("res://simulation/source_terrain.gd").f32(duration*TICK_SECONDS):
				home["progress"]=duration
				home["work_accumulator"]=0.0
			else:
				var ticks := float(home["temple_work"])/TICK_SECONDS
				home["progress"]=floori(ticks)
				home["work_accumulator"]=ticks-floorf(ticks)
		else:
			var increment := preload("res://simulation/construction_work.gd").advance(0.0,1.0,int(group["count"]),int(group["count"]),float(group["skill"]),float(home.get("new_builder_contribution",1.0)),runtime_value("build_rate",1.0))
			home["work_accumulator"]=float(home.get("work_accumulator",0.0))+increment
		# Finish before converting a potentially large CSV-configured work value
		# to an integer. Excess work belongs to this task, not a future upgrade.
		if home.get("kind","")!="shrine" and home["work_accumulator"]>=duration-int(home["progress"]):
			home["progress"]=duration
			home["work_accumulator"]=0.0
		elif home.get("kind","")!="shrine":
			var work := floori(home["work_accumulator"])
			home["work_accumulator"]-=work
			home["progress"]+=work
		if home["progress"]<duration: continue
		for follower: Dictionary in _state["followers"]:
			if follower["job"]!=id: continue
			follower["job"]=-1
			follower["state"]="idle"
			follower.erase("work_x")
			follower.erase("work_z")


func source_shrine_site(id: String="") -> Dictionary:
	if id.is_empty():
		var opening: Dictionary=_state["opening"]
		id=opening["definition"].get("discovery_site_id" if Opening.supports_discovery(opening) else "first_shrine_id","")
	for site: Dictionary in _state["progression"]["shrines"]:
		if site["id"]==id: return site
	return {}


func source_dock_site() -> Dictionary:
	var id: String=_state["opening"]["definition"].get("dock_site_id","")
	return source_shrine_site(id) if not id.is_empty() else {}


func source_land_expansion(site: Dictionary) -> bool:
	var kind: String=site.get("type","")
	var supported: bool=kind=="Shrine_LandExp" or kind=="Shrine_OreLandExp" and _state["opening"]["definition"].has("mining_core")
	return supported and site["id"]!=_state["opening"]["definition"].get("first_shrine_id") and not site["model_id"].is_empty()


func source_ark_site(site: Dictionary) -> bool:
	return site.get("id","")!="" and site["id"]==_state["opening"]["definition"].get("ark",{}).get("site_id")


func ark_manifest() -> Array:
	var id: String=_state.get("opening",{}).get("definition",{}).get("ark",{}).get("site_id","")
	if id.is_empty() or not source_shrine_site(id).get("complete",false): return []
	var hull:=Ark.hull(_state,id)
	if hull.is_empty(): return []
	var manifest: Array=[]
	for follower: Dictionary in _state["followers"]:
		if follower.get("indoors_home")==hull["id"] and hull["ark_crew"].has(str(follower["id"])):
			manifest.append({"female":follower.get("female",false),"race":follower["race"]})
	return manifest


func ark_research() -> Dictionary:
	if not _state.has("opening"): return {}
	var source: Dictionary=_state["progression"]
	var research: Dictionary={}
	for key: String in ["discovered","completed","inventory","research","assigned_resources","reward_history","max_rank","abode_type","totem_capacity","age"]:
		if not source.has(key): continue
		var value: Variant=source[key]
		research[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	return research


func inspect_ark_release(id: Variant,destination: Vector2i=Vector2i(-1,-1)) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	if _state.get("source_map",{}).get("id")!="homeworld7": return reject
	for home: Dictionary in _state["homes"]:
		if home["id"]!=id or home.get("kind")!="ark" or home["residents"]<=0: continue
		var bounds:=Rect2i(home["x"],home["z"],home["span"],home["span"])
		for index in range(bounds.size.x):
			for point: Vector2i in [Vector2i(bounds.position.x-1,bounds.position.y+index),Vector2i(bounds.end.x,bounds.position.y+index),Vector2i(bounds.position.x+index,bounds.position.y-1),Vector2i(bounds.position.x+index,bounds.end.y)]:
				if height_at(point.x,point.y)<=0 or not can_act_at(point.x,point.y) or _occupied(point.x,point.y): continue
				var path: Array=[]
				if destination.x>=0 and point!=destination:
					path=_route(point,destination)
					if path.is_empty(): continue
				for follower: Dictionary in _state["followers"]:
					if follower.get("ark_passenger",false) and follower.get("indoors_home")==id:
						return {"ok":true,"cost":0,"reason":"","home":home,"follower":follower,"target":point,"path":path}
	return reject


func release_ark_passenger(home: Dictionary,follower: Dictionary,target: Vector2i) -> void:
	home["residents"]-=1
	follower.erase("indoors_home")
	follower.erase("ark_passenger")
	follower.merge({"x":float(target.x),"z":float(target.y),"state":"idle"},true)
	Weyworld.first_leash(_state)


func inspect_weyworld_leash(command: Dictionary) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var rules: Dictionary=Weyworld.rules(_state)["leash"]
	var width: int=_state["width"]
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	var home_id: Variant=command.get("home_id",-1)
	var selected: Variant=command.get("followers")
	if not CampaignLeash.coordinate(x,width) or not CampaignLeash.coordinate(z,width) or not CampaignLeash.integer(home_id,-1) or not selected is Array: return reject
	if not preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"Leash") and _state["weyworld"]["phase"]!=0: return reject
	var point:=Vector2i(roundi(float(x)),roundi(float(z)))
	if not can_act_at(point.x,point.y) or height_at(point.x,point.y)<=0 or _occupied(point.x,point.y): return reject
	var result: Dictionary
	var orders: Array=[]
	var cost:=0
	if home_id>=0:
		if not selected.is_empty(): return reject
		result=inspect_ark_release(home_id,point)
		if not result["ok"] or Vector2(result["home"]["anchor_x"],result["home"]["anchor_z"]).distance_to(Vector2(point))>float(rules["max_length"]): return reject
		orders.append({"agent":result["follower"],"path":result["path"]})
		cost=rules["home_cost"]
	else:
		if selected.is_empty() or selected.size()>_state["followers"].size(): return reject
		var ids: Dictionary={}
		for id: Variant in selected:
			if not CampaignLeash.integer(id,1) or ids.has(int(id)): return reject
			ids[int(id)]=true
		for agent: Dictionary in _state["followers"]:
			if not ids.erase(int(agent["id"])): continue
			var origin:=Vector2(agent["x"],agent["z"])
			if agent["job"]!=-1 or agent.has("ark_passenger") or agent.has("workplace") or origin.distance_to(Vector2(point))>float(rules["max_length"]): return reject
			var cell:=Vector2i(origin.round())
			var path:=_route(cell,point)
			if cell!=point and path.is_empty(): return reject
			orders.append({"agent":agent,"path":path})
		if not ids.is_empty(): return reject
		result={"reason":""}
		cost=selected.size()*int(rules["follower_cost"])
	result.merge({"ok":_state["belief"]>=cost,"cost":cost,"orders":orders,"destination":[point.x,point.y]},true)
	return result


func inspect_ark_builder(site: Dictionary) -> Dictionary:
	var center:=Vector2(site["x"],site["z"])
	for follower: Dictionary in _state["followers"]:
		if follower["state"]!="idle" or follower["job"]!=-1 or follower.has("workplace") or follower.has("entering_home") or follower.get("seeking_plot",false): continue
		var origin:=Vector2(follower["x"],follower["z"])
		if origin.distance_to(center)>float(follower_values(follower).get("Vision",15)): continue
		var plan:=source_shrine_repair_plan(site,Vector2i(origin.round()))
		if not plan.is_empty(): return {"ok":true,"cost":0,"reason":"","builder":follower["id"],"ark_plan":plan}
	return {"ok":false,"cost":0,"reason":""}


func source_ark_berths(site: Dictionary) -> int:
	var home:=Ark.hull(_state,site["id"])
	if home.is_empty(): return 0
	var reserved := 0
	for follower: Dictionary in _state["followers"]:
		if follower.get("ark_boarding")==site["id"]: reserved+=1
	return maxi(0,int(home["capacity"])-int(home["residents"])-reserved)


func source_ark_boarding_plan(site: Dictionary,origin: Vector2i,reserved: Dictionary) -> Dictionary:
	if not site["complete"] or not source_plot_eligible(site["x"],site["z"]): return {}
	return _promised_abode_approach(origin,source_shrine_bounds(site),reserved,true)


func board_source_ark(site_id: String,follower: Dictionary) -> void:
	var home:=Ark.hull(_state,site_id)
	Ark.board(home,follower)
	_state["progression"]["revision"]+=1


func source_shrine_layer(site: Dictionary) -> int:
	if site.get("source_height")!=null: return int(site["source_height"])
	return int(_state["opening"]["definition"]["raw_floor"][int(site["z"])*int(_state["width"])+int(site["x"])])


func source_shrine_clear(site: Dictionary,ignore_home: int=-1) -> bool:
	if site.is_empty(): return false
	var anchor := Vector2i(site["x"],site["z"])
	if not can_act_at(anchor.x,anchor.y) or _occupied(anchor.x,anchor.y,ignore_home) or not plot_obstruction(anchor.x,anchor.y).is_empty(): return false
	var terrain := preload("res://simulation/source_terrain.gd")
	var footprint := {"x":float(site["x"]),"z":float(site["z"]),"height":terrain.surface_height(source_shrine_layer(site)),"footprint_width":int(site["width"])}
	return preload("res://simulation/source_temple_footprint.gd").count(footprint,_state["opening"]["definition"]["temple_footprint_rules"],source_raw_height_at)==0


func source_shrine_plan(candidate: Dictionary) -> Dictionary:
	var discovery := Opening.supports_discovery(_state["opening"])
	if not discovery and _state["opening"]["shrine_step"] not in [2,3]: return {}
	if not preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],"BuildTemplesClaim" if discovery else "BuildExpansions"): return {}
	var source: Dictionary=_state["opening"]["definition"]
	var abode: Dictionary=candidate["home"]
	var values: Dictionary=source["mud_hut"]["values"] if abode.get("model_id")==source["mud_hut"]["model_id"] else source["first_abode_values"]["values"]
	var follower: Dictionary=candidate["follower"]
	var origin := Vector2i(roundi(follower["x"]),roundi(follower["z"]))
	var sites: Array=[source_shrine_site()]
	if CampaignLeash.enabled(_state):
		sites.append(source_dock_site())
		for site: Dictionary in _state["progression"]["shrines"]:
			if source_land_expansion(site) or source_ark_site(site): sites.append(site)
	for site: Dictionary in sites:
		if site.is_empty() or origin.distance_to(Vector2i(site["x"],site["z"]))>float(abode.get("vision_radius",values["visionradius"])): continue
		var plan:=source_shrine_repair_plan(site,origin)
		if not plan.is_empty(): return plan
	return {}


func source_shrine_repair_plan(site: Dictionary,origin: Vector2i,reserved: Dictionary={}) -> Dictionary:
	if site.is_empty() or site["complete"] or site.get("repaired",false): return {}
	var ore_beacon: bool=site.get("type")=="Shrine_OreLandExp"
	var ark := source_ark_site(site)
	if (ore_beacon or ark) and not Economy.spends_resource(_state,"ore"): return {}
	if ark and not source_plot_eligible(site["x"],site["z"]): return {}
	var building_id := -1
	for home: Dictionary in _state["homes"]:
		if home.get("shrine_id")==site["id"]: building_id=int(home["id"]); break
	if not source_shrine_clear(site,building_id): return {}
	var payment: Dictionary={}
	if building_id==-1 and (ore_beacon or ark):
		var quote:=preload("res://simulation/temple_rules.gd").costs(_state,site)
		if not quote["ok"]: return {}
		payment=quote["costs"]
	var occupied := reserved.duplicate()
	if building_id!=-1:
		for agent: Dictionary in _state["followers"]:
			if agent["job"]==building_id: occupied[Vector2i(agent["work_x"],agent["work_z"])]=true
	if occupied.size()>=int(site["build_capacity"]): return {}
	var approach := _promised_abode_approach(origin,source_shrine_bounds(site),occupied,site["id"]==_state["opening"]["definition"].get("dock_site_id"))
	if approach.is_empty(): return {}
	approach["building_id"]=building_id
	approach["site_id"]=site["id"]
	if not payment.is_empty(): approach["payment"]=payment
	return approach


func source_shrine_bounds(site: Dictionary) -> Rect2i:
	var anchor := Vector2i(site["x"],site["z"])
	var span := ceili(float(site["nav_size"]))
	return Rect2i(anchor-Vector2i.ONE*(span/2),Vector2i.ONE*span)


func source_clear_footprint(area: Rect2i) -> bool:
	var ground:=height_at(area.position.x,area.position.y)
	if ground<=0: return false
	for z in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			if height_at(x,z)!=ground or not can_act_at(x,z) or _occupied(x,z) or not plot_obstruction(x,z).is_empty():
				return false
	for site: Dictionary in _state["progression"]["shrines"]:
		if source_shrine_bounds(site).intersects(area): return false
	return true


func source_shrine_builder_home() -> Variant:
	var site := source_shrine_site()
	var best := INF
	var selected: Variant=null
	for home: Dictionary in _state["homes"]:
		var candidate := Opening.release_candidate(_state,int(home["id"]))
		if candidate.is_empty() or source_shrine_plan(candidate).is_empty(): continue
		var distance := Vector2(home["x"],home["z"]).distance_squared_to(Vector2(site["x"],site["z"]))
		if distance<best:
			best=distance
			selected=home["id"]
	return selected


func assign_source_shrine(follower: Dictionary,plan: Dictionary) -> void:
	var site := source_shrine_site(plan["site_id"])
	var bounds := source_shrine_bounds(site)
	var id: int=plan["building_id"]
	var work: Vector2i=plan["target"]
	if id==-1:
		for resource: String in plan.get("payment",{}):
			_state[resource]=int(_state[resource])-int(plan["payment"][resource])
		id=_state["next_id"]
		_state["next_id"]+=1
		_state["homes"].append({"id":id,"kind":"shrine","authored_shrine":true,"shrine_id":site["id"],"model_id":site["model_id"],"rotation":site["rotation"],"x":bounds.position.x,"z":bounds.position.y,"span":bounds.size.x,"capacity":0,"build_capacity":site["build_capacity"],"build_ticks":site["build_ticks"],"progress":0,"temple_work":0.0,"stored":0,"residents":0,"work_x":work.x,"work_z":work.y,"builder":follower["id"],"stalled":false,"access_path":plan["path"].duplicate()})
		if source_ark_site(site):
			_state["homes"].back().merge({"ark_crew":{},"capacity":site["build_capacity"],"breed_locked":true},true)
		site["started"]=true
		_spatial_revision+=1
	follower.merge({"job":id,"repair_site":site["id"],"work_x":work.x,"work_z":work.y,"path":plan["path"].duplicate(),"state":"walking"},true)


func finish_source_shrine(id: int) -> String:
	for home: Dictionary in _state["homes"]:
		if home["id"]!=id or not home.get("authored_shrine",false): continue
		var site := source_shrine_site(home["shrine_id"])
		if site.get("repaired",false): return ""
		site["repaired"]=true
		_state["progression"]["revision"]+=1
		for follower: Dictionary in _state["followers"]:
			if home.get("ark_crew",{}).has(str(follower["id"])):
				Ark.board(home,follower)
				continue
			if follower.get("repair_site")==site["id"]:
				follower.erase("repair_site")
				if follower.has("away_home"): follower["entering_home"]=int(follower["away_home"])
		return site["id"]
	return ""


func dwelling_count() -> int:
	var count := 0
	for home: Dictionary in _state["homes"]:
		if home.get("kind","")=="": count+=1
	return count


func begin_promised_abode(plot: Dictionary,builder_id: int=-1) -> bool:
	var story: Dictionary=_state["opening"]["definition"]
	var first: bool=_state["homes"].is_empty()
	if plot.is_empty() or not story.has("first_abode_model") or (not first and builder_id<0): return false
	var unlocked := func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],key)
	var ground := func(x: float,z: float) -> float: return preload("res://simulation/source_terrain.gd").surface_height(source_raw_height_at(x,z))
	var tent_index := -1
	for house: Dictionary in story["house_selection"]:
		if house["id"]=="AbodeType_0_Rank_1": tent_index=int(house["index"]); break
	var existing: Array=[]
	for home: Dictionary in _state["homes"]:
		if home.get("kind","")=="": existing.append({"index":home.get("source_index",tent_index),"owner":0})
	var random := RandomNumberGenerator.new()
	random.state=_random.state
	var request := preload("res://simulation/source_plot_conversion.gd").request(plot,0,0,false,false,existing,story["house_selection"],story["plot_environment"],story["plot_conversion_rules"],unlocked,ground,random.randi)
	if request.is_empty(): return false
	var source_id: String=story["house_selection"][request["index"]]["id"]
	var definition := {"model_id":story["first_abode_model"],"values":story["first_abode_values"]["values"],"name":story["first_abode_values"]["raw"]["House Name"]}
	if source_id!="AbodeType_0_Rank_1":
		if not (Opening.supports_timeline_housing(_state["opening"]) or Opening.supports_shrine_housing(_state["opening"]) or Opening.supports_discovery(_state["opening"])): return false
		if source_id==story["mud_hut"]["source_id"]: definition=story["mud_hut"]
		elif source_id=="AbodeType_1_Rank_2": definition=story.get("mud_lodge",{})
		elif source_id.begins_with("StoneHouse_"): definition=story.get("stone_abodes",{}).get(source_id,{})
		else: definition=story.get("wooden_abodes",{}).get(source_id,{})
		if definition.is_empty(): return false
	var wheat:=source_abode_wheat_cost(plot)
	if wheat>int(_state.get("wheat",0)): return false
	var values: Dictionary=definition["values"]
	var center: Array=request["position"]
	var span := int(values["base size"])
	var x := floori(float(center[0])-span*0.5+0.5)
	var z := floori(float(center[1])-span*0.5+0.5)
	var footprint := Rect2i(x,z,span,span)
	var routes: Array=[]
	var reserved := {}
	var slots := int(story["promised_steps"][2]["build_capacity"] if first else values["build capacity"])
	for follower: Dictionary in _state["followers"]:
		if routes.size()>=slots: break
		if follower["state"]=="indoors" or builder_id>=0 and follower["id"]!=builder_id: continue
		var start := Vector2i(roundi(follower["x"]),roundi(follower["z"]))
		var approach := _promised_abode_approach(start,footprint,reserved)
		if approach.is_empty(): continue
		reserved[approach["target"]]=true
		routes.append({"follower":follower,"path":approach["path"],"target":approach["target"]})
	if routes.is_empty(): return false
	if not preload("res://simulation/source_plot_conversion.gd").release_plot(_state["source_plots"],int(plot["id"]),true,false): return false
	if wheat>0: _state["wheat"]-=wheat
	_random.state=random.state
	var id: int=_state["next_id"]
	_state["next_id"]+=1
	var work: Vector2i=routes[0]["target"]
	var duration:=Economy.build_ticks(_state,{"build_ticks":roundi(float(values["build time"])/TICK_SECONDS),"rank":definition.get("rank",1)})
	_state["homes"].append({"id":id,"model_id":definition["model_id"],"name":definition["name"],"family":definition.get("family",2 if definition.has("rank") else 0),"rank":definition.get("rank",1),"source_house":source_id,"source_index":request["index"],"script_abode_type":definition.get("script_type",0),
		"x":x,"z":z,"anchor_x":center[0],"anchor_z":center[1],"rotation":rad_to_deg(center[3]),"span":span,
		"capacity":int(values["capacity"]),"build_capacity":slots,"new_builder_contribution":values["new builder contribution"],
		"vision_radius":values["visionradius"],"belief_modifier":values["belief modifier"],"belief_multiplier":values["belief multiplier per peep in house"],
		"breeder_count":int(values["breeder count"]),"birth_ticks":roundi(float(values["birth rate"])/TICK_SECONDS),
		"build_ticks":duration,"progress":0,"stored":0,"residents":0,"min_belief":int(values["min belief"]),"max_belief":int(values["max belief"]),
		"builder":routes[0]["follower"]["id"],"work_x":work.x,"work_z":work.y,"stalled":false,"access_path":[]})
	_spatial_revision+=1
	for route: Dictionary in routes:
		var follower: Dictionary=route["follower"]
		var target: Vector2i=route["target"]
		follower.merge({"job":id,"work_x":target.x,"work_z":target.y,"path":route["path"],"state":"walking","entering_home":id},true)
		follower.erase("seeking_plot")
	return true


func refresh_source_abode_build_times() -> void:
	var stats: Array=_state["opening"]["definition"]["house_base_stats"]["rows"]
	for home: Dictionary in _state["homes"]:
		if not home.has("source_house") or home["progress"]>=home["build_ticks"]: continue
		var seconds: float=stats[home["source_index"]]["values"]["build time"]
		var duration:=Economy.build_ticks(_state,{"build_ticks":roundi(seconds/TICK_SECONDS),"rank":home["rank"]})
		home["build_ticks"]=duration
		home["progress"]=mini(int(home["progress"]),duration-1)


func source_abode_wheat_cost(plot: Dictionary) -> int:
	var progression: Dictionary=_state["progression"]
	var unlocked:=func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(progression,key)
	if not unlocked.call("FoodSpending"): return 0
	var membership:=func(point: Array) -> int:
		var owner:=4294967295
		for settlement: Dictionary in progression["settlements"]:
			var dx:=float(point[0])-float(settlement["x"])
			var dz:=float(point[1])-float(settlement["z"])
			if dx*dx+dz*dz<=float(settlement["radius"])*float(settlement["radius"]): owner=int(settlement["id"])
		return owner
	var quote:=preload("res://simulation/source_plot_cost.gd").quote(plot,1,_state["opening"]["definition"],unlocked,membership,dwelling_count())
	return maxi(0,ceili(quote.get("amount",0.0)))


func promised_growth_plots() -> Array:
	var opening: Dictionary=_state["opening"]
	var definition: Dictionary=opening["definition"]
	var site: Dictionary=definition["constants"]["INITIAL_ROCK"]
	var registry: Dictionary=_state["source_plots"]
	var plots: Array=[]
	var expanded := Opening.supports_timeline_housing(opening) or Opening.supports_shrine_housing(opening) or Opening.supports_discovery(opening)
	var pit := source_shrine_site(definition["discovery_site_id"]) if definition.has("discovery_site_id") else {}
	var pit_bounds := Rect2i() if pit.is_empty() else source_shrine_bounds(pit)
	var dock:=source_dock_site()
	var dock_bounds:=Rect2i() if dock.is_empty() else source_shrine_bounds(dock)
	var expansion_bounds: Array[Rect2i]=[]
	for temple: Dictionary in _state["progression"]["shrines"]:
		if source_land_expansion(temple) or source_ark_site(temple): expansion_bounds.append(source_shrine_bounds(temple))
	var shrine: Dictionary=definition["constants"]["FIRST_SHRINE"] if definition.has("first_shrine_id") else {}
	for id: int in registry["active"]:
		var plot: Dictionary=registry["slots"][id]
		var footprint := Rect2i(int(plot["x"]),int(plot["z"]),int(plot["size"]),int(plot["size"]))
		if not pit.is_empty() and pit_bounds.intersects(footprint): continue
		if not dock.is_empty() and dock_bounds.intersects(footprint): continue
		if expansion_bounds.any(func(bounds: Rect2i) -> bool: return bounds.intersects(footprint)): continue
		if not shrine.is_empty() and footprint.has_point(Vector2i(shrine["x"],shrine["y"])): continue
		if not expanded and not preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(site["x"],site["y"]),20.0): continue
		var half := float(plot["size"])*0.5
		var center := Vector2(plot["x"],plot["z"])+Vector2.ONE*half
		if can_act_at(center.x,center.y): plots.append(plot)
	return plots


func promised_home_limit() -> int:
	var opening: Dictionary=_state["opening"]
	var level: String="timeline_population_card" if Opening.supports_timeline_housing(opening) else "growth_population_card"
	if Opening.supports_shrine_housing(opening): level="shrine_population_card"
	return int(opening["definition"][level]["population"])/int(_state["homes"][0]["capacity"])


func has_room_for_growth(reserved: int=0) -> bool:
	return Opening.supports_discovery(_state["opening"]) or dwelling_count()+reserved<promised_home_limit()


func promised_plot_reachable(plot: Dictionary,origin: Vector2i) -> bool:
	var size := int(plot["size"])
	var footprint := Rect2i(int(plot["x"]),int(plot["z"]),size,size)
	return not _promised_abode_approach(origin,footprint,{}).is_empty()


func growth_plots_from(origin: Vector2) -> Array:
	var plots := promised_growth_plots()
	plots.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var distance_a := origin.distance_squared_to(Vector2(a["x"],a["z"])+Vector2.ONE*float(a["size"])*0.5)
		var distance_b := origin.distance_squared_to(Vector2(b["x"],b["z"])+Vector2.ONE*float(b["size"])*0.5)
		return a["id"]<b["id"] if distance_a==distance_b else distance_a<distance_b)
	return plots


func start_growth_construction() -> Array:
	var ids: Array=[]
	if _state["homes"].is_empty(): return ids
	for follower: Dictionary in _state["followers"]:
		if not has_room_for_growth(): break
		if not follower.get("seeking_plot",false): continue
		var origin := Vector2(follower["x"],follower["z"])
		for plot: Dictionary in growth_plots_from(origin):
			if begin_promised_abode(plot,int(follower["id"])):
				ids.append(_state["homes"].back()["id"])
				break
	return ids


func _promised_abode_approach(start: Vector2i,footprint: Rect2i,reserved: Dictionary,avoid_footprint: bool=false) -> Dictionary:
	var best := {}
	for offset in range(footprint.size.x):
		for target: Vector2i in [Vector2i(footprint.position.x-1,footprint.position.y+offset),Vector2i(footprint.end.x,footprint.position.y+offset),Vector2i(footprint.position.x+offset,footprint.position.y-1),Vector2i(footprint.position.x+offset,footprint.end.y)]:
			if reserved.has(target) or height_at(target.x,target.y)<=0 or _occupied(target.x,target.y): continue
			var route := _route(start,target,-1,footprint) if avoid_footprint else _route(start,target)
			if start!=target and route.is_empty() or not best.is_empty() and route.size()>=best["path"].size(): continue
			var enters := false
			var outside := not footprint.has_point(start)
			for cell: int in route:
				if footprint.has_point(Vector2i(cell%int(_state["width"]),cell/int(_state["width"]))):
					if outside: enters=true; break
				else: outside=true
			if not enters: best={"target":target,"path":route}
	return best


func advance_promised_abode(wait_to_enter: bool=false) -> Array:
	var events: Array=[]
	var construction := {}
	for home: Dictionary in _state["homes"]:
		if home["progress"]<home["build_ticks"]: construction[home["id"]]=true
	for follower: Dictionary in _state["followers"]:
		if not construction.has(follower["job"]): continue
		var work := Vector2i(follower["work_x"],follower["work_z"])
		finish_promised_approach(follower,work)
		_update_agent(follower,false)
	if not construction.is_empty(): _advance_construction()
	var use_assigned_entrance: bool=Opening.supports_growth(_state["opening"]) or Opening.supports_timeline_housing(_state["opening"]) or _state["opening"]["phase"] in ["shrine","discovery"]
	var fallback: int=-1 if use_assigned_entrance else _state["homes"].back()["id"]
	for home: Dictionary in _state["homes"]:
		if home["progress"]<home["build_ticks"]: continue
		if construction.has(home["id"]):
			events.append({"hook":"onAbodeComplete","id":home["id"]})
			continue
		if wait_to_enter: continue
		var entrance := Vector2i(home["work_x"],home["work_z"])
		for follower: Dictionary in _state["followers"]:
			if follower["state"]=="indoors" or follower.get("entering_home",fallback)!=home["id"] or home["residents"]>=home["capacity"]: continue
			var position := Vector2(follower["x"],follower["z"])
			if position.distance_to(Vector2(entrance))<0.01:
				follower["state"]="indoors"
				follower["indoors_home"]=home["id"]
				follower.erase("entering_home")
				follower.erase("away_home")
				follower["path"]=[]
				home["residents"]+=1
				events.append({"hook":"onEnterHouse","id":follower["id"]})
			else:
				if follower["path"].is_empty(): follower["path"]=_route(Vector2i(position.round()),entrance)
				finish_promised_approach(follower,entrance)
				if not follower["path"].is_empty(): _update_agent(follower,false)
	return events


func finish_promised_approach(follower: Dictionary,target: Vector2i) -> void:
	# Sculpting clears routes mid-stride. A route to the rounded current cell
	# is empty even when the follower still needs to reach its exact waypoint.
	if not follower["path"].is_empty(): return
	var position := Vector2(follower["x"],follower["z"])
	if Vector2i(position.round())==target and position.distance_to(Vector2(target))>=0.01:
		follower["path"].append(target.y*int(_state["width"])+target.x)


func advance_promised_breeding() -> void:
	var away := {}
	for follower: Dictionary in _state["followers"]:
		if follower.has("away_home"):
			var home_id := int(follower["away_home"])
			away[home_id]=int(away.get(home_id,0))+1
	for home: Dictionary in _state["homes"]:
		if home["progress"]<home["build_ticks"] or home["residents"]<=0 or home["residents"]+int(away.get(home["id"],0))>=home["capacity"] or home.get("breed_locked",false): continue
		var elapsed := int(home.get("breed_ticks",0))+1
		home["breed_ticks"]=elapsed
		if elapsed<preload("res://simulation/building_stats.gd").authored_birth_interval(_state,home): continue
		var follower := _agent(home["work_x"],home["work_z"],false)
		follower["state"]="indoors"
		follower["indoors_home"]=home["id"]
		_state["followers"].append(follower)
		home["residents"]+=1
		home["breed_ticks"]=0


func house_spec(rank: int = -1) -> Dictionary:
	return cached_house_spec(rank).duplicate(true)


func cached_house_spec(rank: int = -1) -> Dictionary:
	if not _state.has("progression"): return {"span":2}
	var p: Dictionary = _state["progression"]
	if rank<0: rank=int(p["max_rank"])
	if rank<1 or rank>int(p["max_rank"]): return {}
	var family := mini(1,int(p["abode_type"]))
	var key := Vector3i(rank,family,int(p["max_rank"]))
	if _house_specs.has(key): return _house_specs[key]
	for source: Dictionary in p["rules"]["houses"]:
		if source["family"]==family and source["rank"]==rank:
			_house_specs[key]=source.duplicate(true) if source.has("model_id") else {}
			if not _house_specs[key].is_empty(): _house_specs[key]["build_ticks"]=Economy.build_ticks(_state,source)
			return _house_specs[key]
	return {}


func _refresh_abode_timers() -> void:
	_house_specs.clear()
	for home: Dictionary in _state["homes"]:
		if home.get("kind","")!="": continue
		for source: Dictionary in _state["progression"]["rules"]["houses"]:
			if source["family"]!=home.get("family",0) or source["rank"]!=home.get("rank",1) or not source.has("build_ticks"): continue
			var fraction := float(home["progress"])/maxi(1,int(home["build_ticks"]))
			home["build_ticks"]=Economy.build_ticks(_state,source)
			home["progress"]=mini(home["build_ticks"],roundi(fraction*int(home["build_ticks"])))
			break


func _complete_shrine(home: Dictionary) -> void:
	for shrine: Dictionary in _state["progression"]["shrines"]:
		if shrine["id"]!=home["shrine_id"] or shrine["complete"]: continue
		if preload("res://simulation/temple_rules.gd").complete(_state["progression"],shrine["id"]): _give_progression_card(shrine["card"])


func _give_progression_card(id: String) -> void:
	Progression.reward(_state,id)
	var definition: Dictionary = _state["progression"]["rules"]["cards"].get(id,{})
	var count := int(definition.get("reward",{}).get("followers",0))
	if count>0:
		var origin: Dictionary = _state["camera_start"]
		for index in range(count): _state["followers"].append(_agent(origin["x"],origin["z"],false))
		_recover_agents()


func _advance_land_effects(events: Array) -> void:
	var progression_rules: Dictionary=_state.get("progression",{}).get("rules",{})
	var rules: Dictionary=progression_rules.get("beautify_rules",{})
	if not rules.has("timer"):
		return
	if not _state.has("source_influence") and not _state.has("map_fields"):
		_state["map_fields"]=SourceRaster.initial()
	var raster: Dictionary=_state.get("source_influence",{}).get("raster",_state.get("map_fields",{}))
	var now := int(_state["tick"])*roundi(TICK_SECONDS*1000.0)
	var interval := Beautify.timer_interval(rules,progression_rules["config"])
	var cells := LandEffectTimer.advance(raster,now,interval,-1.0,rules["timer"])
	if not cells.is_empty():
		if _state.has("map_fields"): AbodeBeauty.refresh_expired(_state,cells)
		events.append({"type":"land_effect_expired","cells":cells})


func _beautify_ground(x: int,z: int) -> float:
	if x<0 or z<0 or x>=int(_state["width"]) or z>=int(_state["width"]):
		return -1.0
	if _state.has("opening"):
		return float(source_raw_height_at(x,z))
	return float(height_at(x,z)+19)


func _inspect_beautify(command: Dictionary,result: Dictionary) -> Dictionary:
	var p: Dictionary=_state["progression"]
	var rules: Dictionary=p["rules"].get("beautify_rules",{})
	if rules.is_empty():
		return result
	var raster: Dictionary=_state.get("source_influence",{}).get("raster",_state.get("map_fields",{"fields":{}}))
	var plan := Beautify.quote(raster,float(command["x"]),float(command["z"]),rules,p["rules"]["config"],_beautify_ground)
	if plan.is_empty():
		return {"ok":false,"cost":0,"reason":""}
	var arm_cost := int(result["cost"])
	var charge := float(plan["charge"])
	var remainder := float(p.get("beautify_cost_remainder",0.0))
	if charge>0.0:
		var total := Beautify.Terrain.f32(charge+remainder)
		var debit := int(total)
		var available := int(_state["belief"])-arm_cost
		if available<debit or (debit==0 and float(available)<total):
			return {"ok":false,"cost":arm_cost+debit,"reason":""}
		result["cost"]=arm_cost+debit
		remainder=Beautify.Terrain.f32(total-debit)
	plan["remainder"]=remainder
	result["beautify"]=plan
	return result


func _apply_progression(command: Dictionary, events: Array,result: Dictionary) -> void:
	var p: Dictionary = _state["progression"]
	match command["type"]:
		"open_chest":
			for chest: Dictionary in p["chests"]:
				if chest["id"]!=command["id"]: continue
				var reward: String = chest["card"]
				var quantity: Dictionary=p["rules"]["cards"].get(reward,{}).get("reward",{})
				if p["rules"].has("reward_cards") and not p["rules"]["reward_cards"].has(reward) and quantity.is_empty(): reward=""
				if reward.is_empty(): reward=Progression.random_reward(p,_random)
				if reward.is_empty() or not p["rules"]["cards"].has(reward): return
				chest["opened"] = true
				_give_progression_card(reward)
				var show_card: bool=not p["rules"].has("reward_cards") or p["rules"]["reward_cards"].has(reward)
				events.append({"type":"chest_opened","id":chest["id"],"card":reward if show_card else "","reward":quantity.duplicate(true)})
		"tap_object":
			if command.has("cell"):
				var key := str(int(command["cell"]))
				p["rock_taps"][key]=int(p["rock_taps"].get(key,0))+1
				if p["rock_taps"][key]>=int(p["rules"]["config"].get("tapsToDestroyRock",2)):
					p["rock_revision"]+=1
					var variant := (int(_state["rocks"][int(command["cell"])])-1)%7
					_state["belief"]+=int(p["rules"].get("object_belief",{}).get(str(15+variant),0))
					if not "Card_Spirituality" in p["discovered"] and p["first_card_tick"]<0: p["first_card_tick"]=_state["tick"]+roundi(float(p["rules"]["config"].get("GiveFirstCardDelay",3.3))/TICK_SECONDS)
				return
			for object: Dictionary in p["objects"]:
				if object["id"]!=command["id"]: continue
				object["taps"] += 1
				if object["taps"]>=int(p["rules"]["config"].get("tapsToDestroyRock",2)):
					object["removed"] = true
					if not "Card_Spirituality" in p["discovered"] and p["first_card_tick"]<0: p["first_card_tick"]=_state["tick"]+roundi(float(p["rules"]["config"].get("GiveFirstCardDelay",3.3))/TICK_SECONDS)
		"use_power":
			var power: String = command["power"]
			var duration_key: String = {"GodPower_Beautify":"BeautifyLength","GodPower_FingerOfGod":"FingerOfGodLength"}.get(power,"")
			if not str(duration_key).is_empty() and int(p["active_powers"].get(power,-1))<=int(_state["tick"]): p["active_powers"][power]=_state["tick"]+roundi(float(p["rules"]["config"].get(duration_key,0))/TICK_SECONDS)
			if power=="GodPower_Totem": p["totem"]={"x":int(command["x"]),"z":int(command["z"]),"active":true}
			elif power=="GodPower_TotemActivate": p["totem"]["active"]=not p["totem"].get("active",false)
			elif power=="GodPower_Beautify":
				if result.has("beautify"):
					if not _state.has("source_influence") and not _state.has("map_fields"):
						_state["map_fields"]=SourceRaster.initial()
					var raster: Dictionary=_state.get("source_influence",{}).get("raster",_state.get("map_fields",{}))
					var changed: Array=[]
					Beautify.apply(raster,result["beautify"],p["rules"]["beautify_rules"],_beautify_ground,changed)
					p["beautify_cost_remainder"]=result["beautify"]["remainder"]
					for item: Array in changed:
						if item[0]=="refresh":
							var area := item.slice(1)
							AbodeBeauty.refresh(_state,_state["homes"],area)
							events.append({"type":"beautify_terrain","area":area})
			elif power=="GodPower_FingerOfGod":
				for home: Dictionary in _state["homes"].duplicate():
					if home.get("kind","")=="shrine" or command.has("home_id") and int(command["home_id"])!=int(home["id"]): continue
					if int(command["x"])>=home["x"] and int(command["x"])<home["x"]+int(home.get("span",2)) and int(command["z"])>=home["z"] and int(command["z"])<home["z"]+int(home.get("span",2)):
						_state["homes"].erase(home)
						_spatial_revision+=1
						for follower: Dictionary in _state["followers"]:
							if follower["job"]==home["id"]: follower["job"]=-1
						break
				for follower: Dictionary in _state["followers"].duplicate():
					if Vector2(follower["x"],follower["z"]).distance_to(Vector2(command["x"],command["z"]))<0.6:
						_state["followers"].erase(follower)
						break
				Economy.reconcile(_state)
			p["revision"] += 1
			if power in ["GodPower_Totem","GodPower_TotemActivate"]:
				for follower: Dictionary in _state["followers"]:
					if follower["job"]==-1:
						follower["path"]=[]
						follower["state"]="idle"
						follower["wait"]=0


func install_weyworld_tutorial(rules: Dictionary) -> void:
	if rules.is_empty() or _state.has("weyworld"): return
	var updated: Dictionary=_state["progression"]["rules"].duplicate(true)
	updated["weyworld"]=rules.duplicate(true)
	_state["progression"]["rules"]=Immutable.freeze(updated)
	Weyworld.initialize(self,_state)


func migrate_progression(rules: Dictionary,rocks: PackedByteArray) -> void:
	_plan_stamp=-1
	_house_specs.clear()
	var old: Dictionary = _state.get("progression",{})
	var merged := rules.duplicate(true)
	# A content migration must not discard the player's saved CSV balance.
	for key: String in ["config","houses","followers","influence_enabled","sticker_aliases"]:
		if old.get("rules",{}).has(key): merged[key]=old["rules"][key].duplicate(true) if old["rules"][key] is Dictionary or old["rules"][key] is Array else old["rules"][key]
	if not merged["config"].has("templeFixerFalloff"): merged["config"]["templeFixerFalloff"]=rules["config"]["templeFixerFalloff"]
	for house: Dictionary in merged["houses"]:
		for source: Dictionary in rules["houses"]:
			if source["family"]!=house["family"] or source["rank"]!=house["rank"]: continue
			for field: String in ["wheat_cost","ore_cost","new_builder_contribution"]:
				if not house.has(field) and source.has(field): house[field]=source[field]
	for site: Dictionary in merged["shrines"]:
		for previous: Dictionary in old.get("rules",{}).get("shrines",[]):
			if previous["id"]==site["id"] and previous.has("build_ticks"): site["build_ticks"]=previous["build_ticks"]
	var updated := Progression.initialize(merged,_state["terrain"],int(_state["width"]))
	for field in ["discovered","completed","inventory","max_rank","abode_type","totem_capacity","totem","beautify_cost_remainder","first_card_tick","age","last_reward","revision","rock_taps","rock_revision","active_powers","player_level","research","assigned_resources","settlements","reward_history","happiness","supply_next_tick","supply_serial"]:
		if old.has(field): updated[field]=old[field]
	updated["prior_research"]=old.get("prior_research",{}).duplicate(true)
	if old.get("rules",{}).get("research_scope","initialworldsetup")!=merged.get("research_scope","initialworldsetup") and not updated["research"].is_empty():
		updated["prior_research"][old.get("rules",{}).get("research_scope","initialworldsetup")]=updated["research"].duplicate(true)
	updated["research"]=updated["research"].duplicate(true)
	for id: String in updated["research"].keys():
		if not merged.get("research_cards",{}).has(id): updated["research"].erase(id)
		else: updated["research"][id]=mini(int(updated["research"][id]),int(merged["research_cards"][id]["research_needed"]))
	updated["assigned_resources"]=updated["assigned_resources"].duplicate(true)
	updated["inventory"]=updated["inventory"].duplicate(true)
	for id: String in updated["assigned_resources"]:
		if not merged.get("research_cards",{}).has(id) or old.get("rules",{}).get("research_cards",{}).has(id): continue
		var assigned := {}
		var points := 0
		var card: Dictionary=merged["research_cards"][id]
		for resource: String in updated["assigned_resources"][id]:
			var canonical: String=merged.get("sticker_aliases",{}).get(resource,resource)
			var count := int(updated["assigned_resources"][id][resource])
			var contribution := int(merged.get("stickers",{}).get(canonical,{}).get("contributions",{}).get(card["research_type"],0))
			if contribution<=0:
				if not id in updated["completed"]: updated["inventory"][resource]=int(updated["inventory"].get(resource,0))+count
				continue
			assigned[canonical]=int(assigned.get(canonical,0))+count
			points+=count*contribution
		updated["assigned_resources"][id]=assigned
		updated["research"][id]=mini(points,int(card["research_needed"]))
	if old.is_empty():
		updated["discovered"]=_state["campaign"]["cards"].duplicate()
		updated["completed"]=_state["campaign"]["cards"].duplicate()
		for id: String in updated["completed"]:
			if id.begins_with("Card_MaxRank_"): updated["max_rank"]=maxi(int(updated["max_rank"]),int(id.get_slice("_",2)))
			if id.begins_with("Card_AbodeType_"): updated["abode_type"]=maxi(int(updated["abode_type"]),int(id.get_slice("_",2))-1)
	for chest: Dictionary in updated["chests"]:
		for previous: Dictionary in old.get("chests",[]):
			if previous["id"]==chest["id"]: chest["opened"]=previous["opened"]
	for previous: Dictionary in old.get("chests",[]):
		if previous.get("generated",false): updated["chests"].append(previous.duplicate(true))
	for shrine: Dictionary in updated["shrines"]:
		for previous: Dictionary in old.get("shrines",[]):
			if previous["id"]==shrine["id"]:
				shrine["started"]=previous["started"]
				shrine["complete"]=previous["complete"]
				if previous.get("source_height")!=null: shrine["source_height"]=previous["source_height"]
				if shrine["started"]:
					shrine["x"]=previous["x"]
					shrine["z"]=previous["z"]
	_state["progression"]=updated
	Immutable.freeze(_state["progression"]["rules"])
	Weyworld.initialize(self,_state)
	var footprint_changed := false
	for home: Dictionary in _state["homes"]:
		if home.get("kind","")=="shrine":
			if not home.has("temple_work"): home["temple_work"]=preload("res://simulation/source_terrain.gd").f32((float(home["progress"])+float(home.get("work_accumulator",0)))*TICK_SECONDS)
			for site: Dictionary in updated["shrines"]:
				if site["id"]!=home.get("shrine_id",""): continue
				var region := preload("res://simulation/temple_rules.gd").footprint(site)
				var span := maxi(region.size.x,region.size.y)
				if int(home["x"])!=region.position.x or int(home["z"])!=region.position.y or int(home.get("span",2))!=span:
					footprint_changed=true
					home["x"]=region.position.x; home["z"]=region.position.y; home["span"]=span
					home["access_path"]=[]
					home["work_x"]=maxi(0,region.position.x-1); home["work_z"]=region.position.y
					for follower: Dictionary in _state["followers"]:
						if follower["job"]!=home["id"]: continue
						follower["job"]=-1; follower["state"]="idle"; follower["path"]=[]
						follower.erase("work_x"); follower.erase("work_z")
				for field: String in ["model_id","build_capacity","build_priority","rotation"]:
					if site.has(field): home[field]=site[field]
		if home.has("new_builder_contribution"): continue
		if home.get("kind","") in ["farm","mine"]:
			var specification: Dictionary=merged.get("economy",{}).get("plots",{}).get("%s:%d"%[home["kind"],int(home["rank"])],{})
			if specification.has("new_builder_contribution"): home["new_builder_contribution"]=specification["new_builder_contribution"]
		elif home.get("kind","")=="":
			for house: Dictionary in merged["houses"]:
				if house["family"]==home.get("family",0) and house["rank"]==home.get("rank",1) and house.has("new_builder_contribution"):
					home["new_builder_contribution"]=house["new_builder_contribution"]
					break
	if not _state.has("rocks"): _state["rocks"]=rocks.duplicate()
	if not _state.has("gems"): _state["gems"]=int(rules["config"].get("InitialGems",100))
	if footprint_changed:
		_spatial_revision+=1
		_recover_agents()
	AbodeBeauty.refresh(_state,_state["homes"])
	Progression.refresh(_state)
	Influence.refresh(_state)


func plan_worker(id: int) -> Dictionary:
	var item := Economy.settlement(_state,id)
	if item.is_empty(): return {"ok":false,"cost":0,"reason":""}
	var available: Array=[]
	for agent: Dictionary in _state["followers"]:
		if Economy.worker_available(_state,agent,item): available.append(agent)
	if available.is_empty(): return {"ok":false,"cost":0,"reason":""}
	var existing := Economy.plan_existing_plot(self,_state,item,available)
	if not existing.is_empty(): return existing
	var radius := ceili(float(item["radius"]))
	# Larger source fields become viable when the player clears enough space.
	# Test each footprint, affordability and route through the same command gate.
	var ranks: Array = [-1] if item["role"]=="builder" else [6,5,4,3,2,1]
	for rank: int in ranks:
		for distance in range(2,radius+1):
			for dz in range(-distance,distance+1):
				for dx: int in [-distance,distance] if absi(dz)<distance else range(-distance,distance+1):
					var command := {"type":"home" if item["role"]=="builder" else "work_plot","x":int(item["x"])+dx,"z":int(item["z"])+dz,"settlement_id":id,"rank":rank}
					var result := _validate(command)
					if result["ok"]:
						result["plot_command"]=command
						return result
	return {"ok":false,"cost":0,"reason":""}


func deploy_source_worker(plan: Dictionary,events: Array) -> void:
	if plan.has("field"):
		Farming.staff_field(_state,plan)
		return
	var field_id:=Farming.start_field(self,_state,plan)
	if field_id<0 or plan["field_spec"]["kind"]!="farm": return
	var intro:=Opening.new()
	intro.configure(self,_state,events)
	intro.farming_hook("onFollowerSprogged",[plan["worker"]])
	intro.farming_hook("onAbodeBuilding",[field_id])


func _prepare_plan_reservations() -> void:
	var stamp := hash(Vector3i(_spatial_revision,_state.get("progression",{}).get("revision",0),_state["homes"].size()))
	if stamp==_plan_stamp: return
	_plan_stamp=stamp
	_plan_reserved.clear()
	var width: int = _state["width"]
	for home: Dictionary in _state["homes"]:
		for cell: int in home.get("access_path",[]): _plan_reserved[cell]="home:%d" % home["id"]
		_plan_reserved[int(home["work_z"])*width+int(home["work_x"]) ]="home:%d" % home["id"]
	if not _state.has("progression"): return
	for chest: Dictionary in _state["progression"]["chests"]:
		if not chest["opened"] and chest["height"]>=0: _plan_reserved[int(chest["z"])*width+int(chest["x"]) ]="chest:"+chest["id"]
	for shrine: Dictionary in _state["progression"]["shrines"]:
		var region := preload("res://simulation/temple_rules.gd").footprint(shrine)
		if not shrine.get("complete",false) and int(shrine.get("build_ticks",0))>0: region=region.grow(1)
		for z in range(maxi(0,region.position.y),mini(width,region.end.y)):
			for x in range(maxi(0,region.position.x),mini(width,region.end.x)): _plan_reserved[z*width+x]="shrine:"+shrine["id"]


func runtime_value(key: String,fallback: float) -> float:
	return float(_state.get("runtime",{}).get(key,fallback))


func reconfigure(changes: Array) -> Dictionary:
	if not _state.has("progression"): return {"ok":false,"message":"Start a campaign before applying its balance."}
	var rules: Dictionary = _state["progression"]["rules"].duplicate(true)
	var runtime: Dictionary = _state.get("runtime",{}).duplicate(true)
	var influence_changed := false
	for change: Variant in changes:
		if change is Dictionary and change.get("category")=="house_name":
			var unit: PackedStringArray=str(change.get("unit","")).split(":")
			var label: String=str(change.get("label","")).strip_edges()
			if unit.size()!=2 or not unit[0].is_valid_int() or not unit[1].is_valid_int() or label.is_empty() or label.length()>100: return {"ok":false,"message":"Invalid abode identity."}
			var family := int(unit[0])
			var rank := int(unit[1])
			if family<0 or family>4 or rank<1 or rank>6: return {"ok":false,"message":"Unknown abode family/rank."}
			var found := false
			for house: Dictionary in rules["houses"]:
				if house["family"]==family and house["rank"]==rank: house["name"]=label; found=true
			if not found: rules["houses"].append({"family":family,"rank":rank,"name":label})
			continue
		if not change is Dictionary or not (change.get("value") is int or change.get("value") is float) or not is_finite(float(change["value"])): return {"ok":false,"message":"Constants must be finite numbers."}
		var value := float(change["value"])
		var category: String = change.get("category","")
		match category:
			"config":
				var key: String = change.get("key","")
				if not rules["config"].has(key) or value<(-1 if key.begins_with("belief_") else 0) or value>1e12: return {"ok":false,"message":"Invalid source configuration: "+key}
				if key.begins_with("OutOfRange.") or key.begins_with("Light") or key.begins_with("BGColour."):
					if value>4: return {"ok":false,"message":"Color/light values must be between 0 and 4."}
				if key in ["InitialTotemCapacity","tapsToDestroyRock","FirstCardIndex"] and (value<1 or value!=int(value)): return {"ok":false,"message":key+" must be a positive integer."}
				if key=="templeFixerFalloff" and value>8: return {"ok":false,"message":"Temple fixer falloff must be between 0 and 8."}
				rules["config"][key]=str(value)
			"house":
				var field: String = change.get("field","")
				if not field in ["span","capacity","max_belief","min_belief","build_ticks","birth_ticks","vision_radius","build_capacity","build_priority","new_builder_contribution","breeder_count","belief_modifier","belief_multiplier"] or value<0 or value>31536000: return {"ok":false,"message":"Invalid abode constant."}
				if field=="new_builder_contribution" and value>8: return {"ok":false,"message":"Builder contribution must be between 0 and 8."}
				if field in ["span","capacity","build_ticks","birth_ticks","vision_radius","build_capacity"] and value<=0: return {"ok":false,"message":"Abode sizes and timers must be positive."}
				if field=="span" and (value<1 or value>32 or value!=int(value)): return {"ok":false,"message":"Plot span must be an integer from 1 to 32."}
				if field=="capacity" and (value<1 or value>10000): return {"ok":false,"message":"Invalid abode capacity."}
				var found := false
				for house: Dictionary in rules["houses"]:
					if house["family"]==change.get("family") and house["rank"]==change.get("rank"):
						house[field]=maxi(1,roundi(value*10)) if field.ends_with("_ticks") else (int(value) if field in ["span","min_belief","max_belief","breeder_count"] else value)
						found=true
				if not found: return {"ok":false,"message":"Unknown abode row."}
			"follower":
				var race: String=change.get("race","")
				var field: String=change.get("field","")
				if not race in ["Brown Head","Red Head","Champion","Astari"] or not field in ["MaxHealth","RouteSpeed","Vision","Stamina","Strength","JobSkill","ReactionSkill","StaminaGainAtHome","StaminaGainSitting","MinReactionPriority","FireDamage","SwampDamage","DrownDamage","BlightedDamage","SwimDamage","StaminaDecay","Scale","FullScorchedSpeedMult","FullBeautifySpeedMult","BasketCapacity"] or value<0 or value>1e6: return {"ok":false,"message":"Invalid follower value."}
				if field in ["MaxHealth","RouteSpeed","Vision","JobSkill","Scale"] and value<=0: return {"ok":false,"message":field+" must be positive."}
				if not rules.has("followers"): rules["followers"]={}
				if not rules["followers"].has(race): rules["followers"][race]={}
				rules["followers"][race][field]=value
			"influence":
				var index := int(change.get("index",-1))
				var field: String = change.get("field","")
				if change.has("offset_from_default"):
					if not field in ["x","z","radius"] or not (change["offset_from_default"] is int or change["offset_from_default"] is float) or not is_finite(float(change["offset_from_default"])): return {"ok":false,"message":"Invalid influence edit."}
					index=-1
					for i in range(rules["influence_areas"].size()):
						if rules["influence_areas"][i]["unlock"]==change.get("unlock",""): index=i; break
					if index<0: continue
					var defaults: Array=rules.get("influence_defaults",rules["influence_areas"])
					value=float(defaults[index][field])+float(change["offset_from_default"])
				elif field in ["x","z"] and change.has("reference_offset"):
					var reference: Variant = change["reference_offset"]
					if not reference is Array or reference.size()!=2: return {"ok":false,"message":"Invalid influence registration."}
					var axis := 0 if field=="x" else 1
					if not (reference[axis] is int or reference[axis] is float) or not is_finite(float(reference[axis])): return {"ok":false,"message":"Invalid influence registration."}
					value+=float(rules.get("registration_offset",[0,0])[axis])-float(reference[axis])
				if index<0 or index>=rules["influence_areas"].size() or not field in ["x","z","radius"] or value<-float(_state["width"]) or value>float(_state["width"])*2 or (field=="radius" and value<=0): return {"ok":false,"message":"Invalid influence constant."}
				influence_changed=influence_changed or float(rules["influence_areas"][index][field])!=value
				rules["influence_areas"][index][field]=value
			"card","requirement":
				var id: String = change.get("id","")
				if not rules["cards"].has(id) or value<(-1 if category=="card" and change.get("field")=="age" else 0) or value>1e6 or value!=int(value): return {"ok":false,"message":"Invalid card constant: "+id}
				if category=="card":
					var field: String = change.get("field","")
					if not field in ["age","number"]: return {"ok":false,"message":"Unknown card field."}
					rules["cards"][id][field]=int(value)
				else:
					var resource: String = change.get("resource","")
					if not rules["cards"].has(resource) or rules["cards"][resource]["type"]!=1: return {"ok":false,"message":"Unknown card resource."}
					if value==0: rules["cards"][id]["requirements"].erase(resource)
					else: rules["cards"][id]["requirements"][resource]=int(value)
			"shrine":
				if change.has("registered_scope") and change["registered_scope"]!=rules.get("registered_scope",""): continue
				if value<=0 or value>31536000: return {"ok":false,"message":"Shrine repair time must be positive."}
				var found := false
				for shrine: Dictionary in rules["shrines"]:
					if shrine["id"]==change.get("id"): shrine["build_ticks"]=maxi(1,roundi(value*10)); found=true
				if not found: return {"ok":false,"message":"Unknown shrine."}
			"runtime":
				var key: String = change.get("key","")
				if not key in ["follower_speed","sheep_speed","build_rate","birth_rate","belief_rate","sculpt_cost","home_search_radius"] or value<0 or value>1000: return {"ok":false,"message":"Invalid runtime constant."}
				if key!="sculpt_cost" and value<=0: return {"ok":false,"message":key+" must be positive."}
				if key=="home_search_radius" and (value>32 or value!=int(value)): return {"ok":false,"message":"Home search radius must be an integer from 1 to 32."}
				runtime[key]=value
			_:
				return {"ok":false,"message":"Unknown constant category."}
	var chance := 0.0
	for key in ["Cards_PercentChanceToGetCardYouNeed","Cards_PercentChanceToGetOtherUsefulCard","Cards_PercentChanceToGetRandomCard"]: chance+=float(rules["config"].get(key,0))
	if not is_equal_approx(chance,100): return {"ok":false,"message":"Chest reward chances must total 100 percent."}
	_state["runtime"]=Progression.canonical_numbers(runtime)
	_state["progression"]["rules"]=Immutable.freeze(Progression.canonical_numbers(rules))
	_house_specs.clear()
	rules=_state["progression"]["rules"]
	if influence_changed and _state.has("source_influence"):
		var unlocked := func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(_state["progression"],key)
		# Original CSV table reload clears both influence fields and resets area
		# radii. Apply that zero-delta rebuild at this configuration boundary.
		preload("res://simulation/source_influence_areas.gd").advance(_state["source_influence"],rules["influence_areas"],_state["opening"]["definition"]["influence_rules"],unlocked,0.0,[],true,true)
	_state["progression"]["revision"]+=1
	_state["progression"]["totem_capacity"]=int(rules["config"].get("InitialTotemCapacity",4))+(5 if "Card_TotemCapacity" in _state["progression"]["completed"] else 0)
	for home: Dictionary in _state["homes"]:
		if home.get("kind","")=="ark": continue
		var duration: int = home.get("build_ticks",_state.get("build_ticks",BUILD_TICKS))
		var fraction := float(home["progress"])/duration
		if home.get("kind","")=="shrine":
			for shrine: Dictionary in rules["shrines"]:
				if shrine["id"]==home["shrine_id"]: home["build_ticks"]=shrine["build_ticks"]
			if int(home["build_ticks"])!=duration:
				var work_fraction := float(home.get("temple_work",float(home["progress"])*TICK_SECONDS))/(duration*TICK_SECONDS)
				home["temple_work"]=preload("res://simulation/source_terrain.gd").f32(work_fraction*int(home["build_ticks"])*TICK_SECONDS)
		elif home.get("kind","") in ["farm","mine"]:
			var spec: Dictionary = rules.get("economy",{}).get("plots",{}).get("%s:%d"%[home["kind"],int(home["rank"])],{})
			for field: String in ["capacity","min_belief","max_belief","build_ticks","harvest_rate","vision_radius","wheat_cost","ore_cost","new_builder_contribution"]:
				if spec.has(field): home[field]=spec[field]
		else:
			for house: Dictionary in rules["houses"]:
				if house["family"]==home.get("family",0) and house["rank"]==home.get("rank",1):
					for field in ["name","capacity","min_belief","max_belief","build_ticks","birth_ticks","vision_radius","build_capacity","build_priority","new_builder_contribution","breeder_count","belief_modifier","belief_multiplier","wheat_cost","ore_cost"]:
						if house.has(field): home[field]=int(house[field]) if field=="capacity" else house[field]
					home["build_ticks"]=Economy.build_ticks(_state,house)
			home["stored"]=mini(int(home["stored"]),int(home.get("max_belief",30)))
		if home.get("kind","")=="shrine" and home.has("temple_work"):
			var work_ticks := float(home["temple_work"])/TICK_SECONDS
			home["progress"]=mini(int(home["build_ticks"]),floori(work_ticks))
			home["work_accumulator"]=0.0 if home["progress"]>=int(home["build_ticks"]) else work_ticks-floorf(work_ticks)
		else: home["progress"]=mini(int(home["build_ticks"]),roundi(fraction*int(home["build_ticks"])))
	AbodeBeauty.refresh(_state,_state["homes"])
	for shrine: Dictionary in _state["progression"]["shrines"]:
		for source: Dictionary in rules["shrines"]:
			if shrine["id"]==source["id"]: shrine["build_ticks"]=source["build_ticks"]
	for agent: Dictionary in _state["followers"]:
		var stats := follower_values(agent)
		agent["max_health"]=float(stats.get("MaxHealth",100))
		agent["health"]=minf(float(agent.get("health",agent["max_health"])),agent["max_health"])
		agent["scale"]=float(stats.get("Scale",1))
	Progression.refresh(_state)
	Influence.refresh(_state)
	if influence_changed and rules.has("registered_scope"): Economy.fill_free_harvest(_state)
	_plan_stamp=-1
	return {"ok":true,"message":"Applied %d constants. Existing plot footprints are preserved; new plots use the new sizes." % changes.size()}


func query_copy() -> RefCounted:
	# Detached query ownership: application may inspect this copy on the main
	# thread while the authoritative world advances on its worker.
	var copy: RefCounted=get_script().new()
	copy._state=detached_state(false)
	copy._models=_models if _models.is_read_only() else _models.duplicate(true)
	copy._tree_cells=_tree_cells # Immutable index shared by detached query owners.
	copy._tree_coast=_tree_coast
	copy._tree_rows=_tree_rows
	copy._tree_tiles=_tree_tiles
	copy._dry_land=_dry_land
	copy._random=RandomNumberGenerator.new()
	copy._random.seed=_random.seed
	copy._random.state=_random.state
	return copy


func initialize_rocks(field: PackedByteArray,original_heights: PackedByteArray) -> void:
	_state["rocks"]=field.duplicate()
	_state["rock_heights"]=PackedByteArray()
	_state["rock_heights"].resize(field.size())
	for cell in range(field.size()):
		if field[cell]==0: continue
		if original_heights[cell]==0: _state["rocks"][cell]=0
		else: _state["rock_heights"][cell]=original_heights[cell]
	for object: Dictionary in _state.get("progression",{}).get("objects",[]):
		if _state.get("source_map",{}).get("id","")!="homeworld": break
		var type: String=object.get("type","")
		if not type.begins_with("rock") or not type.trim_prefix("rock").is_valid_int() or object.get("removed",false): continue
		var cell := int(object["z"])*int(_state["width"])+int(object["x"])
		if cell<0 or cell>=field.size() or original_heights[cell]==0: continue
		_state["rocks"][cell]=clampi(int(type.trim_prefix("rock")),1,7)
		_state["rock_heights"][cell]=original_heights[cell]


func migrate_rocks(original_heights: PackedByteArray,source_field: PackedByteArray=PackedByteArray()) -> void:
	if int(_state.get("rock_density_version",0))<1 and source_field.size()==original_heights.size():
		initialize_rocks(source_field,original_heights)
		_state["rock_density_version"]=1
		_state["progression"]["rock_revision"]+=1
	# Legacy saves retained underwater source records, which must not become
	# new objects when the player extends a coastal terrace.
	if _state.has("rocks") and not _state.has("rock_heights") and _state["rocks"].size()==original_heights.size():
		initialize_rocks(_state["rocks"],original_heights)
		_state["progression"]["rock_revision"]+=1


func follower_values(agent: Dictionary) -> Dictionary:
	return _state.get("progression",{}).get("rules",{}).get("followers",{}).get(str(agent.get("race","Brown Head")),{})
