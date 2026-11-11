extends SceneTree

const World = preload("res://simulation/world.gd")
const Capacity = preload("res://simulation/campaign_capacity_shrine.gd")
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
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var rules: Dictionary=content.get("story",{}).get(Capacity.KIND,{})
	var prices: Array=rules.get("prices",[]).map(func(value: Variant) -> int: return int(value))
	check(rules.get("population")==360 and rules.get("model")=="shrine.group.bin:dff1563f" and prices==[200,1000,2000,3000,5000],
		"Load the original milestone, assembly and placement prices, got %s"%[rules])
	if failures: finish(); return
	var random:=RandomNumberGenerator.new()
	random.seed=360
	world.initialize({"campaign_data":content},random)
	state=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var p: Dictionary=state["progression"]
	p["script_unlocks"]={"Expansion_1":true}
	state["belief"]=2000
	for tick in range(60): world._advance_source_influence([])
	while state["followers"].size()<359: state["followers"].append(world._agent(175,165,false))
	world.step()
	check(not Capacity.CARD in p["discovered"],"Keep the advance hidden below 360 followers")
	state["followers"].append(world._agent(175,165,false))
	var events:=world.step()
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="card_discovered" and event.get("card")==Capacity.CARD),
		"Discover the source card and notify its gallery at 360 followers")
	check(not Capacity.POWER in p["powers"] and not world.inspect({"type":"claim_card","card":Capacity.CARD})["ok"],
		"Keep the shrine unavailable until its Social research is complete")
	if failures: finish(); return
	world.step([{"type":"campaign_capacity_card_closed"}])
	var definition: Dictionary=p["rules"]["research_cards"][Capacity.CARD]
	check(definition["research_type"]=="SOCIAL" and definition["research_needed"]==7,"Use the seven-point Social recipe")
	var match_id := "Sticker_Textile_1"
	var mismatch_id := "Sticker_Tools_1"
	p["inventory"][mismatch_id]=1
	check(not world.inspect({"type":"research_card","card":Capacity.CARD,"sticker":mismatch_id})["ok"],"Reject a non-Social sticker")
	var research:={"type":"research_card","card":Capacity.CARD,"sticker":match_id}
	for index in range(7):
		if Capacity.CARD in p["completed"]: break
		p["inventory"][match_id]=1
		check(world.inspect(research)["ok"],"Accept original Social sticker %s"%match_id)
		world.step([research])
	world.step([{"type":"campaign_capacity_card_closed"}])
	check(Capacity.POWER in p["powers"] and opening.get("capacity_step")==3 and p["inventory"].get(match_id)==0,
		"Spend compatible stickers, unlock the power and advance the prompt. Research %s, powers %s, step %s"%[p.get("research",{}),p["powers"],opening.get("capacity_step")])
	if failures: finish(); return
	var point:=find_placement()
	check(point.x>=0,"Find a clear dry tile in the player's influence")
	if failures: finish(); return
	var near:=house(point+Vector2i(3,0),0)
	var far:=house(point+Vector2i(16,0),2)
	var placement:=cast_at(point)
	check(world.inspect(placement).get("cost")==200,"Quote the first original placement price")
	world.step([placement,placement])
	check(state["props"].size()==1 and state["belief"]==1800 and world._occupied(point.x,point.y),
		"Place once, debit belief once and protect the footprint")
	check(world.inspect_building(near["id"])["capacity"]==3 and near["residents"]==3 and far["residents"]==2,
		"Only a nearby home gains a third occupant through normal birth")
	check(world.inspect_building(state["props"][0]["id"],Capacity.KIND).get("site_type")=="Monument_Family",
		"Expose the original shrine information record")
	var overlap:=cast_at(point+Vector2i(0,1))
	check(world.inspect(overlap).get("cost")==1000,"The second placement uses the next original price")
	world.step([overlap])
	check(state["props"].size()==2 and world.inspect_building(near["id"])["capacity"]==3,
		"Overlapping shrines share the same capacity modifier")
	var workers:={"type":Capacity.UPGRADE,"id":"LvlUp_Shrine_Capacity_3"}
	var radius:={"type":Capacity.UPGRADE,"id":"LvlUp_Shrine_Capacity_2"}
	state["gems"]=0
	state["wheat"]=0
	check(not world.inspect(workers)["ok"] and not world.inspect(radius)["ok"],"Both upgrades require their original currencies")
	state["gems"]=100
	world.step([workers,workers])
	check(state["gems"]==0 and world.inspect_building(near["id"])["capacity"]==4 and world.inspect_building(far["id"])["capacity"]==2,
		"The gem upgrade adds two places within the current radius and charges once")
	state["wheat"]=100
	world.step([radius,radius])
	check(state["wheat"]==0 and world.inspect_building(far["id"])["capacity"]==4 and far["residents"]==3,
		"The wheat upgrade doubles radius and opens occupancy in a distant home")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Restore the placed shrines and upgrade flags")
	if failures: finish(); return
	check(restored.inspect_building(near["id"])["capacity"]==4 and restored.inspect_building(far["id"])["capacity"]==4,
		"Restored homes use the same derived capacity")
	check(restored.snapshot(false)["opening"]["capacity_status"]["price"]==2000,"Reload preserves the placement price tier")
	finish()


func find_placement() -> Vector2i:
	for z in range(124,155):
		for x in range(145,179):
			if not world.source_clear_footprint(Rect2i(x,z,1,2)): continue
			if world.height_at(x+3,z)>0 and world.height_at(x+16,z)>0: return Vector2i(x,z)
	return Vector2i(-1,-1)


func house(point: Vector2i,first: int) -> Dictionary:
	var home:={"id":state["next_id"],"x":point.x,"z":point.y,"span":2,"work_x":point.x+2,"work_z":point.y,
		"progress":1,"build_ticks":1,"capacity":2,"residents":2,"stored":0,"builder":-1,"stalled":false,"birth_ticks":1}
	state["next_id"]+=1
	state["homes"].append(home)
	world._spatial_revision+=1
	for index in range(first,first+2):
		state["followers"][index].merge({"state":"indoors","indoors_home":home["id"],"x":float(home["work_x"]),"z":float(home["work_z"])},true)
	return home


func cast_at(point: Vector2i) -> Dictionary:
	return {"type":"use_power","power":Capacity.POWER,"x":point.x,"z":point.y}


func finish() -> void:
	print("Homeworld6 Shrine of Capacity: ",failures," failures")
	quit(1 if failures else 0)
