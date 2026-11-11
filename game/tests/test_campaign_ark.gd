extends SceneTree

const World = preload("res://simulation/world.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var source:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(not source.is_empty(),"The original Ark data must load")
	if failures: quit(1); return
	var world:=World.new()
	world.initialize({"campaign_data":source},RandomNumberGenerator.new())
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"leash_step":2,"messages":[]},true)
	opening["leash_level_card"]=opening["definition"]["leash_population_card"]["id"]
	opening["globals"]["onStartPlayTriggered"]=true
	p["script_unlocks"]={"Leash":true,"OreSpending":true}
	var builder: Dictionary=state["followers"][0]
	builder.merge({"x":306.0,"z":317.0,"state":"idle","profession":"miner"},true)
	world.step()
	check(not opening.has("ark_progress"),"The village must stay locked before the authored approach beacon")
	p["script_unlocks"]["Expansion_7a"]=true
	for tick in range(60): world._advance_source_influence([])
	world.step()
	var progress: Dictionary=opening.get("ark_progress",{})
	check(not progress.is_empty() and not progress.has("festival_until"),"The source village scan must reject a Miner")
	check(not world.source_plot_eligible(327,310),"The powers-only village influence must not unlock the beacon")
	if failures: quit(1); return
	builder.erase("profession")
	state["belief"]=100
	var leash:={"type":"leash","followers":[builder["id"]],"x":307,"z":317}
	check(world.inspect(leash)["ok"],"The player must be able to leash a Builder into the rival village")
	world.step([leash])
	state["tick"]=int(progress["next_scan"])-1
	var events:=world.step()
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_astari_festival_started") and progress["festival_until"]-state["tick"]==300,"The original builder scan must start the 30-second forced festival")
	check(p["happiness"]["player"]>0.99 and p["happiness"]["astari"]==0,"The forced festival must apply the original happiness swing")
	if failures: quit(1); return
	state["tick"]=int(progress["festival_until"])-2
	world.step()
	check(not p["script_unlocks"].has("winAstari"),"The village must remain locked until the festival ends")
	world.step()
	for tick in range(60): world._advance_source_influence([])
	world.step()
	check(world.source_plot_eligible(327,310) and "Card_AstariConquered" in p["discovered"],"Taking over the village must expose the original beacon and grant its card")
	var ark: Dictionary=world.source_shrine_site("1036")
	var start:={"type":"repair_shrine","id":ark["id"]}
	var other: Dictionary=state["followers"][1]
	other.merge({"x":339.0,"z":295.0,"state":"idle"},true)
	state["wheat"]=700
	state["ore"]=550
	state["belief"]=300
	check(not world.inspect(start)["ok"],"The Ark must stay out of reach until beacon 1035 is activated")
	builder.merge({"x":326.0,"z":310.0,"state":"idle"},true)
	var beacon:={"type":"leash","followers":[builder["id"]],"x":327,"z":310}
	check(world.inspect(beacon)["ok"],"The real beacon site must accept the leashed Builder. Builder %s, plan %s, belief %s"%[builder,world.source_shrine_repair_plan(world.source_shrine_site("1035"),Vector2i(326,310)),state["belief"]])
	if failures: quit(1); return
	world.step([beacon])
	check(state["ore"]==500,"Starting beacon 1035 must cost 50 ore")
	complete_current_build(world)
	var activate:={"type":"campaign_activate_shrine","id":"1035"}
	check(world.inspect(activate)["ok"],"The repaired beacon must be ready to activate")
	world.step([activate])
	for tick in range(60): world._advance_source_influence([])
	world.step()
	check(world.source_plot_eligible(345,300),"The original beacon must reveal the Ark site")
	state["wheat"]=699
	check(not world.inspect(start)["ok"],"The Ark must require all 700 wheat")
	state["wheat"]=700
	state["ore"]=499
	check(not world.inspect(start)["ok"],"The Ark must require all 500 ore")
	state["ore"]=500
	check(world.inspect(start)["ok"],"The restored Ark site must accept the nearby Builder")
	if failures: quit(1); return
	world.step([start,start])
	var hull: Dictionary=state["homes"].back()
	check(state["wheat"]==0 and state["ore"]==0 and hull["model_id"]=="ark.group.bin:dff1563f","Construction must charge once and use the original assembled hull")
	check(hull["build_ticks"]==72000 and hull["build_capacity"]==300,"Construction must retain the source time and builder capacity")
	complete_current_build(world)
	check(ark["complete"] and opening["ark_progress"]["complete"],"Finishing the hull must complete the Ark milestone")
	check(hull["residents"]==1 and other.get("indoors_home")==hull["id"],"The builder who worked on the Ark must board on completion")
	builder.merge({"x":350.0,"z":295.0,"state":"idle"},true)
	var board:={"type":"leash","followers":[builder["id"]],"x":345,"z":300}
	check(world.inspect(board)["ok"],"The completed Ark must accept another reachable passenger through the leash")
	world.step([board,board])
	var stats:=world.inspect_building(ark["id"],"temple")
	check(stats["occupants"]==2 and stats["capacity"]==300,"Ark inspection must show the two boarded passengers and the original 300 places")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"The finished Ark and conquest flags must reload")
	check_crossing(restored)
	print("Homeworld6 Astari and Ark crossing: ",failures," failures")
	quit(1 if failures else 0)


func complete_current_build(world: RefCounted) -> void:
	var home: Dictionary=world._state["homes"].back()
	home["temple_work"]=preload("res://simulation/source_terrain.gd").f32(float(home["build_ticks"]-1)*0.1)
	home["progress"]=int(home["build_ticks"])-1
	for tick in range(5):
		if home["progress"]>=home["build_ticks"]: break
		world.step()


func check_crossing(home: RefCounted) -> void:
	var source: Dictionary=home._state["progression"]
	for id: String in ["Card_Settlement_Farming","Card_Settlement_Mine","Card_GodPower_TotemActivate","Card_GrainToBuild","Card_RepairTemple_2"]:
		source["discovered"].append(id)
		source["completed"].append(id)
	source["inventory"]["Sticker_Textile_1"]=3
	source["discovered"].append("Card_WheatBuff_1")
	source["research"]["Card_WheatBuff_1"]=1
	source["assigned_resources"]["Card_WheatBuff_1"]={"Sticker_Textile_1":1}
	var sail:={"type":"campaign_ark_sail","id":"1036"}
	check(home.inspect(sail)["ok"] and home.step([sail]).any(func(event: Dictionary) -> bool: return event["type"]=="campaign_ark_sail"),"The completed and staffed Ark must accept Set Sail")
	var crew: Array=home.ark_manifest()
	check(crew.size()==2,"The departure manifest must contain only boarded followers")
	var content:=preload("res://infrastructure/campaign_content.gd").map_definition("homeworld7")
	content["ark_passengers"]=crew
	content["ark_research"]=home.ark_research()
	var weyworld:=World.new()
	weyworld.initialize({"campaign_data":content},RandomNumberGenerator.new())
	var state: Dictionary=weyworld._state
	var ark: Dictionary=state["homes"][0]
	var inherited: Dictionary=state["progression"]
	check("GodPower_PlaceSettlement_2" in inherited["powers"] and "GodPower_PlaceSettlement_3" in inherited["powers"],"Inherited Homeworld advances must enable Weyworld farming and mining")
	check(inherited["inventory"]["Sticker_Textile_1"]==3 and inherited["research"]["Card_WheatBuff_1"]==1,"Unspent stickers and partial research must survive the crossing")
	check(state["wheat"]==700 and state["ore"]==500 and state["belief"]==25000,"The destination must retain its authored starting resources")
	check(ark["anchor_x"]==88 and ark["anchor_z"]==248 and ark["capacity"]==2 and ark["residents"]==2,"Weyworld must use the authored landing and PeopleInArk capacity")
	check(state["followers"].size()==4,"Keep the two authored Weyworld followers alongside the arriving crew")
	var release:={"type":"weyworld_release_ark","id":ark["id"]}
	for tick in range(4): weyworld.step()
	check(ark["residents"]==2 and state["followers"][0].get("ark_passenger",false),"Passengers must remain aboard until released")
	check(weyworld.inspect(release)["ok"],"The real Weyworld shore must provide a legal exit")
	weyworld.step([release])
	check(ark["residents"]==1 and not state["followers"][0].has("ark_passenger"),"The Builders action must release one passenger")
	var restored:=World.new()
	check(restored.restore(weyworld.export_state(),RandomNumberGenerator.new()) and restored.inspect(release)["ok"],"Weyworld must reload with its remaining crew")
