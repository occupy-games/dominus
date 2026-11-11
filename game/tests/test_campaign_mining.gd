extends SceneTree

const World = preload("res://simulation/world.gd")
const Farming = preload("res://simulation/campaign_farming.gd")
const Economy = preload("res://simulation/campaign_economy.gd")
const Temples = preload("res://simulation/temple_rules.gd")
const Plots = preload("res://simulation/source_plot_conversion.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var world:=World.new()
	var rng:=RandomNumberGenerator.new()
	rng.seed=550
	world.initialize({"campaign_data":preload("res://infrastructure/campaign_opening_content.gd").definition()},rng)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var progression: Dictionary=state["progression"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(progression,site["id"])
	progression["script_unlocks"]={"PlotsAppearClaim":true,"Low_Rank_1":true}
	for tick in range(24): world._advance_source_influence([])
	world._advance_source_plots()
	var plot: Dictionary={}
	var entrance:=Vector2i.ZERO
	for candidate: Dictionary in world.promised_growth_plots():
		var center:=Vector2(candidate["x"],candidate["z"])+Vector2.ONE*float(candidate["size"])*0.5
		var start:=Vector2i(candidate["x"]-1,candidate["z"])
		if world.height_at(start.x,start.y)<=0: continue
		for other: Dictionary in world.promised_growth_plots():
			if candidate["id"]==other["id"] or world.source_house_for_plot(other["x"],other["z"],other["size"],2).is_empty(): continue
			var other_center:=Vector2(other["x"],other["z"])+Vector2.ONE*float(other["size"])*0.5
			if Rect2i(other["x"],other["z"],other["size"],other["size"]).has_point(start): continue
			if center.distance_to(other_center)>11.5 or not world.promised_plot_reachable(other,start): continue
			plot=candidate
			entrance=start
			break
		if not plot.is_empty(): break
	check(not plot.is_empty(),"The original opening terrain must offer a reachable source mine plot")
	if failures: quit(1); return
	var home_id: int=state["next_id"]
	state["next_id"]+=1
	var point:=Vector2i(plot["x"]+int(plot["size"])/2,plot["z"]+int(plot["size"])/2)
	Plots.release_plot(state["source_plots"],plot["id"],true,false)
	state["homes"].append({"id":home_id,"x":int(plot["x"]),"z":int(plot["z"]),"anchor_x":point.x,"anchor_z":point.y,
		"span":int(plot["size"]),"capacity":2,"residents":2,"stored":7,"max_belief":20,"min_belief":1,"progress":1,"build_ticks":1,
		"work_x":entrance.x,"work_z":entrance.y,"builder":-1,"stalled":false,"script_abode_type":2})
	world._spatial_revision+=1
	for follower: Dictionary in state["followers"]:
		follower.merge({"state":"indoors","indoors_home":home_id,"x":float(entrance.x),"z":float(entrance.y)},true)
	var card: String=opening["definition"]["mining_population_card"]["id"]
	var draft:={"type":"campaign_mining_preview","x":point.x,"z":point.y}
	state["belief"]=7500
	while state["followers"].size()<549: state["followers"].append(world._agent(entrance.x,entrance.y,false))
	world.step()
	check(not card in progression["discovered"] and not world.inspect(draft)["ok"],"Mining must stay locked through 549 followers")
	state["followers"].append(world._agent(entrance.x,entrance.y,false))
	world.step()
	check(card in progression["discovered"] and Farming.MINING_POWER in progression["powers"],"The 550th follower must unlock the source Mining Settlement on discovery")
	state["followers"].resize(2)
	state["belief"]=7499
	check(not world.inspect(draft)["ok"],"Mining settlement costs 7,500 belief")
	state["belief"]=7500
	check(world.inspect(draft)["ok"],"The source Mine power should preview the selected abode")
	if failures: quit(1); return
	world.step([draft])
	check(state["belief"]==7500 and progression["settlements"].is_empty(),"Preview must preserve belief and the abode")
	var confirm:={"type":"campaign_mining_confirm"}
	world.step([confirm,confirm])
	check(state["belief"]==0 and progression["settlements"].size()==1,"Confirmation must charge and place one Mining Settlement")
	if failures: quit(1); return
	var settlement: Dictionary=progression["settlements"][0]
	check(settlement["role"]=="miner" and state["props"].back()["model_id"]=="settlementstatues.group.bin:c738faa1","Use the original miner settlement and statue")
	var deploy:={"type":"deploy_worker","id":settlement["id"]}
	for tick in range(30):
		if world.inspect(deploy)["ok"]: break
		world.step()
	check(world.inspect(deploy)["ok"],"The settlement badge must deploy a worker to the reachable mine")
	if failures: quit(1); return
	world.step([deploy])
	var mine: Dictionary=state["homes"].back()
	check(mine["kind"]=="mine" and str(mine["model_id"]).begins_with("miningfields.group.bin:"),"The worker must construct a source mining assembly")
	check(state["followers"][0]["profession"]=="miner","Construction must assign the original miner profession")
	var harvest:={"type":"collect_settlement","id":settlement["id"]}
	check(mine["harvest_accumulator"]==0,"Unfinished mines cannot produce ore")
	for tick in range(450):
		if mine["harvest_accumulator"]>0: break
		world.step()
	check(mine["progress"]==mine["build_ticks"] and mine["harvest_accumulator"]>0,"The miner must walk, build and produce ore")
	if failures: quit(1); return
	var worker: Dictionary=state["followers"][0]
	for tick in range(4000):
		if settlement["ore"]>0: break
		Economy.update_agent(world,state,worker)
	check(settlement["ore"]==mine["max_belief"] and world.inspect(harvest)["ok"],
		"The miner must carry the original ore batch to their settlement. Mine stock %s, settlement stock %s, delivery %s, worker %s"%[mine["harvest_accumulator"],settlement["ore"],Economy.delivery_point(state,settlement),worker])
	check(not world.inspect({"type":"collect","home_id":mine["id"]})["ok"],"Ore must be collected at the settlement")
	world.step([harvest,harvest])
	check(state["ore"]==mine["max_belief"] and state.get("wheat",0)==0,"Mine harvest must give ore once and leave wheat alone")
	var ore_card:={"type":"claim_card","card":"Card_RepairTemple_2"}
	check(not world.inspect(ore_card)["ok"],"One mine and its harvest cannot unlock ore repair")
	var second: Dictionary=mine.duplicate(true)
	second.merge({"id":state["next_id"],"x":200,"z":350,"anchor_x":200,"anchor_z":350,"builder":-1},true)
	state["next_id"]+=1
	state["homes"].append(second)
	world.step()
	check(world.inspect(ore_card)["ok"] and world.snapshot(false)["currency_metrics"]["ore"]["amount"]==2,"Two player mines must expose ore repair and advance the source meter")
	world.step([ore_card])
	check(Economy.spends_resource(state,"ore"),"Claiming the original advance must enable ore spending")
	check_advanced_farming(world,mine)
	check_stone_abodes(world,mine)
	check_ore_beacon(world)
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Mining settlement, ore and repair advance must survive a save round trip")
	print("Homeworld6 mining: ",failures," failures")
	quit(1 if failures else 0)


func check_advanced_farming(world: RefCounted,mine: Dictionary) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var card := "Card_WheatBuff_1"
	check(not card in p["discovered"],"Advanced Farming must stay hidden below five mines")
	for count in range(3):
		var other:=mine.duplicate(true)
		other.merge({"id":state["next_id"],"x":205+count*5,"z":350,"anchor_x":205+count*5,"anchor_z":350,"builder":-1},true)
		state["next_id"]+=1
		state["homes"].append(other)
	world.step()
	check(card in p["discovered"] and not card in p["completed"],"Five mines must reveal the original typed advance")
	var sticker := "Sticker_Textile_1"
	p["inventory"][sticker]=18
	var farm: Dictionary=p["rules"]["economy"]["plots"]["farm:1"]
	var before:=Economy.harvest_rate(state,farm)
	for count in range(18):
		world.step([{"type":"research_card","card":card,"sticker":sticker}])
	check(card in p["completed"] and is_equal_approx(Economy.harvest_rate(state,farm),before*1.5),"Completing Social research must apply the original wheat production multiplier")


func check_stone_abodes(world: RefCounted,mine: Dictionary) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var definition: Dictionary=state["opening"]["definition"]
	var unlock:=func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(p,key)
	for rank in [5,6]:
		var card: String="Card_AbodeType3_Rank%d"%rank
		var target := 20 if rank==5 else 30
		for count in range(Farming.field_count(state,"mine"),target):
			var other:=mine.duplicate(true)
			other.merge({"id":state["next_id"],"x":400+count*12,"z":600,"anchor_x":400+count*12,"anchor_z":600,"builder":-1},true)
			state["next_id"]+=1
			state["homes"].append(other)
			if count==target-2:
				world.step()
				check(not card in p["discovered"],"The stone abode must remain locked one mine below its threshold")
		world.step()
		check(card in p["discovered"],"The stone abode advance must reveal at its original mine count")
		var sticker := "Sticker_Tools_1"
		p["inventory"][sticker]=24
		for count in range(24):
			world.step([{"type":"research_card","card":card,"sticker":sticker}])
		var row:=preload("res://simulation/source_houses.gd").choose(definition["house_selection"],11 if rank==5 else 12,2,2,unlock)
		var expected: String="StoneHouse_Rank_%d"%rank
		check(row.get("id")==expected,"Matching Tech stickers must enable the original highland footprint")
		check(definition["stone_abodes"][expected]["values"]["capacity"]==(18 if rank==5 else 22),"Stone abodes must use the original resident capacity")


func check_ore_beacon(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	p["script_unlocks"]["Expansion_4b"]=true
	for tick in range(35): world._advance_source_influence([])
	var site: Dictionary=world.source_shrine_site("1020")
	var at:=Vector2i(162,380)
	state["ore"]=9
	check(world.source_shrine_repair_plan(site,at).is_empty(),"The original beacon must reject a payment below ten ore")
	state["ore"]=10
	var plan: Dictionary=world.source_shrine_repair_plan(site,at)
	check(not plan.is_empty() and plan.get("payment",{})=={"ore":10},"The original beacon must offer its exact ore price")
	if plan.is_empty(): return
	var builder: Dictionary=world._agent(at.x,at.y,false)
	state["followers"].append(builder)
	world.assign_source_shrine(builder,plan)
	check(state["ore"]==0 and site["started"],"The first worker must pay for the authored beacon when repair starts")
	var other:=Vector2i(164,380)
	var next: Dictionary=world.source_shrine_repair_plan(site,other)
	check(not next.is_empty() and not next.has("payment"),"A second worker must be able to join the already funded repair")
	if next.is_empty(): return
	var assistant: Dictionary=world._agent(other.x,other.y,false)
	state["followers"].append(assistant)
	world.assign_source_shrine(assistant,next)
	check(state["ore"]==0 and assistant["job"]==builder["job"],"Two builders must share one funded construction")
