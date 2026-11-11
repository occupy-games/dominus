extends SceneTree

const World = preload("res://simulation/world.gd")
const Speed = preload("res://simulation/campaign_speed_shrine.gd")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var rules: Dictionary=content.get("story",{}).get(Speed.KIND,{})
	check(rules.get("fields")==30 and rules.get("model")=="shrine.group.bin:dff1563f" and rules.get("authored_sites")==["1205","1206"],
		"Load the original field milestone, model and map sites")
	if failures: finish(); return
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=30
	world.initialize({"campaign_data":content},random)
	var state:=world._state
	var opening: Dictionary=state["opening"]
	var progression: Dictionary=state["progression"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	progression["script_unlocks"]={"Expansion_1":true}
	for tick in range(60): world._advance_source_influence([])
	var events: Array=[]
	Speed.discover(state,29,events)
	check(events.is_empty() and not Speed.CARD in progression["discovered"],"Keep the advance hidden through 29 player fields")
	Speed.discover(state,30,events)
	check(Speed.CARD in progression["discovered"] and not Speed.POWER in progression["powers"],
		"Discover Fitter Followers at 30 fields and require its research")
	var wrong:={"type":"research_card","card":Speed.CARD,"sticker":"Sticker_Tools_1"}
	var research:={"type":"research_card","card":Speed.CARD,"sticker":"Sticker_Textile_1"}
	progression["inventory"].merge({"Sticker_Tools_1":1,"Sticker_Textile_1":12},true)
	check(not world.inspect(wrong)["ok"],"Reject a sticker without Social points")
	for index in range(11): world.step([research])
	check(not Speed.POWER in progression["powers"],"Eleven Social points must leave the power locked")
	world.step([research])
	check(Speed.POWER in progression["powers"] and progression["inventory"]["Sticker_Textile_1"]==0,
		"The twelfth Social point completes research and unlocks the power")
	var map_shrine:=world.inspect_building("1205","temple")
	check(map_shrine.get("site_type")=="Monument_Speed" and map_shrine.get("complete")==true and map_shrine.get("radius")==10,
		"The authored Speed Shrine has its original stats")
	check(is_equal_approx(world.source_route_speed(1.0,Vector2(300,336)),2.0),"The authored Speed Shrine applies its stat effect")
	var point:=clear_pair(world)
	check(point.x>=0,"Find two dry adjacent cells within the action area")
	if failures: finish(); return
	var cast:={"type":"use_power","power":Speed.POWER,"x":point.x,"z":point.y}
	state["belief"]=999
	check(not world.inspect(cast)["ok"],"The first Speed Shrine needs 1,000 belief")
	state["belief"]=4000
	check(world.inspect(cast).get("cost")==1000,"Quote the first placement price")
	world.step([cast,cast])
	check(state["props"].size()==1 and state["belief"]==3000 and world._occupied(point.x,point.y),
		"An occupied footprint cannot be placed or charged twice")
	cast["x"]=point.x+1
	check(world.inspect(cast).get("cost")==2000,"Quote the second placement price")
	world.step([cast])
	var at:=Vector2(point)
	var beyond:=at+Vector2(16,0)
	var follower:={"x":at.x,"z":at.y,"path":[point.y*int(state["width"])+point.x-1]}
	var sheep:=follower.duplicate(true)
	world.advance_agent_path(follower,false,1.0)
	world.advance_agent_path(sheep,true,1.0)
	check(absf(float(follower["x"])-(at.x-0.2))<0.001 and absf(float(sheep["x"])-(at.x-0.1))<0.001,
		"Overlapping effects double follower movement once and leave sheep speed unchanged")
	check(is_equal_approx(world.source_route_speed(1.0,beyond),1.0),"Movement outside the shrine radius keeps its normal speed")
	var radius:={"type":Speed.UPGRADE,"id":"LvlUp_Shrine_Speed_2"}
	var faster:={"type":Speed.UPGRADE,"id":"LvlUp_Shrine_Speed_3"}
	state["wheat"]=0
	state["ore"]=0
	check(not world.inspect(radius)["ok"] and not world.inspect(faster)["ok"],"Both upgrades require the original currencies")
	state["wheat"]=100
	state["ore"]=100
	world.step([radius,radius,faster,faster])
	check(state["wheat"]==0 and state["ore"]==0 and not world.inspect(radius)["ok"] and not world.inspect(faster)["ok"],
		"Each upgrade spends its original currency once")
	check(is_equal_approx(world.source_route_speed(1.0,beyond),5.0),"Apply both native stat rows within the upgraded radius")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Restore placed Speed Shrines and their upgrade flags")
	if failures: finish(); return
	restored.step()
	check(is_equal_approx(restored.source_route_speed(1.0,beyond),5.0) and restored.snapshot(false)["opening"]["speed_shrine_status"]["price"]==3000,
		"Restored movement and the placement price use the saved upgrades and sites")
	finish()


func clear_pair(world: RefCounted) -> Vector2i:
	for z in range(124,155):
		for x in range(145,179):
			if world.source_clear_footprint(Rect2i(x,z,2,1)): return Vector2i(x,z)
	return Vector2i(-1,-1)


func finish() -> void:
	print("Homeworld6 Shrine of Speed: ",failures," failures")
	quit(1 if failures else 0)
