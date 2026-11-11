extends SceneTree

const World = preload("res://simulation/world.gd")
const Chests = preload("res://simulation/authored_chests.gd")
const Progression = preload("res://simulation/progression.gd")
const Storms = preload("res://simulation/campaign_storms.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(not content.is_empty(),"Homeworld6 must load its original storm configuration")
	if failures: quit(1); return
	check_clock(content["story"])
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=525
	world.initialize({"campaign_data":content},random)
	world.initialize_authored_chests()
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var clock: Dictionary=opening["clock"]
	clock["speed"]=1.0
	world.step()
	check(not opening.has("storm"),"The campaign must not start storms before Farming is discovered")
	Progression.discover(state["progression"],"Card_Settlement_Farming")
	world.step()
	check(opening.has("storm"),"Discovering the original Farming card must enable storms")
	if failures: quit(1); return
	clock["days"]=2
	var storm_time := float(opening["definition"]["day_cycle"]["period"])*float(opening["definition"]["storm_timing"]["StormTimeOfDay"])
	clock["time"]=storm_time-0.01
	world.step()
	check(opening["storm"]["window"]==1,"Crossing the source time of day must advance the storm window")
	for day in range(2,14,2):
		if opening["storm"]["remaining"]>0:
			check(opening["storm"]["serial"]==0,"Chests must arrive at storm end")
			var restored := World.new()
			check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"An in-progress storm must survive reload")
			if failures: quit(1); return
			var reloaded_storm: Dictionary=restored._state["opening"]["storm"]
			check(reloaded_storm==opening["storm"],"Reloading must preserve the active storm countdown")
			while opening["storm"]["remaining"]>0: world.step()
			if opening["storm"]["serial"]>0: break
		clock["days"]=day+2
		clock["time"]=storm_time-0.01
		world.step()
	var generated: Array=opening["chests"].filter(func(chest: Dictionary) -> bool: return chest.has("serial"))
	check(not generated.is_empty(),"Storms must place new chests through the Homeworld6 simulation")
	if failures: quit(1); return
	var events: Array=[]
	var adapter := Chests.new()
	adapter.configure(world,state,events)
	adapter.random=random
	for chest: Dictionary in adapter.snapshot():
		if not chest["id"].begins_with("storm:"): continue
		check(chest["height"]>=float(world.sculpt_minimum_layer())-0.001 and world.can_act_at(chest["x"],chest["z"]),"New storm chests must stay above the depth limit inside active territory")
		var cue: Dictionary=chest.get("glint",{})
		check(cue.get("initial_delay",0.0)>=4.0 and cue.get("initial_delay",0.0)<=8.0,"Source storm chests must hand the original initial glint timer to presentation")
	var ids := {}
	for chest: Dictionary in generated:
		var id := Chests.identifier(chest)
		check(chest["source_id"]==0 and id.begins_with("storm:") and not ids.has(id),"Generated chests must retain distinct identities and source ID zero")
		ids[id]=true
	var handle := int(generated[0]["handle"])
	adapter.grant_story(opening,handle,0)
	check(events.size()==1 and events[0]["type"]=="chest_story_found" and opening["chest_story_dispatch"]["stories_acquired"].size()==1,"A storm story chest must use the original story registry")
	var gems: int=state["gems"]
	adapter.grant_card(opening,handle,"Sticker_Gem_1")
	check(state["gems"]==gems+1,"The source gem reward must credit the gem counter")
	var reloaded := World.new()
	check(reloaded.restore(world.export_state(),RandomNumberGenerator.new()),"Generated chests must survive reload")
	if not failures:
		var after: Array=reloaded._state["opening"]["chests"]
		check(Progression.canonical_numbers(after)==Progression.canonical_numbers(opening["chests"]),"A reload must preserve chest positions, identities and opening phases")
		check_submerged_budget(reloaded)
	print("Homeworld6 storm chest integration: ",failures," failures")
	quit(1 if failures else 0)


func check_clock(definition: Dictionary) -> void:
	var period: float=definition["day_cycle"]["period"]
	var fixture := {"definition":definition,"clock":{"time":period*0.95,"days":0}}
	var draws := [32767,0,0]
	var word := func() -> int: return draws.pop_front()
	Storms.advance(fixture,true,0.1,word)
	fixture["clock"]["days"]=2
	check(not Storms.advance(fixture,true,0.1,word) and fixture["storm"]["remaining"]==0,"A source chance miss must skip the storm")
	fixture["clock"]["days"]=4
	check(not Storms.advance(fixture,true,0.1,word) and fixture["storm"]["remaining"]==definition["storm_timing"]["stormLengthMin"],"A source chance hit must start the sampled storm duration")
	check(Storms.advance(fixture,true,definition["storm_timing"]["stormLengthMin"],word),"Storm completion must request replenishment")
	check(not Storms.advance(fixture,true,0.1,word) and draws.is_empty(),"A storm must replenish once and only roll at a crossed boundary")


func check_submerged_budget(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var chests: Array=opening["chests"]
	var legacy: Dictionary=chests.filter(func(chest: Dictionary) -> bool: return chest.has("serial"))[0]
	var position: Array=legacy["core"]["position"]
	var center := Vector2(position[0],position[1])
	var definition: Dictionary=opening["definition"].duplicate(false)
	var area := {}
	for source: Dictionary in definition["storm_chest_areas"]:
		if source["max_spawn"]>0 and center.distance_to(Vector2(source["x"],source["z"]))<float(source["radius"]):
			area=source.duplicate(true)
			break
	check(not area.is_empty(),"The source chest must belong to a refill area")
	if area.is_empty(): return
	area["max_total"]=1
	area["force"]=true
	definition["storm_chest_areas"]=[area]
	opening["definition"]=definition
	opening["chests"]=chests.filter(func(chest: Dictionary) -> bool: return not chest.has("serial") or chest["serial"]==legacy["serial"])
	var adapter := Chests.new()
	adapter.configure(world,state,[])
	adapter.random=RandomNumberGenerator.new()
	adapter.random.seed=525
	var serial: int=opening["storm"]["serial"]
	for interval in range(8): adapter.replenish(opening)
	check(opening["storm"]["serial"]==serial,"A reachable chest must keep its slot while it remains unopened")
	var sea_level := int(definition["chest_factory_rules"]["sea_level"])
	position[2]=Terrain.surface_height(sea_level-1)
	legacy["core"]["base_height"]=position[2]
	for interval in range(8): adapter.replenish(opening)
	check(opening["storm"]["serial"]==serial,"A shallow submerged chest must still keep its refill slot")
	# Reproduce a stranded storm chest from an older save.
	position[2]=Terrain.surface_height(sea_level+int(world.sculpt_minimum_layer())-1)
	legacy["core"]["base_height"]=position[2]
	for interval in range(16):
		adapter.replenish(opening)
		if opening["storm"]["serial"]>serial: break
	check(opening["storm"]["serial"]==serial+1 and legacy in opening["chests"],"A chest below the editable floor must free the refill slot while retaining its saved position")
