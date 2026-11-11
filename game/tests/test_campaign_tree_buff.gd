extends SceneTree

const World = preload("res://simulation/world.gd")
const Stats = preload("res://simulation/building_stats.gd")
const Research = preload("res://simulation/research.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed=290
	var content := preload("res://infrastructure/campaign_opening_content.gd").definition()
	world.initialize({"campaign_data":content},rng)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var tree: Dictionary={}
	for row: Dictionary in state["trees"]:
		if row["x"]>10 and row["z"]>10 and row["x"]<1000 and row["z"]<1000 and world.tree_at(int(row["x"]),int(row["z"])):
			tree=row
			break
	check(not tree.is_empty(),"The original map must have a live tree")
	if failures: quit(1); return
	preload("res://simulation/source_influence.gd").circle(state["source_influence"]["raster"],
		{"id":"9223372036854775807","x":tree["x"],"z":tree["z"],"radius":8.0},opening["definition"]["influence_rules"])
	# Place a completed test abode near the original tree. No authored tree,
	# research recipe, influence, or environment multiplier is substituted.
	var center := Vector2(tree["x"],tree["z"])+Vector2(2,0)
	var home := {"id":state["next_id"],"source_house":"AbodeType_0_Rank_1","source_index":0,
		"x":roundi(center.x),"z":roundi(center.y),"anchor_x":center.x,"anchor_z":center.y,"vision_radius":4.0,
		"span":2,"belief_modifier":4.0,"belief_multiplier":1.0,"capacity":2,"breeder_count":1,"residents":1,
		"birth_ticks":100000,"build_ticks":1,"progress":1,"stored":0,"builder":-1,
		"work_x":roundi(center.x),"work_z":roundi(center.y),"stalled":false}
	state["next_id"]+=1
	state["homes"].append(home)
	var base := Stats.belief_per_cycle(state,home)
	check_milestone(world,state,290,"Card_TreeBuff_1","TreeBuff_1")
	var trees := int(home.get("nearby_trees",0))
	var first := Stats.belief_per_cycle(state,home)
	check(trees>0 and is_equal_approx(first,1.0+4.0*minf(2.0,pow(1.01,trees))) and first>base,"Trees Buff Belief must multiply the abode modifier using its live tree count")
	if failures: quit(1); return
	var tap := {"type":"tap_tree","cell":tree["cell"]}
	for attempt in range(8):
		if not world.inspect(tap)["ok"]: break
		world.step([tap])
	check(home["nearby_trees"]==trees-1 and Stats.belief_per_cycle(state,home)<first,"Clearing a tree must remove its contribution")
	check_milestone(world,state,5000,"Card_TreeBuff_2","TreeBuff_2")
	var count := int(home["nearby_trees"])
	var expected := 1.0+4.0*minf(2.0,pow(1.01,count))*minf(4.0,pow(1.05,count))
	check(is_equal_approx(Stats.belief_per_cycle(state,home),expected),"The second source advance must stack with the first")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Save and load must retain the completed advances and abode samples")
	if not failures:
		restored.prepare_loaded_opening()
		check(is_equal_approx(Stats.belief_per_cycle(restored._state,restored._state["homes"][0]),expected),"Restored production must use the same live tree count")
	print("Homeworld6 tree belief advances: ",failures," failures")
	quit(1 if failures else 0)


func check_milestone(world: RefCounted,state: Dictionary,population: int,card: String,unlock: String) -> void:
	var progression: Dictionary=state["progression"]
	while state["followers"].size()<population-1: state["followers"].append(world._agent(160,123,false))
	world.step()
	check(not card in progression["discovered"],"Advance must stay hidden below its source milestone")
	state["followers"].append(world._agent(160,123,false))
	world.step()
	check(card in progression["discovered"] and not Unlocks.enabled(progression,unlock),"Discovery must precede the research effect")
	if failures: return
	var recipe: Dictionary=progression["rules"]["research_cards"][card]
	for sticker: String in progression["rules"]["stickers"]:
		var points: int=progression["rules"]["stickers"][sticker]["contributions"].get(recipe["research_type"],0)
		if points<=0: continue
		var count := ceili(float(recipe["research_needed"])/points)
		progression["inventory"][sticker]=count
		for i in range(count):
			var command := {"type":"research_card","card":card,"sticker":sticker}
			check(world.inspect(command)["ok"],"The original typed sticker must be accepted")
			if failures: return
			world.step([command])
		break
	check(Unlocks.enabled(progression,unlock) and Research.points(progression,card)==recipe["research_needed"],"Completing typed research must enable the original tree bonus")
