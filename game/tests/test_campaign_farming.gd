extends SceneTree

const World = preload("res://simulation/world.gd")
const Progression = preload("res://simulation/progression.gd")
const Conversion = preload("res://simulation/source_plot_conversion.gd")
const Temples = preload("res://simulation/temple_rules.gd")
const Economy = preload("res://simulation/campaign_economy.gd")
const Farming = preload("res://simulation/campaign_farming.gd")
const Rain = preload("res://simulation/campaign_rain.gd")
const Fountain = preload("res://simulation/campaign_fountain.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)


func center(plot: Dictionary) -> Vector2i:
	return Vector2i(plot["x"],plot["z"])+Vector2i.ONE*(int(plot["size"])/2)


func run() -> void:
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var milestone: Dictionary=opening["definition"]["farming_population_card"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(state["progression"],site["id"])
	var progress: Dictionary=state["progression"]
	progress["script_unlocks"]={"PlotsAppearClaim":true,"Low_Rank_1":true}
	world.initialize_authored_chests()
	for tick in range(24): world._advance_source_influence([])
	world._advance_source_plots()
	var plots:=world.promised_growth_plots()
	var pair: Array=[]
	for plot: Dictionary in plots:
		for other: Dictionary in plots:
			if other["id"]!=plot["id"] and center(other).distance_to(center(plot))<12:
				var origin:=Vector2i(plot["x"]-1,plot["z"])
				var area:=Rect2i(other["x"],other["z"],other["size"],other["size"])
				if not world._promised_abode_approach(origin,area,{},true).is_empty():
					pair=[plot,other]
					break
		if not pair.is_empty(): break
	if pair.is_empty():
		push_error("Expected source land with an abode and reachable adjacent plot")
		quit(1)
		return
	# Controlled population and completed house for the Farming-specific gate.
	var plot: Dictionary=pair[0]
	var at:=center(plot)
	var origin:=Vector2i(plot["x"]-1,plot["z"])
	var home_id: int=state["next_id"]
	state["next_id"]+=1
	Conversion.release_plot(state["source_plots"],plot["id"],true,false)
	state["homes"].append({"id":home_id,"x":int(plot["x"]),"z":int(plot["z"]),"anchor_x":at.x,"anchor_z":at.y,"span":4,
		"progress":100,"build_ticks":100,"capacity":3,"residents":3,"stored":15,"max_belief":20,"min_belief":1,
		"work_x":origin.x,"work_z":origin.y,"builder":-1,"stalled":false,"script_abode_type":2})
	world._spatial_revision+=1
	while state["followers"].size()<int(milestone["population"])-1: state["followers"].append(world._agent(origin.x,origin.y,false))
	for index in range(3):
		state["followers"][index].merge({"x":float(origin.x),"z":float(origin.y),"state":"indoors","indoors_home":home_id},true)
	state["belief"]=3000
	world.step()
	check(not world.inspect({"type":"campaign_farm_card"})["ok"],"Below the authored population milestone Farming must remain hidden")
	state["followers"].append(world._agent(origin.x,origin.y,false))
	world.step()
	check(world.inspect({"type":"campaign_farm_card"})["ok"],"The authored 165th follower must discover Farming")
	world.step([{"type":"campaign_farm_card"}])
	world.step([{"type":"campaign_dismiss_level_card"},{"type":"campaign_farm_select"}])
	var draft:={}
	for z in range(at.y-3,at.y+4):
		for x in range(at.x-3,at.x+4):
			var placement:={"type":"campaign_farm_preview","x":x,"z":z}
			if world.inspect(placement)["ok"]:
				draft=placement
				break
		if not draft.is_empty(): break
	var confirm:={"type":"campaign_farm_confirm"}
	check(not world.inspect(confirm)["ok"] and not draft.is_empty(),"Only an affordable source ring can be previewed")
	if failures>0: quit(1); return
	world.step([{"type":"campaign_farm_begin"},draft])
	check(state["belief"]==3000 and progress["settlements"].is_empty(),"Preview must preserve belief and homes")
	world.step([confirm,confirm])
	check(state["belief"]==0 and progress["settlements"].size()==1 and world.dwelling_count()==1 and state["homes"][0].get("settlement_core",false),"Confirm must replace its homes with one settlement exactly once")
	if failures>0: quit(1); return
	var item: Dictionary=progress["settlements"][0]
	check(item["capacity"]==3 and state["homes"][0]["residents"]==3 and state["homes"][0]["stored"]==15,"Compression must preserve residents, capacity and belief")
	var deploy:={"type":"deploy_worker","id":item["id"]}
	for tick in range(80):
		if world.inspect(deploy)["ok"]: break
		world.step()
	check(world.inspect(deploy)["ok"],"The settlement must offer a real source plot to its farmer")
	world.step([deploy])
	if state["homes"].size()<2: quit(1); return
	var field: Dictionary=state["homes"].back()
	var harvest:={"type":"collect","home_id":field["id"]}
	check(opening["farming_step"]==5 and not world.inspect(harvest)["ok"],"Starting a real field must complete the lesson and keep premature harvest locked")
	var saved:=world.export_state()
	var restored:=World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"The actual merged settlement and in-progress field must reload")
	if failures>0: quit(1); return
	field=restored._state["homes"].back()
	for tick in range(3900):
		if restored.inspect(harvest)["ok"]: break
		restored.step()
	check(restored.inspect(harvest)["ok"],"A source farmer must walk, build and grow a full crop at the authored rate")
	restored.step([harvest,harvest])
	check(restored._state.get("wheat",0)==field["max_belief"] and not restored.inspect(harvest)["ok"],"One click must collect the crop exactly once")
	check(restored.snapshot(false)["currency_metrics"]["wheat"]["amount"]==1,"The original field bar must count the built plot independently of wheat stock")
	check(restored._state["opening"]["error"].is_empty(),"The original Farming callbacks must complete without a script error")
	if failures==0: check_grain_building(restored,deploy)
	print("Source Farming milestone, settlement and field: ",failures," failures")
	quit(1 if failures else 0)


func check_grain_building(world: RefCounted,deploy: Dictionary) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var claim:={"type":"claim_card","card":"Card_GrainToBuild"}
	check(not world.inspect(claim)["ok"],"A single field and its harvest must leave Super-Fast Building locked")
	check(world.inspect(deploy)["ok"],"A second Farmer must have a reachable source plot")
	if failures>0: return
	world.step([deploy])
	check(world.inspect(claim)["ok"],"Starting the second field must discover the authored building card")
	if failures>0: return
	var events: Array=world.step([claim,claim])
	check(events.has({"type":"campaign_show_card","card":claim["card"]}) and opening["superfast_step"]==1,"Claim must present the original tutorial card once")
	var fields: Array=state["homes"].filter(func(home: Dictionary) -> bool: return home.get("authored_field",false))
	check(fields.size()==15 and world.snapshot(false)["currency_metrics"]["wheat"]["amount"]==2,"The authored stock fields must not inflate the player's field count")
	var free: Dictionary={}
	for item: Dictionary in fields:
		if item["anchor_x"]==149 and item["anchor_z"]==213: free=item; break
	check(not free.is_empty() and free["harvest_accumulator"]==0 and free["source_index"]==8,"The introductory prebuilt field must use its source coordinates, size and initial stock")
	if failures>0: return
	world.step([{"type":"campaign_dismiss_level_card"},{"type":"campaign_ack","id":5502}])
	check(opening["superfast_step"]==2 and free["harvest_accumulator"]==4 and opening["error"].is_empty(),"The source acknowledgment must stock the authored field and begin grain collection")
	var player_fields: Array=state["homes"].filter(func(home: Dictionary) -> bool: return home.get("direct_harvest",false) and not home.get("authored_field",false))
	check(opening["globals"]["nrOfGrainCollectionsLeft"]>0 and player_fields[0]["harvest_accumulator"]>0,"The source settlement query must fill and mark its local fields")
	var free_wheat:={"type":"collect","home_id":free["id"]}
	for tick in range(220):
		if world.inspect(free_wheat)["ok"]: break
		world.step()
	check(world.inspect(free_wheat)["ok"],"The card must expose its original influence area to reach the prebuilt harvest")
	if failures>0: return
	var before: int=state["wheat"]
	world.step([free_wheat,free_wheat])
	check(state["wheat"]==before+4 and opening["persistent"].get("FreeWheatCollected",0)==1,"Collecting the free field must award its stock once and dispatch the source callback")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Stocked and harvested authored fields must survive save and reload")
	if failures>0: return
	world=restored
	state=world._state
	opening=state["opening"]
	for field: Dictionary in player_fields:
		var crop:={"type":"collect","home_id":field["id"]}
		for tick in range(220):
			if world.inspect(crop)["ok"]: break
			world.step()
		check(world.inspect(crop)["ok"],"Every marked local field must produce collectable tutorial wheat")
		world.step([crop])
	if world.inspect({"type":"campaign_ack","id":5505})["ok"]: world.step([{"type":"campaign_ack","id":5505}])
	check(opening["superfast_step"]==5 and opening["error"].is_empty(),"The original collection callbacks must finish the lesson")
	check_paid_abode(world)
	if failures==0: check_rain(world)
	if failures==0: check_mud_lodge(world)
	if failures==0: check_fountain(world)
	if failures==0: check_source_chest(world)
	if failures==0: check_grain_advances(world)


func check_paid_abode(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var paid_plot: Dictionary={}
	var entrance:=Vector2i.ZERO
	var cost:=0
	for plot: Dictionary in world.promised_growth_plots():
		cost=world.source_abode_wheat_cost(plot)
		if cost<=0 or cost>int(state["wheat"]): continue
		var area:=Rect2i(plot["x"],plot["z"],plot["size"],plot["size"])
		for candidate: Vector2i in [area.position-Vector2i(1,0),area.position-Vector2i(0,1),Vector2i(area.end.x,area.position.y),Vector2i(area.position.x,area.end.y)]:
			if not world._promised_abode_approach(candidate,area,{}).is_empty():
				paid_plot=plot
				entrance=candidate
				break
		if not paid_plot.is_empty(): break
	check(not paid_plot.is_empty(),"The unlocked source terrain must offer an affordable ordinary plot outside settlements")
	if paid_plot.is_empty(): return
	var builder: Dictionary=world._agent(entrance.x,entrance.y,false)
	state["followers"].append(builder)
	var stock: int=state["wheat"]
	state["wheat"]=cost-1
	check(not world.begin_promised_abode(paid_plot,builder["id"]) and paid_plot["id"] in state["source_plots"]["active"] and state["wheat"]==cost-1,"Insufficient wheat must preserve the stock and source plot")
	state["wheat"]=stock
	check(world.begin_promised_abode(paid_plot,builder["id"]) and state["wheat"]==stock-cost,"A real ordinary abode must debit its source wheat cost exactly once")
	var home: Dictionary=state["homes"].back()
	var seconds: float=state["opening"]["definition"]["house_base_stats"]["rows"][home["source_index"]]["values"]["build time"]
	check(home["build_ticks"]==roundi(seconds),"The source 0.1 build-time modifier must apply to the inherited abode duration")
	for tick in range(400):
		if home["progress"]>=home["build_ticks"]: break
		world.step()
	check(home["progress"]==home["build_ticks"] and state["wheat"]==stock-cost,"The assigned Builder must finish the paid abode without paying again")


func check_rain(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var fields: Array=state["homes"].filter(func(home: Dictionary) -> bool: return home.get("direct_harvest",false) and not home.get("authored_field",false))
	var field: Dictionary=fields[0]
	var cast:={"type":"use_power","power":Rain.POWER,"x":field["anchor_x"],"z":field["anchor_z"]}
	var claim:={"type":"claim_card","card":Rain.CARD}
	var stop:={"type":"campaign_rain_stop"}
	# Model the remaining field-count gate with unstaffed fields. Keep the actual
	# staffed field and its source worker from the preceding campaign steps.
	while Farming.field_count(state)<5:
		check(not world.inspect(claim)["ok"] and not Rain.POWER in state["progression"]["powers"],"Rain must stay locked below five player fields")
		var extra:=field.duplicate(true)
		extra.merge({"id":state["next_id"],"x":300+state["next_id"],"z":200,"builder":-1},true)
		state["next_id"]+=1
		state["homes"].append(extra)
		world.step()
	check(world.inspect(claim)["ok"] and Rain.POWER in state["progression"]["powers"],"Five player fields must discover the zero-sticker advance and unlock Rain")
	var before: float=field["harvest_accumulator"]
	var base:=Economy.harvest_rate(state,field)*World.TICK_SECONDS
	state["belief"]=30
	world.step([cast,cast])
	check(state["belief"]==20 and is_equal_approx(float(field["harvest_accumulator"])-before,101*base),"Two inputs in one tick must debit belief once and accelerate the staffed field")
	before=field["harvest_accumulator"]
	world.step()
	check(state["belief"]==10 and is_equal_approx(float(field["harvest_accumulator"])-before,101*base),"A stationary hold must keep spending and growing on ticks")
	before=field["harvest_accumulator"]
	world.step([stop,claim,claim])
	check(state["belief"]==10 and is_equal_approx(float(field["harvest_accumulator"])-before,base),"Release must immediately restore ordinary growth without spending")
	check(state["progression"]["completed"].count(Rain.CARD)==1,"The free advance must be claimable once")
	world.step([cast])
	world.step()
	check(state["belief"]==0 and not state["opening"].has("rain_cast"),"An empty belief balance must stop Rain without overdrawing")


func check_fountain(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var rules: Dictionary=opening["definition"]["fountain"]
	var claim:={"type":"claim_card","card":Fountain.CARD}
	while state["followers"].size()<int(rules["population"])-1:
		state["followers"].append(world._agent(157,123,false))
	world.step()
	check(not world.inspect(claim)["ok"],"The Fountain advance must remain unavailable at 259 followers")
	state["followers"].append(world._agent(157,123,false))
	world.step()
	check(world.inspect(claim)["ok"] and not Fountain.POWER in state["progression"]["powers"],"At 260 followers the advance must be revealed before the gift unlocks")
	var events: Array=world.step([claim,claim])
	check(events.has({"type":"campaign_show_card","card":Fountain.CARD}) and Fountain.POWER in state["progression"]["powers"],"Claim the source Fountain advance once to unlock its gift")
	world.step([{"type":"campaign_dismiss_level_card"}])
	check(not opening.has("fountain_card_open"),"Closing the Fountain card must dismiss the tutorial")
	var placement:={}
	state["gems"]=10
	for home: Dictionary in state["homes"]:
		if home.get("kind","")!="": continue
		for z in range(int(home["z"])-5,int(home["z"])+8):
			for x in range(int(home["x"])-5,int(home["x"])+8):
				var command:={"type":"use_power","power":Fountain.POWER,"x":x,"z":z}
				if world.inspect(command)["ok"]: placement=command; break
			if not placement.is_empty(): break
		if not placement.is_empty(): break
	check(not placement.is_empty(),"The real terrain must offer a legal 2 × 1 Fountain site near a completed abode")
	if failures>0: return
	state["gems"]=9
	check(not world.inspect(placement)["ok"],"The recovered Fountain price must be ten gems")
	state["gems"]=10
	var before: int=state["props"].size()
	world.step([placement,placement])
	check(state["gems"]==0 and state["props"].size()==before+1,"Placement must occupy the site and debit exactly ten gems")
	var fountain: Dictionary=state["props"].back()
	check(world._occupied(fountain["x"],fountain["z"]) and world._occupied(fountain["x"]+1,fountain["z"]),"Both original Fountain cells must block occupation")
	var tap:={"type":"campaign_fountain_tap","id":fountain["id"]}
	var happiness: Dictionary=state["progression"]["happiness"]
	var old: float=happiness["player"]
	events=world.step([tap,tap])
	check(events.count({"type":"source_sound","event":"Fountain celebration"})==1 and is_equal_approx(float(happiness["player"])-old,0.1),"The first tap must play the source celebration and raise happiness once")
	check(not world.inspect(tap)["ok"] and opening.get("fountain_tutorial_done",false),"An active celebration must not award repeat happiness")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and not restored.inspect(tap)["ok"],"The installed Fountain and its celebration must survive a reload")


func check_mud_lodge(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var rules: Dictionary=state["opening"]["definition"]
	var card:="Card_AbodeType1_Rank2"
	var research: Dictionary=p["rules"]["research_cards"][card]
	while state["followers"].size()<179:
		state["followers"].append(world._agent(157,123,false))
	world.step()
	check(not card in p["discovered"],"The larger mud abode must remain locked at 179 followers")
	state["followers"].append(world._agent(157,123,false))
	world.step()
	check(card in p["discovered"] and not card in p["completed"],"The original 180-follower milestone must reveal the mud abode advance")
	var sticker:="Sticker_Tools_1"
	var points: int=p["rules"]["stickers"][sticker]["contributions"].get(research["research_type"],0)
	check(points>0,"Tools must match the source tech advance")
	if failures>0: return
	var assignment:={"type":"research_card","card":card,"sticker":sticker}
	var needed:=ceili(float(research["research_needed"])/points)
	p["inventory"][sticker]=needed
	for index in range(needed): world.step([assignment])
	var unlocked:=func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(p,key)
	var house:=preload("res://simulation/source_houses.gd").choose(rules["house_selection"],5,0,0,unlocked)
	check(card in p["completed"] and house.get("id")=="AbodeType_1_Rank_2","Filling the tech advance must unlock the original five-cell lowland abode")
	check(rules["mud_lodge"]["model_id"]=="lowlandrural2.group.bin:90cbbc80" and rules["mud_lodge"]["values"]["capacity"]==5,"The larger abode must use the original assembly and five resident slots")


func check_source_chest(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var fallback: Array=opening["definition"]["authored_sticker_chests"].filter(func(row: Dictionary) -> bool: return row["reward"].is_empty())
	check(fallback.size()==82,"All source sites that roll a sticker must be registered")
	var action: Dictionary={}
	for chest: Dictionary in opening["chests"]:
		if not chest["reward"].is_empty(): continue
		var candidate:={"type":"open_chest","id":"reward:"+str(chest["source_id"])}
		if world.inspect(candidate)["ok"]:
			action=candidate
			break
	check(not action.is_empty(),"The original reachable sites must include a chest that rolls a sticker")
	if failures>0: return
	var reward: String=""
	var grants:=0
	world.step([action,action])
	for tick in range(160):
		for event: Dictionary in world.step():
			if event["type"]=="chest_opened" and event["id"]==action["id"]:
				reward=event["card"]
				grants+=1
		if grants>0: break
	check(grants==1 and state["progression"]["rules"]["stickers"].has(reward) and state["progression"]["inventory"].get(reward,0)>0,"The recovered selector must grant one original sticker to the shared inventory")
	for tick in range(160):
		if not world.snapshot(false)["progression"]["chests"].any(func(chest: Dictionary) -> bool: return chest["id"]==action["id"]): break
		world.step()
	check(not world.snapshot(false)["progression"]["chests"].any(func(chest: Dictionary) -> bool: return chest["id"]==action["id"]),"The original lifetime must remove the used chest")


func check_grain_advances(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var rules: Dictionary=state["opening"]["definition"]
	var source: Array=rules["grain_advances"]
	check(source.map(func(row: Dictionary) -> int: return row["fields"])==[8,12,40],"Use the three authored field milestones")
	if failures>0: return
	for index in range(source.size()):
		var card: String=source[index]["id"]
		var threshold: int=source[index]["fields"]
		add_field_fixtures(state,threshold-1)
		world.step()
		check(not card in p["discovered"],"The source advance must stay hidden below its field threshold: "+card)
		add_field_fixtures(state,threshold)
		world.step()
		check(card in p["discovered"] and not world.inspect({"type":"claim_card","card":card})["ok"],"The source field milestone must open typed research for "+card)
		if failures>0: return
		var research: Dictionary=p["rules"]["research_cards"][card]
		var resource: String="Sticker_Tools_1" if index!=1 else ""
		if resource.is_empty():
			for id: String in p["rules"]["stickers"]:
				var sticker: Dictionary=p["rules"]["stickers"][id]
				if p["rules"]["reward_cards"].has(id) and int(sticker["contributions"].get("TRADE",0))>0:
					resource=id
					break
		var points: int=p["rules"]["stickers"][resource]["contributions"][research["research_type"]]
		var copies:=ceili(float(research["research_needed"])/points)
		p["inventory"][resource]=copies
		for count in range(copies):
			world.step([{"type":"research_card","card":card,"sticker":resource}])
		check(card in p["completed"] and p["inventory"][resource]==0,"Matching stickers must complete "+card)
		if index==1:
			check(Farming.BUILDER_POWER in p["powers"],"Builder Settlement power must unlock on completed Trade research")
			continue
		var span:=7 if index==0 else 9
		var source_id:="AbodeType_3_Rank_%d"%(3 if index==0 else 4)
		var unlocked:=func(key: String) -> bool: return preload("res://simulation/source_unlocks.gd").enabled(p,key)
		var row:=preload("res://simulation/source_houses.gd").choose(rules["house_selection"],span,1,1,unlocked)
		check(row.get("id")==source_id,"The advance must unlock the matching midland footprint")
		var expected:="lowlandrural2.group.bin:"+("41a622c1" if index==0 else "f2808902")
		check(rules["wooden_abodes"][source_id]["model_id"]==expected,"The footprint must use the original assembled model")
	if failures==0: check_builder_settlement(world)


func add_field_fixtures(state: Dictionary,target: int) -> void:
	var example: Dictionary={}
	for home: Dictionary in state["homes"]:
		if home.get("direct_harvest",false) and not home.get("authored_field",false):
			example=home
			break
	for index in range(Farming.field_count(state),target):
		var field:=example.duplicate(true)
		var x:=600+index*9
		field.merge({"id":state["next_id"],"x":x,"z":600,"anchor_x":x,"anchor_z":600,"work_x":x,"work_z":600,"builder":-1},true)
		state["next_id"]+=1
		state["homes"].append(field)


func check_builder_settlement(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var home: Dictionary={}
	for item: Dictionary in state["homes"]:
		if item.has("settlement_id") or not str(item.get("kind","")).is_empty() or item["progress"]<item["build_ticks"]: continue
		home=item
		break
	check(not home.is_empty(),"The completed wheat-funded abode must remain available for Builder compression")
	if failures>0: return
	var draft:={"type":"campaign_builder_preview","x":roundi(home["anchor_x"]),"z":roundi(home["anchor_z"])}
	state["belief"]=2999
	check(not world.inspect(draft)["ok"],"The original Builder Settlement must require 3,000 belief")
	state["belief"]=3000
	var plan: Dictionary=world.inspect(draft)
	check(plan["ok"] and home["id"] in plan.get("members",[]),"Builder preview must include the completed abode")
	if failures>0: return
	var before: int=world.dwelling_count()
	var settlements: int=p["settlements"].size()
	world.step([draft])
	check(state["belief"]==3000 and world.dwelling_count()==before and p["settlements"].size()==settlements,"Builder preview must preserve the abodes and belief")
	var confirm:={"type":"campaign_builder_confirm"}
	world.step([confirm,confirm])
	check(state["belief"]==0 and p["settlements"].size()==settlements+1,"Builder confirmation must charge once")
	var item: Dictionary=p["settlements"].back()
	check(item["role"]=="builder" and item["capacity"]==plan["capacity"] and item["members"].size()==1,"Builder compression must preserve capacity and create a single core")
	check(state["props"].back()["model_id"]=="settlementstatues.group.bin:19b106ed","The settlement must use the original Builder statue")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Builder settlement and completed research must survive reload")
	if failures>0: return
	var deploy:={"type":"deploy_worker","id":item["id"]}
	var result: Dictionary=restored.inspect(deploy)
	check(result.get("plot_command",{}).get("type")=="sprog","Builder dispatch must use the regular abode and shrine construction rules")
	if result["ok"]:
		check(restored.step([deploy]).any(func(event: Dictionary) -> bool: return event["type"]=="sprog"),"A ready Builder must leave the settlement through its badge action")
