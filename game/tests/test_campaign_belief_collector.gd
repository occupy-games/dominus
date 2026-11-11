extends SceneTree

const World = preload("res://simulation/world.gd")
const Collector = preload("res://simulation/campaign_belief_collector.gd")
const Rocks = preload("res://simulation/authored_rocks.gd")
const Temples = preload("res://simulation/temple_rules.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func grow_to(world: RefCounted,population: int) -> void:
	var state: Dictionary=world._state
	while state["followers"].size()<population: state["followers"].append(world._agent(157,123,false))
	world.step()


func complete_with_matching_stickers(world: RefCounted,id: String) -> void:
	var p: Dictionary=world._state["progression"]
	var card: Dictionary=p["rules"]["research_cards"][id]
	for sticker: String in p["rules"]["stickers"]:
		var record: Dictionary=p["rules"]["stickers"][sticker]
		var value:=int(record["contributions"].get(card["research_type"],0))
		if record.get("internal",false) or value<=0: continue
		var count:=ceili(float(card["research_needed"])/value)
		p["inventory"][sticker]=count
		for index in range(count): world.step([{"type":"research_card","card":id,"sticker":sticker}])
		break
	check(id in p["completed"],"The source advance must complete with matching typed stickers")


func next_pulse(world: RefCounted) -> void:
	var tick: int=world._state["tick"]
	for index in range(10-tick%10): world.step()


func run() -> void:
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	p["script_unlocks"]={"GenerateBelief":false,"TreeRockBelief":true}
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(p,site["id"])
	for tick in range(24): world._advance_source_influence([])
	check_rocks(world)
	if failures==0: check_collector(world)
	print("Source Homeworld6 belief advances: ",failures," failures")
	quit(1 if failures else 0)


func check_rocks(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var rules: Dictionary=state["opening"]["definition"]["rock_belief"]
	grow_to(world,74)
	check(not rules["card"] in p["discovered"],"Rock Belief must stay hidden at 74 followers")
	grow_to(world,75)
	check(rules["card"] in p["discovered"],"The source Rock Belief card must be revealed at 75 followers")
	var commands:=[]
	for rock: Dictionary in Rocks.entries(state):
		var command:={"type":"tap_object","cell":Rocks.cell(state,rock)}
		if world.inspect(command)["ok"]: commands.append(command)
		if commands.size()==2: break
	check(commands.size()==2,"The active original map must contain two targetable rocks")
	if failures>0: return
	for index in range(commands.size()):
		var command: Dictionary=commands[index]
		if index==1: complete_with_matching_stickers(world,rules["card"])
		var rock:=Rocks.at(state,command["cell"])
		var base: int=rules["amounts"][str(int(rock["type"]))]
		var before: int=state["belief"]
		world.step([command,command])
		check(state["belief"]-before==base*(1 if index==0 else 10),"A real source rock must award its current belief once")


func check_collector(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	grow_to(world,94)
	check(not Collector.CARD in p["discovered"],"The shrine advance must stay hidden at 94 followers")
	grow_to(world,95)
	check(Collector.CARD in p["discovered"] and not Collector.POWER in p["powers"],"Discovery alone must not grant the monument")
	complete_with_matching_stickers(world,Collector.CARD)
	check(Collector.POWER in p["powers"],"Completing Social research must unlock the monument")
	var point:=Vector2i.ZERO
	for z in range(116,139):
		for x in range(152,168):
			if world.source_clear_footprint(Rect2i(x,z,1,1)): point=Vector2i(x,z); break
		if point!=Vector2i.ZERO: break
	check(point!=Vector2i.ZERO,"Expected a clear shrine footprint on the real map")
	if failures>0: return
	var homes:=[]
	for delta: int in [3,4,5,12]:
		var home:={"id":state["next_id"],"x":point.x+delta,"z":point.y,"span":1,"build_ticks":1,"progress":1,
			"residents":0,"stored":10,"min_belief":1,"max_belief":20,"builder":-1,"work_x":point.x+delta,"work_z":point.y+1,"stalled":false}
		state["next_id"]+=1
		state["homes"].append(home)
		homes.append(home)
	homes[2]["settlement_id"]=1000000
	world._spatial_revision+=1
	var cast:={"type":"use_power","power":Collector.POWER,"x":point.x,"z":point.y}
	state["belief"]=999
	check(not world.inspect(cast)["ok"],"The first shrine needs 1,000 belief")
	state["belief"]=1000
	if (int(state["tick"])+1)%10==0: world.step()
	world.step([cast,cast])
	check(state["props"].size()==1 and state["belief"]==0 and world._occupied(point.x,point.y),"Placement must charge once and reserve the footprint")
	var id: int=state["props"][0]["id"]
	check(world.inspect_building(id,Collector.KIND)["radius"]==10,"The original type row gives an effect radius of ten")
	next_pulse(world)
	check(state["belief"]==10 and homes[0]["stored"]==0 and homes[1]["stored"]==10,"The first pulse must collect from one ready abode")
	next_pulse(world)
	check(state["belief"]==20 and homes[1]["stored"]==0 and homes[2]["stored"]==10 and homes[3]["stored"]==10,"Settled and out-of-radius dwellings must retain their belief")
	next_pulse(world)
	homes[0]["stored"]=10
	next_pulse(world)
	var since: int=state["props"][0]["ready_since"]
	while int(state["tick"])<since+299: world.step()
	check(state["belief"]==20,"After the ready homes run out the next collection must wait thirty seconds")
	world.step()
	check(state["belief"]==30,"The shrine must resume on the source wait deadline")
	var rules:=Collector.rules_for(state)
	var upgrade:={"type":"campaign_belief_collector_upgrade","id":rules["upgrades"][0]["id"]}
	state["gems"]=10
	world.step([upgrade,upgrade])
	check(state["gems"]==0 and Collector.status(state)["radius"]==15,"The first upgrade must apply its radius and charge ten gems once")
	next_pulse(world)
	check(state["belief"]==41 and homes[3]["stored"]==0,"The upgraded shrine must collect the more distant abode with its 10% boost")
	upgrade["id"]=rules["upgrades"][1]["id"]
	state["gems"]=20
	world.step([upgrade])
	check(state["gems"]==0 and Collector.status(state)["radius"]==20 and Collector.status(state)["multiplier"]==1.2,"The final upgrade must apply its original radius and amount")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and restored.inspect_building(id,Collector.KIND)["radius"]==20,"The monument and its upgrades must survive reload")
