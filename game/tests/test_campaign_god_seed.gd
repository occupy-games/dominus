extends SceneTree

const World = preload("res://simulation/world.gd")
const GodSeed = preload("res://simulation/campaign_god_seed.gd")
const Stats = preload("res://simulation/building_stats.gd")
const Economy = preload("res://simulation/campaign_economy.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var forest: Dictionary=content.get("story",{}).get("god_seed",{})
	check(forest.get("population")==130 and forest.get("cost")==100 and forest.get("cost_increment")==0,
		"Holy Forest must use the original desktop population and Belief rows")
	if failures: quit(1); return
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=130
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	state["belief"]=500
	state["gems"]=30
	var p: Dictionary=state["progression"]
	p["script_unlocks"]={"Happiness":true}
	while state["followers"].size()<129: state["followers"].append(world._agent(160,123,false))
	world.step()
	var land := find_point(world,true)
	var water := find_point(world,false)
	var cast := {"type":"use_power","power":GodSeed.POWER,"x":land.x,"z":land.y}
	check(land.x>=0 and water.x>=0,"Original active coast must supply dry and submerged test positions")
	check(not GodSeed.CARD in p["discovered"] and not world.inspect(cast)["ok"],"Planting must stay locked below 130 followers")
	state["followers"].append(world._agent(160,123,false))
	world.step()
	check(GodSeed.CARD in p["discovered"] and not GodSeed.CARD in p["completed"] and GodSeed.POWER in p["powers"],
		"The original discovery must unlock the power before the card is claimed")
	if failures: quit(1); return
	var home := add_abode(world,state,Vector2i(land)+Vector2i(3,0))
	var before := Stats.belief_per_cycle(state,home)
	var claim := {"type":"claim_card","card":GodSeed.CARD}
	world.step([claim])
	check(opening["god_seed_step"]==1 and has_message(opening,5701),"Claiming the original card must show its source tip")
	world.step([{"type":"campaign_dismiss_level_card"}])
	world.step([{"type":"campaign_god_seed_select"}])
	check(opening["god_seed_step"]==2 and has_message(opening,5702),"Selecting the power must show the original planting prompt")
	var reject := cast.duplicate()
	reject.merge({"x":water.x,"z":water.y},true)
	var rng_state := random.state
	check(not world.inspect(reject)["ok"],"Sea level must reject Holy Forest placement")
	reject.merge({"x":home["x"],"z":home["z"]},true)
	check(not world.inspect(reject)["ok"],"An occupied cell must reject Holy Forest placement")
	reject.merge({"x":500,"z":500},true)
	check(not world.inspect(reject)["ok"] and rng_state==random.state,"Placement previews must leave RNG untouched")
	var initial_trees := world.shared_trees()
	var mood: float=p["happiness"]["player"]
	var belief: int=state["belief"]
	var events := world.step([cast])
	var tree: Dictionary=state["trees"][-1]
	check(state["belief"]==belief-100 and world.tree_at(int(land.x),int(land.y)),"One cast must pay 100 Belief and register occupancy")
	check(tree.get("planted_tick")==state["tick"] and tree["x"]==land.x and tree["z"]==land.y and tree["model_id"] in forest["models"],
		"The saved plant must use a real Holy Forest model and the fractional cast position")
	check(not world.inspect(cast)["ok"] and initial_trees.is_read_only() and world.shared_trees().size()==initial_trees.size()+1,
		"Repeat casting must reject while the earlier detached forest retains its layout")
	check(is_same(world.shared_trees(),world.query_copy().shared_trees()),"Detached queries must share immutable planting descriptors")
	check(not has_message(opening,5702) and opening["god_seed_step"]==3,"Planting must dismiss the source tutorial")
	check(events.any(func(event: Dictionary) -> bool: return event.get("event")==forest["sound"]),"An accepted cast must emit the original sound event")
	check(float(p["happiness"]["player"])>mood+0.019,"Planting in the abode radius must credit the original player happiness")
	check(home.get("nearby_seed_trees")==1 and is_equal_approx(Stats.belief_per_cycle(state,home),before+0.08),
		"The abode must gain the original 2 percent modifier from the Holy Forest tree")
	check_upgrades(world,state)
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"The planted tree and upgrades must survive save restoration")
	if failures: quit(1); return
	var tap := {"type":"tap_tree","cell":tree["cell"]}
	world.step([tap])
	restored.step([tap])
	check(world.export_state()==restored.export_state() and home.get("nearby_seed_trees")==0,
		"Removing the tree after load must remove its bonus and preserve continuation")
	check(world.inspect(cast)["ok"],"A cleared Holy Forest cell must accept another tree")
	world.step([cast])
	check(world.shared_trees().size()==initial_trees.size()+1 and home.get("nearby_seed_trees")==1,
		"Replanting must reuse the cleared slot and restore its bonus")
	print("Homeworld6 Holy Forest placement, upgrades and persistence: ",failures," failures")
	quit(1 if failures else 0)


func has_message(opening: Dictionary, id: int) -> bool:
	return opening["messages"].any(func(entry: Dictionary) -> bool: return entry["id"]==id)


func find_point(world: RefCounted, dry: bool) -> Vector2:
	for z in range(101,135):
		for x in range(149,177):
			var point := Vector2(x+0.25,z+0.25)
			var raw: int=world.source_raw_height_at(point.x,point.y)
			if (raw>=20)!=dry or not world.can_act_at(point.x,point.y): continue
			if world.source_seed_slot_available(x,z): return point
	return -Vector2.ONE


func add_abode(world: RefCounted, state: Dictionary, at: Vector2i) -> Dictionary:
	var home := {"id":state["next_id"],"source_house":"AbodeType_0_Rank_1","source_index":0,
		"x":at.x,"z":at.y,"anchor_x":at.x,"anchor_z":at.y,"vision_radius":8.0,
		"span":2,"belief_modifier":4.0,"belief_multiplier":1.0,"capacity":2,"breeder_count":1,"residents":1,
		"birth_ticks":100000,"build_ticks":1,"progress":1,"stored":0,"builder":-1,
		"work_x":at.x,"work_z":at.y,"stalled":false,"access_path":[]}
	state["next_id"]+=1
	state["homes"].append(home)
	world._spatial_revision+=1
	return home


func check_upgrades(world: RefCounted, state: Dictionary) -> void:
	var p: Dictionary=state["progression"]
	var farm := {"kind":"farm","rank":1,"harvest_rate":100.0,"nearby_seed_trees":1}
	var mine := {"kind":"mine","rank":1,"harvest_rate":100.0,"nearby_seed_trees":1}
	check(Economy.harvest_rate(state,farm)==100.0 and Economy.harvest_rate(state,mine)==100.0,
		"Planted trees must leave farms and mines unchanged until their upgrades")
	var purchase := {"type":"campaign_god_seed_upgrade","id":"LvlUp_GodPower_GodSeed_2"}
	world.step([purchase])
	check(state["gems"]==10 and Unlocks.enabled(p,"Upgrade_GodPower_GodSeed_2") and not world.inspect(purchase)["ok"],
		"Boost Mines must cost 20 gems once and be available independently")
	check(is_equal_approx(Economy.harvest_rate(state,mine),102.0) and Economy.harvest_rate(state,farm)==100.0,
		"Boost Mines must apply the source tree modifier to mines")
	world.step([{"type":"campaign_god_seed_upgrade","id":"LvlUp_GodPower_GodSeed_1"}])
	check(state["gems"]==0 and is_equal_approx(Economy.harvest_rate(state,farm),102.0),
		"Boost Fields must cost 10 gems and apply the source tree modifier to fields")
