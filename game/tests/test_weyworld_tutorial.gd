extends SceneTree

const World = preload("res://simulation/world.gd")
const Weyworld = preload("res://simulation/weyworld.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=Content.map_definition("homeworld7")
	check(not content.is_empty(),"Weyworld must load its scoped tutorial data")
	if failures: quit(1); return
	content["automatic_settlement"]=false
	content["ark_passengers"]=[{"female":false,"race":"Brown Head"}]
	content["ark_research"]={"discovered":["Card_GodPower_TotemActivate"],"completed":["Card_GodPower_TotemActivate"]}
	var world:=World.new()
	world.initialize({"campaign_data":content},RandomNumberGenerator.new())
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var tutorial: Dictionary=state["weyworld"]
	var ark: Dictionary=state["homes"][0]
	var snapshot:=world.snapshot(false)
	var landing:=snapshot["weyworld"] as Dictionary
	check(landing["messages"][0]["id"]==5801 and landing["camera_degrees"]==-30 and landing["leash_homes"]==[ark["id"]],"The opening prompt and camera must target the original landed Ark")
	check(snapshot["currency_metrics"]["wheat"]["amount"]==0 and snapshot["currency_metrics"]["ore"]["amount"]==0,"Starting resources and authored free sites must not fill either production meter")
	check(not "Card_Adv_WheatCollection" in p["discovered"] and not "Card_Adv_OreCollection" in p["discovered"],"Starting stock must not discover advances for player-built sites")
	var passenger: Dictionary=state["followers"][0]
	var direct: Dictionary=world.inspect({"type":"weyworld_release_ark","id":ark["id"]})
	var shore: Vector2i=direct["target"]
	var leash: Dictionary={}
	for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var point:=shore+offset
		var candidate:={"type":"leash","home_id":ark["id"],"followers":[],"x":point.x,"z":point.y}
		if world.inspect(candidate).get("ok",false): leash=candidate; break
	check(not leash.is_empty(),"The real shore must allow a leash from the Ark")
	if failures: quit(1); return
	var old_belief: int=state["belief"]
	world.step([leash,leash])
	check(ark["residents"]==0 and state["belief"]==old_belief-int(Weyworld.rules(state)["leash"]["home_cost"]),"One valid hold gesture must debit once and release one passenger")
	check(not passenger.has("ark_passenger") and tutorial["phase"]==1 and not 5801 in tutorial["hints"],"The leash must advance the original opening step")
	var goal:=Vector2(leash["x"],leash["z"])
	for tick in range(120):
		if not passenger.has("weyworld_destination"): break
		world.step()
	check(not passenger.has("weyworld_destination") and Vector2(passenger["x"],passenger["z"]).distance_to(goal)<0.01,"The released passenger must walk to the dropped destination")
	var house: Dictionary={}
	var origin:=Vector2i(goal)
	for radius in range(1,12):
		for z in range(origin.y-radius,origin.y+radius+1):
			for x in range(origin.x-radius,origin.x+radius+1):
				var candidate:={"type":"home","x":x,"z":z,"rank":1}
				if world.inspect(candidate)["ok"]: house=candidate; break
			if not house.is_empty(): break
		if not house.is_empty(): break
	check(not house.is_empty(),"The landing must provide a legal nearby abode")
	if failures: quit(1); return
	world.step([house])
	check(tutorial["hints"]==[5802],"Starting a real home must show the authored abode explanation")
	for tick in range(400):
		if tutorial["phase"]==2: break
		world.step()
	check(tutorial["phase"]==2 and tutorial["hints"].is_empty(),"Finishing the first home must wait for access to Verdant Land")
	var first_beacon: Dictionary=world.source_shrine_site("2002")
	first_beacon["started"]=true
	preload("res://simulation/temple_rules.gd").complete(p,"2002")
	world.step()
	check(tutorial["hints"]==[5803],"The original beacon expansion must reveal the Verdant Land hint")
	world.step([{"type":"campaign_ack","id":5803}])
	check(tutorial["phase"]==3 and tutorial["hints"]==[5804],"Acknowledging Verdant Land must reveal Rugged Land and wait for the late landmarks")
	p["script_unlocks"]={"Expansion_5b":true}
	world.step()
	check(5806 in tutorial["hints"] and not 5805 in tutorial["hints"] and tutorial.get("queue_hallowed",false),"Simultaneous Granite and Hallowed access must show Granite first")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"The queued second hint must survive reload")
	if failures: quit(1); return
	restored.step([{"type":"campaign_ack","id":5806}])
	check(5805 in restored._state["weyworld"]["hints"],"Acknowledging Granite must reveal the queued Hallowed Ground explanation")
	check_biomes(state,p)
	print("Weyworld authored tutorial, leash and biomes: ",failures," failures")
	quit(1 if failures else 0)


func check_biomes(state: Dictionary,p: Dictionary) -> void:
	var rules:=Weyworld.rules(state)
	check(Weyworld.placement_reason(state,"farm",130,255).is_empty() and not Weyworld.placement_reason(state,"mine",130,255).is_empty(),"Verdant Land must accept fields and reject mines")
	check(Weyworld.placement_reason(state,"mine",116,290).is_empty() and not Weyworld.placement_reason(state,"farm",116,290).is_empty(),"Rugged Land must accept mines and reject fields")
	check(Weyworld.placement_reason(state,"home",168,175)==rules["biome_messages"]["home"],"Ordinary abodes must be barred from Hallowed Ground")
	check(Weyworld.house_spec(state,1,168,175).is_empty(),"The monastery must remain locked before its source advance")
	p["discovered"].append("Card_AbodeType1_Holy_1")
	p["completed"].append("Card_AbodeType1_Holy_1")
	var monastery:=Weyworld.house_spec(state,1,168,175)
	check(monastery.get("source_house")=="AbodeType_7_Rank_1" and monastery.get("model_id")=="weylowlandrural1.group.bin:dff1563f","The original holy advance must enable its assembled Monastery")
