extends SceneTree

const World = preload("res://simulation/world.gd")
const Upgrades = preload("res://simulation/campaign_settlement_upgrades.gd")
const MINING := "GodPower_PlaceSettlement_3"

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var source: Dictionary=content.get("story",{}).get(Upgrades.KEY,{})
	check(Upgrades.valid_rules(source),"Recover all three source settlement upgrade sequences")
	if failures: finish(); return
	for power: String in source:
		var rules: Dictionary=source[power]
		check(rules["radius"]==10 and rules["population"]==50 and rules["workers"]==5,
			"Load the original starting limits for "+power)
		check(rules["upgrades"][2]["currency"]=="wheat" and rules["upgrades"][2]["cost"]==150 and
			rules["upgrades"][3]["currency"]=="ore" and rules["upgrades"][3]["cost"]==150,
			"Keep the source wheat and ore costs for "+power)
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=550
	world.initialize({"campaign_data":content},random)
	var state:=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var progression: Dictionary=state["progression"]
	progression["script_unlocks"]={"Expansion_1":true}
	for tick in range(60): world._advance_source_influence([])
	var offers: Array=source[MINING]["upgrades"]
	var first:=purchase(offers[0])
	state["gems"]=20
	check(not world.inspect(first)["ok"],"A locked settlement cannot be upgraded")
	progression["powers"].append(MINING)
	state["gems"]=19
	check(not world.inspect(first)["ok"],"The Mining Settlement upgrade costs 20 gems")
	state["gems"]=20
	state["belief"]=7500
	state["wheat"]=150
	check(not world.inspect(purchase(offers[2]))["ok"],"Require earlier levels before buying the wheat upgrade")
	var center:=test_center(world)
	check(center.x>=0,"Find two dry abode sites in the original influence area")
	if failures: finish(); return
	var near:=abode(state,center)
	var far:=abode(state,center+Vector2i(11,0))
	world._spatial_revision+=1
	var preview:={"type":"campaign_mining_preview","x":center.x,"z":center.y}
	check(world.inspect(preview).get("members",[])==[near],"A fresh Mining Settlement only compresses the nearer abode")
	var job_state:={"opening":opening,"progression":progression,"followers":[]}
	var core:={"id":100,"settlement_id":101}
	progression["settlements"].append({"id":101,"role":"miner"})
	for index in range(5): job_state["followers"].append({"away_home":100,"state":"mining"})
	check(not Upgrades.can_release(job_state,core),"A full rank-one mining crew uses all five worker slots")
	progression["settlements"].pop_back()
	world.step([first,first])
	check(state["gems"]==0 and not world.inspect(first)["ok"],"Apply and debit each level once")
	var upgraded:=Upgrades.parameters(state,MINING)
	check(upgraded=={"radius":12,"population":80,"workers":8},"The first upgrade changes all three source limits, got %s"%[upgraded])
	check(world.inspect(preview).get("members",[])==[near,far],"The upgraded radius compresses both actual abodes")
	progression["settlements"].append({"id":101,"role":"miner"})
	check(Upgrades.can_release(job_state,core),"Existing settlements can release additional workers after the upgrade")
	progression["settlements"].pop_back()
	state["gems"]=40
	state["ore"]=150
	world.step([purchase(offers[1]),purchase(offers[2]),purchase(offers[3])])
	var top: Dictionary=world.snapshot(false)["opening"]["settlement_status"][MINING]
	var wallet: Array=[state["gems"],state["wheat"],state["ore"]]
	check(top=={"radius":22,"population":5000,"workers":500} and wallet==[0,0,0],
		"All four original levels accumulate their effects and charge their own currency. Limits %s, wallet %s"%[top,wallet])
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and Upgrades.parameters(restored._state,MINING)==top,
		"Restore all purchased levels and compression limits")
	finish()


func purchase(offer: Dictionary) -> Dictionary:
	return {"type":Upgrades.COMMAND,"id":offer["id"]}


func test_center(world: RefCounted) -> Vector2i:
	for z in range(120,150):
		for x in range(146,169):
			if world.source_clear_footprint(Rect2i(x,z,2,1)) and world.source_clear_footprint(Rect2i(x+11,z,2,1)):
				return Vector2i(x,z)
	return Vector2i(-1,-1)


func abode(state: Dictionary,point: Vector2i) -> int:
	var id: int=state["next_id"]
	state["next_id"]+=1
	state["homes"].append({"id":id,"x":point.x,"z":point.y,"anchor_x":point.x,"anchor_z":point.y,"span":1,
		"progress":1,"build_ticks":1,"capacity":2,"residents":0,"stored":0,"builder":-1,"stalled":false,
		"work_x":point.x+1,"work_z":point.y,"birth_ticks":100000})
	return id


func finish() -> void:
	print("Homeworld6 settlement upgrades: ",failures," failures")
	quit(1 if failures else 0)
