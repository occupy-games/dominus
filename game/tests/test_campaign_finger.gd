extends SceneTree

const World = preload("res://simulation/world.gd")
const Finger = preload("res://simulation/campaign_finger.gd")
const Content = preload("res://infrastructure/campaign_opening_content.gd")
const Rocks = preload("res://simulation/authored_rocks.gd")
var failures := 0
var world := World.new()
var state: Dictionary


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content := Content.definition()
	var rules: Dictionary=content.get("story",{}).get("finger_of_god",{})
	check(rules.get("population")==325 and rules.get("duration")==10 and rules.get("activation_cost")==0,
		"Homeworld6 must load the source milestone and native activation rules")
	if failures: finish(); return
	var rng := RandomNumberGenerator.new()
	rng.seed=325
	world.initialize({"campaign_data":content},rng)
	state=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var progression: Dictionary=state["progression"]
	progression["script_unlocks"]={"Happiness":true}
	while state["followers"].size()<324: state["followers"].append(world._agent(175,165,false))
	var arm := {"type":Finger.ARM}
	state["belief"]=6000
	world.step()
	check(not world.inspect(arm)["ok"] and not Finger.CARD in progression["discovered"],"The power must remain locked below 325 followers")
	state["followers"].append(world._agent(175,165,false))
	var discovery := world.step()
	check(Finger.CARD in progression["discovered"] and Finger.POWER in progression["powers"] and has_event(discovery,"card_discovered",Finger.CARD),
		"The 325th follower must surface the source advance and enable its miracle")
	var claim := {"type":"claim_card","card":Finger.CARD}
	check(world.inspect(claim)["ok"],"The original Faith advance needs zero stickers")
	if failures: finish(); return
	world.step([claim,{"type":"campaign_finger_menu","show":true}])
	check(Finger.CARD in progression["completed"] and opening["messages"].any(func(message: Dictionary) -> bool: return message["id"]==5901),
		"The claimed advance must expose the original power menu tip")
	state["belief"]=99
	check(not world.inspect(arm)["ok"],"The cheapest original target sets the arming threshold")
	state["belief"]=6000
	var origin := isolated_ground()
	check(origin.x>=0,"The source influence area must contain an isolated dry test point")
	if failures: finish(); return
	var home := add_home(origin,false)
	var tenant: Dictionary=state["followers"][0]
	tenant.merge({"state":"indoors","indoors_home":home["id"],"x":float(origin.x),"z":float(origin.y)},true)
	home["residents"]=1
	var press := press_at(Vector2(origin))
	check(not world.inspect(press)["ok"],"A stroke must require explicit arming")
	world.step([arm])
	check(state["belief"]==6000 and world.snapshot(false)["opening"]["finger_status"]["remaining_ticks"]==99,
		"Arming must start the ten-second clock without a debit")
	check(not world.inspect(press_at(Vector2(900,900)))["ok"],"Strokes must respect the map's active area")
	var mood: float=progression["happiness"]["player"]
	var hit := world.step([press,press,{"type":Finger.RELEASE}])
	check(not state["homes"].has(home) and not world._occupied(origin.x,origin.y) and state["belief"]==5900,
		"One accepted stroke must remove the abode and release its plot with one debit")
	check(tenant["state"]=="idle" and not tenant.has("indoors_home") and is_equal_approx(progression["happiness"]["player"],mood-0.02),
		"Destroying the occupied abode must clear the housing reference and apply its source happiness change")
	check(hit.any(func(event: Dictionary) -> bool: return event.get("event")==rules["sound"]),"A successful strike must request the original bank event")
	check(opening["persistent"].get("BeliefFingerProgress")==1337,"The first paid hit must complete the original power tutorial")
	check(not world.inspect(press)["ok"],"A new strike must wait for the finger to lift")
	world.step()
	var exposed := world._agent(origin.x,origin.y,false)
	state["followers"].append(exposed)
	# Move the evicted tenant away before the isolated follower test.
	tenant["x"]=175.0
	tenant["z"]=165.0
	stroke(Vector2(origin))
	check(not state["followers"].has(exposed) and state["belief"]==5800,"Tapping an exposed follower must debit its own price")
	var settlement := add_home(origin,true)
	stroke(Vector2(origin))
	check(state["homes"].has(settlement) and state["belief"]==4800,"A settlement must survive its first paid tap")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"The active power and settlement tap must restore")
	if failures: finish(); return
	for iteration in range(2):
		var commands := [press,{"type":Finger.RELEASE}]
		world.step(commands)
		restored.step(commands)
		world.step()
		restored.step()
		if iteration==0: check(state["homes"].has(settlement),"A settlement must survive the second paid tap")
	check(not state["homes"].has(settlement) and state["belief"]==2800 and restored.export_state()==world.export_state(),
		"The third tap must destroy the settlement and produce identical saved continuation")
	while opening.has("finger_cast"): world.step()
	check(not world.inspect(press)["ok"] and not opening["messages"].any(func(message: Dictionary) -> bool: return message["id"]==5902),
		"The power and active tooltip must expire without another click")
	check_scenery(arm)
	finish()


func check_scenery(arm: Dictionary) -> void:
	var point := Vector2(-1,-1)
	var cell := -1
	for tree: Dictionary in state["trees"]:
		if not world.can_act_at(tree["x"],tree["z"]) or not world.tree_at(int(tree["x"]),int(tree["z"])): continue
		var index: int=tree["cell"]
		if not Rocks.at(state,index).is_empty(): continue
		cell=index
		point=Vector2(tree["x"],tree["z"])
		break
	check(cell>=0,"The source map must supply a targetable tree")
	if cell<0: return
	world.step([arm])
	var events := stroke(point)
	check(state["opening"].get("finger_fires",{}).has(str(cell)) and not state["removed_trees"].has(str(cell)) and has_event(events,"campaign_finger_ignited"),
		"A tree contact must start a persistent fire before removing the tree")
	var due: int=state["opening"]["finger_fires"].get(str(cell),state["tick"])
	while state["tick"]<due: world.step()
	check(state["opening"]["finger_burned"].has(str(cell)) and world.tree_at(cell%1024,cell/1024),
		"The original burn must retain the scorched tree record")
	var belief: int=state["belief"]
	world.step([arm])
	stroke(point)
	check(state["belief"]==belief,"A fully charred tree must not burn a second time")
	for rock: Dictionary in Rocks.entries(state):
		point=Vector2(rock["x"],rock["z"])
		cell=Rocks.cell(state,rock)
		if not world.can_act_at(point.x,point.y) or not Rocks.alive(state,cell): continue
		var rock_events := stroke(point)
		check(not Rocks.alive(state,cell) and rock_events.any(func(event: Dictionary) -> bool: return event["type"]=="rock_removed" and event["cell"]==cell and event["belief"]==0),
			"A finger strike must break an authored boulder without a manual harvesting reward")
		return
	check(false,"The source map must supply a targetable boulder")


func add_home(point: Vector2i,core: bool) -> Dictionary:
	var home := {"id":state["next_id"],"x":point.x,"z":point.y,"span":2,"work_x":point.x-1,"work_z":point.y,
		"progress":30,"build_ticks":30,"capacity":6,"residents":0,"stored":0,"builder":-1,"stalled":false,"birth_ticks":6000}
	state["next_id"]+=1
	state["homes"].append(home)
	world._spatial_revision+=1
	if core:
		home["settlement_core"]=true
		home["settlement_id"]=state["next_id"]
		state["progression"]["settlements"].append({"id":state["next_id"],"role":"builder","x":point.x,"z":point.y,
			"radius":10.0,"members":[home["id"]],"capacity":6,"wheat":0,"ore":0})
		state["next_id"]+=1
	return home


func isolated_ground() -> Vector2i:
	for z in range(115,176):
		for x in range(140,185):
			if not world.can_act_at(x,z) or world.height_at(x,z)<=0 or Vector2(x,z).distance_to(Vector2(175,165))<4: continue
			var clear := true
			for dz in range(-2,3):
				for dx in range(-2,3):
					if world.plot_obstruction(x+dx,z+dz)!="": clear=false
			if clear: return Vector2i(x,z)
	return Vector2i(-1,-1)


func stroke(point: Vector2) -> Array:
	var events := world.step([press_at(point),{"type":Finger.RELEASE}])
	world.step()
	return events


func press_at(point: Vector2) -> Dictionary:
	return {"type":"use_power","power":Finger.POWER,"x":point.x,"z":point.y}


func has_event(events: Array,kind: String,card: String="") -> bool:
	return events.any(func(event: Dictionary) -> bool: return event["type"]==kind and (card.is_empty() or event.get("card")==card))


func finish() -> void:
	print("Homeworld6 Finger of God: ",failures," failures")
	quit(1 if failures else 0)
