extends RefCounted
## Authored Homeworld6 rescue/trail. All timing and callbacks use simulation ticks.
## Later tutorial/story stages are retained as source data, not fabricated here.

const Interpreter = preload("res://simulation/voyage_script.gd")
const DayCycle = preload("res://simulation/day_cycle.gd")
const SourceRocks = preload("res://simulation/authored_rocks.gd")
const ROCK_ID_BASE := 4294967296
const PLOT_HANDLE := 0x05000000
const MESSAGE_GROUPS := {"Trail":0,"PromisedLand":1000,"Timeline":2000,"ShrineOfExpansion":3000,"Belief":4000,"Discovery":5000,"PitOfDoom":5100,"Leash":5200,"Events":5300,"Farming":5400,"SuperFast":5500}
const Farming = preload("res://simulation/campaign_farming.gd")
var world: RefCounted
var state: Dictionary
var events: Array
var opening: Dictionary
var vm := Interpreter.new()


static func initialize(definition: Dictionary) -> Dictionary:
	SourceRocks.prepare(definition)
	var globals: Dictionary = definition["constants"].duplicate(true)
	globals["blockedFollowerObj"]=-1
	globals.merge(definition.get("helpers",{}).duplicate(true))
	globals["DESKTOP_MODE"]=true
	globals["initialFollowers"]={}
	globals["firstPlotPosition"]={"1":null,"2":null,"3":null}
	globals["origTimeOfDaySpeed"]=definition["day_cycle"]["configuration"]["TimeOfDaySpeed"]
	globals["abodesInState0"]=0
	var entries: Array = []
	for row: Dictionary in definition["route"]: entries.append(row["entry"].duplicate(true))
	return {"definition":definition,"phase":"rescue","checkpoint":-1,"globals":globals,
		"entries":entries,
		"submerged_levels":{},"observer":{"mode":"all"},"reactions":{},"next_reaction":1,"tips":{},"next_tip":1,
		"clock":DayCycle.initialize(definition["day_cycle"]),"effects":{},"next_effect":1,
		"promised_step":-1,"actions":{},"next_action":1,"reaction_objects":{},"activity_exception":null,"tree_regeneration":false,
		"camera_locked":true,"zoom_locked":true,
		"scheduled":[],"messages":[{"id":2,"callback":null},{"id":3,"callback":null}],
		"protected":[],"persistent":{},"last_topology":-1,"blocked":false,
		"movement_paused":false,"reaction_speed":float(globals["origGotoSpeedMult"]),"rescue_tick":-1,"revision":0,"error":""}


func configure(owner: RefCounted,data: Dictionary,output: Array) -> void:
	world=owner
	state=data
	events=output
	opening=state["opening"]
	# Script tables use one-based follower indices and a zero-based route. Rebind
	# these aliases after restoring JSON, which cannot preserve table identity.
	var blocks := {}
	for i in range(opening["entries"].size()):
		var entry: Dictionary = opening["entries"][i]
		# The source dispatches these authored mixed-case callback names in lower case.
		for name: String in ["onArrived","onBlocked","onUnblocked"]:
			if entry.has(name): entry[name.to_lower()]=entry[name]
		blocks[str(i)]=entry
	opening["globals"]["BLOCKAGES"]=blocks
	opening["globals"]["currentBlockage"]=int(opening["checkpoint"])
	opening["globals"]["string"]={"format":{"builtin":"string.format"}}
	opening["globals"]["table"]={"insert":{"builtin":"table.insert"},"sort":{"builtin":"table.sort"}}
	if opening["definition"]["constants"].has("en_HudComponent"):
		opening["globals"]["en_HudComponent"]=opening["definition"]["constants"]["en_HudComponent"]
	if opening["globals"]["initialFollowers"].is_empty():
		for i in range(opening["protected"].size()): opening["globals"]["initialFollowers"][str(i+1)]={"id":int(opening["protected"][i]),"blockage":-1}
	vm.initialize(opening["definition"]["program"],opening["globals"],api)


func show_message(id: int, callback: Variant = null) -> void:
	for message: Dictionary in opening["messages"]:
		if int(message["id"])==id:
			message["callback"]=callback
			return
	var message := {"id":id,"callback":callback}
	var entry: Dictionary = opening["definition"]["messages"].get(str(id),{})
	if entry.has("hintDelay"): message["visible_tick"]=int(state["tick"])+roundi(float(entry["hintDelay"])*10)
	if id==1005: message["anchor"]=first_plot_anchor()
	var getter: Dictionary=entry.get("object_get",{})
	if not getter.is_empty():
		var object: Variant=vm.hook(str(getter["symbol"])) if getter.has("symbol") else vm.invoke(getter)
		if object!=null:
			message["object"]=object
			if id in [5007,5102,5202,5204,5301]:
				var site: Dictionary=world.source_shrine_site(str(object))
				if not site.is_empty(): message["anchor"]={"kind":"temple","x":site["x"],"z":site["z"],"height":(float(world.source_shrine_layer(site))-float(state["source_map"]["sea_level"]))*0.3}
			elif id==5505:
				var plot:=plot_from_handle(state,object)
				if not plot.is_empty(): message["anchor"]={"kind":"plot","x":float(plot["x"])+float(plot["size"])*0.5,"z":float(plot["z"])+float(plot["size"])*0.5}
			elif id==5003:
				message["anchor"]=discovery_plot_anchor(object)
			elif id in [5410,5412]:
				var item:=preload("res://simulation/campaign_economy.gd").settlement(state,int(object))
				if not item.is_empty(): message["anchor"]={"kind":"plot","x":item["x"],"z":item["z"]}
			elif id in [2011,3004,4003,5004,5413,5504] or getter.get("symbol","") in ["getFirstAbode","getSecondAbode","getSproggableAbode"]:
				for home: Dictionary in state["homes"]:
					if home["id"]==object: message["anchor"]={"kind":"plot","x":home["anchor_x"],"z":home["anchor_z"]}; break
			elif int(object)>=ROCK_ID_BASE:
				var cell := int(object)-ROCK_ID_BASE
				var rock := SourceRocks.at(state,cell)
				message["anchor"]={"kind":"rock","x":int(rock.get("x",cell%int(state["width"]))),"z":int(rock.get("z",cell/int(state["width"])))}
			else: message["anchor"]={"kind":"follower","id":int(object)}
	if entry.has("pos3d_get"):
		var position: Variant=vm.invoke(entry["pos3d_get"])
		if position is Dictionary:
			message["anchor"]={"kind":"temple","x":Interpreter.table_get(position,1),"z":Interpreter.table_get(position,2),"height":float(Interpreter.table_get(position,3))-float(state["source_map"]["sea_level"])*0.3}
	if id==29:
		var options: Array = opening["definition"]["messages"]["29"]["options"]
		message["option"]=mini(options.size()-1,floori(world._random.randf()*options.size()))
	opening["messages"].append(message)
	opening["revision"]+=1


func show_ark_message(id: int,site_id: String="") -> void:
	show_message(id)
	if site_id.is_empty(): return
	var site: Dictionary=world.source_shrine_site(site_id)
	if site.is_empty(): return
	for message: Dictionary in opening["messages"]:
		if message["id"]!=id: continue
		message["anchor"]={"kind":"temple","x":site["x"],"z":site["z"],"height":(float(world.source_shrine_layer(site))-float(state["source_map"]["sea_level"]))*0.3}
		break


func clear_message(id: int) -> void:
	for message: Dictionary in opening["messages"].duplicate():
		if int(message["id"])==id: opening["messages"].erase(message); opening["revision"]+=1


func acknowledge(id: int) -> void:
	for message: Dictionary in opening["messages"].duplicate():
		if int(message["id"])!=id: continue
		clear_message(id)
		if message["callback"]!=null: vm.invoke(message["callback"])
		elif id==4 and opening["phase"]=="worship": next_checkpoint()
		if id==1005: opening["first_plot_acknowledged"]=true
		if not vm.error.is_empty(): opening["error"]=vm.error
		return


static func supports_first_plot(story: Dictionary) -> bool:
	return story["phase"]=="promised_land" and int(story["promised_step"])==2 and story["definition"]["helpers"].has("getFirstPlotPosition")


static func supports_expansion(story: Dictionary) -> bool:
	return story["phase"]=="promised_land" and int(story["promised_step"]) in [3,4,5] and story["definition"]["helpers"].has("getSecondRock")

static func supports_growth(story: Dictionary) -> bool:
	return story["phase"]=="promised_land" and int(story["promised_step"])==6 and story["definition"].has("growth_population_card")


static func supports_level_card(story: Dictionary) -> bool:
	return story["phase"]=="promised_land" and int(story["promised_step"]) in [7,8] and story["definition"].has("growth_population_card")


static func supports_first_chest(story: Dictionary) -> bool:
	return story["phase"]=="promised_land" and int(story["promised_step"])==9 and story["definition"].has("first_chest")


static func supports_timeline(story: Dictionary) -> bool:
	return story["phase"]=="timeline" and story.get("timeline_step",-1) in [0,1,2,3] and story["definition"].has("timeline_steps")


static func supports_timeline_housing(story: Dictionary) -> bool:
	return story["phase"]=="timeline" and story.get("timeline_step",-1) in [4,5] and story["definition"].has("mud_hut") and story["definition"].has("timeline_population_card")


static func has_shrine_tutorial(story: Dictionary) -> bool:
	var definition: Dictionary=story["definition"]
	return definition.has("first_shrine_id") and definition.has("shrine_steps") and definition.has("shrine_population_card")


static func supports_shrine_housing(story: Dictionary) -> bool:
	return story["phase"]=="shrine" and int(story["shrine_step"]) in [2,3,4]


func shrine_hook(name: String,args: Array=[]) -> void:
	var step := int(opening["shrine_step"])
	var steps: Array=opening["definition"]["shrine_steps"]
	if step>=steps.size(): return
	var hooks: Dictionary=steps[step]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func set_shrine_step(step: int) -> void:
	opening["phase"]="shrine"
	opening["shrine_step"]=step
	var available: bool=step<opening["definition"]["shrine_steps"].size()
	opening["persistent"]["ShrineOfExpansionProgress"]=step+1 if available else 1337
	opening["handoff"]={"tutorial":"ShrineOfExpansion","step":step,"available":available}
	events.append({"type":"campaign_handoff","tutorial":"ShrineOfExpansion","step":step,"available":available})
	shrine_hook("onListening")
	if not available and has_belief_tutorial(opening): set_belief_step(0)


static func has_belief_tutorial(story: Dictionary) -> bool:
	var definition: Dictionary=story["definition"]
	var steps: Variant=definition.get("belief_steps")
	return steps is Array and steps.size()==4 and preload("res://simulation/source_abode_clumps.gd").valid_rules(definition.get("belief_rules")) and definition["belief_rules"].get("executable_sha256")==definition["day_cycle"]["executable_sha256"]


static func supports_discovery(story: Dictionary) -> bool:
	return story["phase"]=="discovery"


func discovery_hook(name: String,args: Array=[],group: String="Discovery") -> void:
	var step: int=opening["discovery_step"] if group=="Discovery" else opening["pit_step"]
	if step>=opening["definition"]["discovery"][group].size(): return
	var hooks: Dictionary=opening["definition"]["discovery"][group][step]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func next_discovery_step() -> void:
	if not opening["definition"].has("discovery_site_id"):
		opening["handoff"]={"tutorial":"Discovery","step":0,"available":false}
		events.append({"type":"campaign_handoff","tutorial":"Discovery","step":0,"available":false})
		return
	opening["phase"]="discovery"
	opening["discovery_step"]=mini(2,int(opening.get("discovery_step",-1))+1)
	if not opening.has("pit_step"): opening["pit_step"]=0
	opening["persistent"]["DiscoveryProgress"]=opening["discovery_step"]+1
	opening["handoff"]={"tutorial":"Discovery","step":opening["discovery_step"],"available":true}
	events.append({"type":"campaign_handoff","tutorial":"Discovery","step":opening["discovery_step"],"available":true})
	discovery_hook("onListening")


func advance_discovery() -> void:
	if opening.erase("resume_leash_card"):
		clear_message(5201)
		leash_hook("onPostLoad",[0])
	if opening.get("leash_mission_pending",false): return
	if opening.erase("resume_dock_card"):
		clear_message(5205)
		opening.erase("dock_card_open")
		leash_hook("onPostLoad",[0])
	if opening.erase("resume_dock_selection"):
		opening["globals"].erase("selectedWorldObject")
		dock_event_hook("onObjectSelected",[null])
	if opening.erase("resume_pit_card"):
		clear_message(5101)
		discovery_hook("onStartPlay")
		discovery_hook("onStartPlay",[],"PitOfDoom")
	if opening["pit_step"]==1 and opening["definition"].has("pit_sacrifice") and opening.get("leash_step",-1)>=2 and not opening.get("pit_leash_prompt_shown",false):
		opening["pit_leash_prompt_shown"]=true
		discovery_hook("onStartPlay",[],"PitOfDoom")
	if opening["globals"].get("bWaitingForTempleInAoI",false): discovery_hook("onInfluenceChanged")
	for id: int in world.start_growth_construction(): discovery_hook("onAbodeBuilding",[id])
	for event: Dictionary in world.advance_promised_abode():
		if event["hook"]!="onAbodeComplete": continue
		var site: String=world.finish_source_shrine(event["id"])
		if site==opening["definition"].get("discovery_site_id"): discovery_hook("onTempleComplete",[site])
		elif not site.is_empty() and site==opening["definition"].get("dock_site_id"): leash_hook("onTempleComplete",[site])
		elif not site.is_empty() and site==opening["definition"].get("ark",{}).get("site_id"):
			preload("res://simulation/temple_rules.gd").complete(state["progression"],site)
	world.advance_promised_breeding()
	var milestone: Dictionary=opening["definition"].get("leash_population_card",{})
	if not milestone.is_empty() and not opening.has("leash_level_card") and state["followers"].size()>=int(milestone["population"]):
		preload("res://simulation/progression.gd").discover(state["progression"],milestone["id"])
		if milestone["id"] in state["progression"]["discovered"]:
			opening["leash_level_card"]=milestone["id"]
			opening["leash_step"]=0
	if opening.get("leash_step")==2 and opening["globals"].get("bWaitingForDockInAoI",false):
		leash_hook("onInfluenceChanged")
	advance_farming()
	advance_superfast()
	advance_fountain()
	advance_cliff_sculpt()
	advance_belief_advances()
	preload("res://simulation/campaign_ark.gd").advance(world,state,self,events)
	if opening["discovery_step"]==0 and not opening["globals"].get("bWaitingForTempleInAoI",false) and int(state["tick"])%10==0:
		discovery_hook("onAbodeSproggable")
		for message: Dictionary in opening["messages"]:
			if int(message["id"])!=5003: continue
			var old: Dictionary=message.get("anchor",{})
			var anchor := discovery_plot_anchor(message.get("object"))
			if anchor.is_empty():
				opening["globals"].erase("plotNearTempleOfDiscovery")
				var handle: Variant=vm.hook("getPlotNearTempleOfDiscovery")
				anchor=discovery_plot_anchor(handle)
				if not anchor.is_empty(): message["object"]=handle
			if anchor!=old:
				message["anchor"]=anchor
				opening["revision"]+=1
			break


func discovery_plot_anchor(handle: Variant) -> Dictionary:
	if handle==null: return {}
	var registry: Dictionary=state["source_plots"]
	var slot := int(handle)-PLOT_HANDLE
	if not slot in registry["active"]: return {}
	var plot: Dictionary=registry["slots"][slot]
	var position: Dictionary=opening["definition"]["constants"]["DISCOVERY"]
	if not preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(position["x"],position["y"]),9.6): return {}
	var half := float(plot["size"])*0.5
	return {"kind":"plot","x":plot["x"]+half,"z":plot["z"]+half}


func leash_hook(name: String,args: Array=[]) -> void:
	var step: int=opening.get("leash_step",-1)
	var steps: Array=opening["definition"].get("discovery",{}).get("Leash",[])
	if step<0 or step>=steps.size(): return
	var hooks: Dictionary=steps[step]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func finish_leash_lesson() -> void:
	opening.erase("leash_mission_pending")
	leash_hook("onPostLoad",[3])
	events.append({"type":"campaign_autosave"})


func leash_release(command: Dictionary,plan: Dictionary,accepted: bool) -> void:
	if opening.get("leash_step")!=2: return
	for assignment: Dictionary in plan["assignments"]: leash_hook("onLeashAdd",[assignment["id"]])
	var context:={"x":command["x"],"z":command["z"]}
	leash_hook("onLeashComplete" if accepted else "onLeashCancel",[context])


func dock_event_hook(name: String,args: Array=[]) -> void:
	if opening.get("events_step")!=0: return
	var hooks: Dictionary=opening["definition"]["discovery"]["Events"][0]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func finish_first_voyage(won: bool) -> void:
	var outcomes: Dictionary=opening["definition"]["constants"]["FIRST_VOYAGE_RETURN"]
	var progress := int(outcomes["2" if won else "1"])
	opening["persistent"]["EventVoyageProgress"]=maxi(progress,int(opening["persistent"].get("EventVoyageProgress",0)))
	dock_event_hook("onPostLoad",[6])
	events.append({"type":"campaign_autosave"})


func farming_hook(name: String,args: Array=[]) -> void:
	var step: int=opening.get("farming_step",-1)
	var steps: Array=opening["definition"].get("discovery",{}).get("Farming",[])
	if step<0 or step>=steps.size(): return
	var hooks: Dictionary=steps[step]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func set_farming_step(step: int) -> void:
	opening["farming_step"]=step
	opening["persistent"]["FarmingProgress"]=step+1 if step<5 else 1337
	if step==5:
		if opening["definition"].has("grain_building_card"): set_superfast_step(0)
		else:
			opening["handoff"]={"tutorial":"SuperFast","step":0,"available":false}
			events.append({"type":"campaign_handoff","tutorial":"SuperFast","step":0,"available":false})
	farming_hook("onListening")


func advance_farming() -> void:
	var p: Dictionary=state["progression"]
	for housing: Dictionary in opening["definition"].get("housing_advances",[]):
		if state["followers"].size()>=int(housing["population"]):
			preload("res://simulation/progression.gd").discover(p,housing["id"])
	var fields:=Farming.field_count(state)
	for advance: Dictionary in opening["definition"].get("grain_advances",[]):
		if fields>=int(advance["fields"]):
			preload("res://simulation/progression.gd").discover(p,advance["id"])
	if opening["definition"].has("builder_core") and not Farming.BUILDER_POWER in p["powers"] and preload("res://simulation/source_unlocks.gd").enabled(p,Farming.BUILDER_POWER):
		p["powers"].append(Farming.BUILDER_POWER)
		p["revision"]+=1
	var mining: Dictionary=opening["definition"].get("mining_population_card",{})
	if not mining.is_empty() and state["followers"].size()>=int(mining["population"]):
		preload("res://simulation/progression.gd").discover(p,mining["id"])
		if not Farming.MINING_POWER in p["powers"] and preload("res://simulation/source_unlocks.gd").enabled(p,Farming.MINING_POWER):
			p["powers"].append(Farming.MINING_POWER)
			p["revision"]+=1
	if Farming.MINING_POWER in p["powers"]:
		var mines:=Farming.field_count(state,"mine")
		for advance: Dictionary in opening["definition"].get("ore_advances",[]):
			if mines>=int(advance["mines"]):
				preload("res://simulation/progression.gd").discover(p,advance["id"])
	var level: Dictionary=opening["definition"].get("farming_population_card",{})
	if level.is_empty(): return
	var rain: Dictionary=opening["definition"].get("rain",{})
	if opening.get("farming_step",-1)>=4 and not rain.is_empty() and not rain["power"] in p["powers"]:
		if fields>=int(rain["fields"]):
			preload("res://simulation/progression.gd").discover(p,rain["card"])
			if rain["card"] in p["discovered"]:
				p["powers"].append(rain["power"])
	if not opening.has("farming_step") and state["followers"].size()>=int(level["population"]):
		preload("res://simulation/progression.gd").discover(p,level["id"])
		if not level["id"] in p["discovered"]: return
		if not Farming.POWER in p["powers"]: p["powers"].append(Farming.POWER)
		set_farming_step(0)
	if opening.erase("resume_farming"):
		match int(opening["farming_step"]):
			1:
				clear_message(5401)
				farming_hook("onPostLoad",[0])
			2: farming_hook("onStartPlay",[0])
			3:
				farming_hook("onPowerCancel")
				opening.erase("farming_preview")
				clear_farming_confirmation()
	if opening.get("farming_step")==2:
		farming_hook("onBeliefChanged",[state["belief"]])
	elif opening.get("farming_step")==4 and int(state["tick"])%10==0:
		var settlement_id: Variant=vm.hook("getFirstSettlement")
		if settlement_id!=null and world.inspect({"type":"deploy_worker","id":settlement_id})["ok"]:
			farming_hook("onAbodeSproggable",[settlement_id])


func farming_action(kind: String,plan: Dictionary) -> void:
	if kind in ["campaign_farm_preview","campaign_farm_confirm","campaign_farm_cancel"]: clear_farming_confirmation()
	match kind:
		"campaign_farm_card":
			var level: Dictionary=opening["definition"]["farming_population_card"]
			preload("res://simulation/progression.gd").complete(state,level["id"])
			events.append({"type":"campaign_show_card","card":level["id"]})
			farming_hook("onCardShown",[level["source_id"]])
		"campaign_farm_select":
			if opening["farming_step"]==2:
				opening["globals"]["selectedCardHash"]="Card_GodPower_Settlement_2"
				farming_hook("onPowerSelected")
			else: opening["farming_placing"]=true
		"campaign_farm_begin": farming_hook("onSettlementDragBegun")
		"campaign_farm_preview":
			opening["farming_preview"]={"x":plan["x"],"z":plan["z"],"members":plan["members"],"capacity":plan["capacity"]}
			farming_hook("onSettlementMerged")
		"campaign_farm_confirm":
			var id:=Farming.merge(world,state,plan)
			opening.erase("farming_preview")
			opening.erase("farming_placing")
			farming_hook("onSettlementConfirmed",[id])
		"campaign_farm_cancel":
			if opening.erase("farming_preview"): farming_hook("onSettlementCancelled")
			elif not opening.erase("farming_placing"): farming_hook("onPowerCancel")


func clear_farming_confirmation() -> void:
	opening["scheduled"]=opening["scheduled"].filter(func(item: Dictionary) -> bool:
		return item.get("args",[])!=["Farming",9])


func advance_superfast() -> void:
	var card: Dictionary=opening["definition"].get("grain_building_card",{})
	if card.is_empty() or opening.get("farming_step")!=5: return
	if not opening.has("superfast_step"): set_superfast_step(0)
	if opening["superfast_step"]==0 and Farming.field_count(state)>=int(card["fields"]):
		preload("res://simulation/progression.gd").discover(state["progression"],card["id"])
	if opening.erase("resume_superfast"): superfast_hook("onPostLoad",[0])


func set_superfast_step(step: int) -> void:
	opening["superfast_step"]=step
	opening["persistent"]["SuperFastProgress"]=step+1 if step<5 else 1337
	opening["handoff"]={"tutorial":"SuperFast" if step<5 else "Happiness","step":step if step<5 else 0,"available":step<5}
	events.append({"type":"campaign_handoff"}.merged(opening["handoff"]))
	superfast_hook("onListening")


func superfast_hook(name: String,args: Array=[]) -> void:
	var step: int=opening.get("superfast_step",-1)
	var steps: Array=opening["definition"].get("discovery",{}).get("SuperFast",[])
	if step<0 or step>=steps.size(): return
	var hooks: Dictionary=steps[step]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func show_grain_building_card(id: String) -> void:
	preload("res://simulation/progression.gd").complete(state,id)
	world.refresh_source_abode_build_times()
	Farming.place_authored_fields(world,state)
	events.append({"type":"campaign_show_card","card":id})
	superfast_hook("onCardShown",[id])


func advance_fountain() -> void:
	var rules: Dictionary=opening["definition"].get("fountain",{})
	if rules.is_empty(): return
	var p: Dictionary=state["progression"]
	var progression:=preload("res://simulation/progression.gd")
	var unlocks:=preload("res://simulation/source_unlocks.gd")
	if unlocks.enabled(p,"Happiness") and not opening.get("happiness_hint_shown",false):
		opening["happiness_hint_shown"]=true
		show_message(5602)
	if state["followers"].size()>=int(rules["population"]):
		progression.discover(p,rules["card"])
	if opening.erase("resume_fountain_card"):
		events.append({"type":"campaign_show_card","card":rules["card"]})
	if opening.has("fountain_hint_until") and int(state["tick"])>=int(opening["fountain_hint_until"]):
		opening.erase("fountain_hint_until")
		clear_message(5606)


func show_fountain_card(id: String) -> void:
	preload("res://simulation/progression.gd").complete(state,id)
	var power: String=opening["definition"]["fountain"]["power"]
	var p: Dictionary=state["progression"]
	if preload("res://simulation/source_unlocks.gd").enabled(p,power) and not power in p["powers"]:
		p["powers"].append(power)
	opening["fountain_card_open"]=true
	opening["persistent"]["HappinessProgress"]=4
	clear_message(5602)
	show_message(5603)
	events.append({"type":"campaign_show_card","card":id})
	events.append({"type":"campaign_autosave"})


func fountain_placed(fountain: Dictionary) -> void:
	if opening.get("fountain_tutorial_done",false) or opening.has("first_fountain"): return
	opening["first_fountain"]=fountain["id"]
	opening["persistent"]["HappinessProgress"]=7
	show_message(5604)
	for message: Dictionary in opening["messages"]:
		if message["id"]==5604:
			message["anchor"]={"kind":"plot","x":fountain["x"],"z":fountain["z"]}
			break


func fountain_celebrated(id: Variant) -> void:
	if opening.get("first_fountain")!=id or opening.get("fountain_tutorial_done",false): return
	opening["fountain_tutorial_done"]=true
	opening["persistent"]["HappinessProgress"]=1337
	clear_message(5604)
	show_message(5606)
	opening["fountain_hint_until"]=int(state["tick"])+300 # Source callback clears the hint after 30 seconds.


func advance_cliff_sculpt() -> void:
	var rules: Dictionary=opening["definition"].get("cliff_sculpt",{})
	if rules.is_empty(): return
	var p: Dictionary=state["progression"]
	if state["followers"].size()>=int(rules["population"]):
		preload("res://simulation/progression.gd").discover(p,rules["card"])
	var power: String=rules["power"]
	if not power in p["powers"] and preload("res://simulation/source_unlocks.gd").enabled(p,power):
		p["powers"].append(power)
		p["revision"]+=1


func advance_belief_advances() -> void:
	var p: Dictionary=state["progression"]
	for key: String in ["rock_belief","belief_collector"]:
		var rules: Dictionary=opening["definition"].get(key,{})
		if rules.is_empty(): continue
		if state["followers"].size()>=int(rules["population"]):
			preload("res://simulation/progression.gd").discover(p,rules["card"])
		var power: String=rules.get("power","")
		if not power.is_empty() and not power in p["powers"] and preload("res://simulation/source_unlocks.gd").enabled(p,power):
			p["powers"].append(power)
			p["revision"]+=1


func belief_hook(name: String,args: Array=[]) -> void:
	var step: int=opening.get("belief_step",-1)
	if step<0 or step>=opening["definition"]["belief_steps"].size(): return
	var hooks: Dictionary=opening["definition"]["belief_steps"][step]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func set_belief_step(step: int) -> void:
	opening["phase"]="belief"
	opening["belief_step"]=step
	if step==0: opening["globals"]["DEBUG_MODE"]=opening["definition"]["belief_rules"].get("debug_default",false)
	var available: bool=step<opening["definition"]["belief_steps"].size()
	if not available:
		var local_names: Dictionary=opening["definition"]["program"].get("local_function_names",{})
		opening["scheduled"]=opening["scheduled"].filter(func(item: Dictionary) -> bool:
			return local_names.get(str(item.get("callback",{}).get("function",-1)),"")!="fnSculptGrass")
	opening["persistent"]["BeliefProgress"]=step+1 if available else 1337
	opening["handoff"]={"tutorial":"Belief","step":step,"available":available}
	events.append({"type":"campaign_handoff","tutorial":"Belief","step":step,"available":available})
	belief_hook("onListening")


func start_shrine_tutorial() -> void:
	set_shrine_step(0)
	shrine_hook("onLevelUpCard",[opening["definition"]["timeline_population_card"]["ordinal"]])


func timeline_hook(name: String,args: Array=[]) -> void:
	if not supports_timeline(opening) and not supports_timeline_housing(opening): return
	var hooks: Dictionary=opening["definition"]["timeline_steps"][int(opening["timeline_step"])]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)
	if not vm.error.is_empty(): opening["error"]=vm.error


func set_timeline_step(step: int) -> void:
	opening["phase"]="timeline"
	if not opening.has("timeline_open"): opening["timeline_open"]=false
	opening["timeline_step"]=step
	if step==4 and supports_timeline_housing(opening): opening["belief_hud_hidden"]=true
	var finished: bool=step==opening["definition"]["timeline_steps"].size()
	opening["persistent"]["TimelineProgress"]=1337 if finished else step+1
	var available := supports_timeline(opening) or supports_timeline_housing(opening)
	opening["handoff"]={"tutorial":"Timeline","step":step,"available":available}
	events.append({"type":"campaign_handoff","tutorial":"Timeline","step":step,"available":available})
	timeline_hook("onListening")


func timeline_action(show: bool) -> void:
	opening["timeline_open"]=show
	events.append({"type":"campaign_timeline_opened" if show else "campaign_timeline_closed","card":opening["level_card"]})
	timeline_hook("onTimelineOpened" if show else "onTimelineClosed")


static func plot_in_radius(state: Dictionary,center: Vector2,radius: float) -> Dictionary:
	var plots: Dictionary=state.get("source_plots",{})
	for id: int in plots.get("active",[]):
		var plot: Dictionary=plots["slots"][id]
		if preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),center,radius): return plot
	return {}


static func release_candidate(state: Dictionary,id: int) -> Dictionary:
	var breeders: int=int(state["opening"]["definition"]["first_abode_values"]["values"]["breeder count"])
	for home: Dictionary in state["homes"]:
		if int(home["id"])!=id or home.get("kind","")=="shrine" or home["progress"]<home["build_ticks"] or home["residents"]<=home.get("breeder_count",breeders): continue
		for follower: Dictionary in state["followers"]:
			if follower["state"]=="indoors" and follower.get("indoors_home",state["homes"][0]["id"])==id: return {"home":home,"follower":follower}
	return {}


static func inside_plot_sculpt_lock(story: Dictionary,x: int,z: int) -> bool:
	var source: Dictionary=story["definition"]["constants"]
	return x>=source["gTrailSculptLockX0"] and x<=source["gTrailSculptLockX1"] and z>=source["gTrailSculptLockY0"] and z<=source["gTrailSculptLockY1"]


static func plot_from_handle(state: Dictionary,handle: Variant) -> Dictionary:
	if not integer(handle,PLOT_HANDLE,PLOT_HANDLE+1023): return {}
	var plots: Dictionary=state.get("source_plots",{})
	var id := int(handle)-PLOT_HANDLE
	if not plots.get("active",[]).has(id): return {}
	return plots["slots"][id]


static func first_plot_in_range(state: Dictionary,handle: Variant) -> Dictionary:
	var plot:=plot_from_handle(state,handle)
	if plot.is_empty(): return {}
	var rock: Dictionary=state["opening"]["definition"]["constants"]["INITIAL_ROCK"]
	if not preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(rock["x"],rock["y"]),1.0): return {}
	return plot


func first_plot_anchor() -> Dictionary:
	var globals: Dictionary=opening["globals"]
	if first_plot_in_range(state,globals.get("firstPlot")).is_empty(): globals.erase("firstPlot")
	var position: Variant=vm.hook("getFirstPlotPosition")
	var handle: Variant=globals.get("firstPlot")
	var plot := first_plot_in_range(state,handle)
	if plot.is_empty() or not position is Dictionary: return {}
	return {"kind":"plot","handle":handle,"x":Interpreter.table_get(position,1),"z":Interpreter.table_get(position,2),"size":int(plot["size"])}


func refresh_first_plot() -> void:
	for message: Dictionary in opening["messages"]:
		if int(message["id"])!=1005: continue
		var anchor := first_plot_anchor()
		if anchor!=message.get("anchor",{}):
			message["anchor"]=anchor
			opening["revision"]+=1
		api("SelectPLOT",[opening["globals"].get("firstPlot")])
		return
	if not opening.get("first_plot_acknowledged",false) or not state["homes"].is_empty(): return
	var anchor := first_plot_anchor()
	api("SelectPLOT",[anchor.get("handle")])
	if not anchor.is_empty() and world.begin_promised_abode(first_plot_in_range(state,anchor["handle"])):
		opening.erase("selected_plot")
		promised_hook("onAbodeBuilding",[state["homes"][0]["id"]])


func promised_hook(name: String,args: Array) -> void:
	var hooks: Dictionary=opening["definition"]["promised_steps"][int(opening["promised_step"])]["hooks"]
	if hooks.has(name): vm.invoke(hooks[name],args)


func release_builder(id: int,shrine_plan: Dictionary={}) -> void:
	var candidate := release_candidate(state,id)
	if candidate.is_empty(): return
	var agent: Dictionary=candidate["follower"]
	candidate["home"]["residents"]-=1
	agent["state"]="idle"
	agent["away_home"]=id
	agent.erase("indoors_home")
	if not shrine_plan.is_empty(): world.assign_source_shrine(agent,shrine_plan)
	elif supports_growth(opening) or supports_timeline_housing(opening) or supports_shrine_housing(opening) or supports_discovery(opening): agent["seeking_plot"]=true
	opening["released_builder"]=agent["id"]
	if supports_discovery(opening):
		discovery_hook("onFollowerSprogged",[agent["id"]])
		if not shrine_plan.is_empty() and shrine_plan["building_id"]==-1:
			if shrine_plan["site_id"]==opening["definition"].get("dock_site_id"): leash_hook("onTempleBuilding",[shrine_plan["site_id"]])
			else: discovery_hook("onTempleBuilding",[shrine_plan["site_id"]])
	elif opening["phase"]=="shrine": shrine_hook("onFollowerSprogged",[agent["id"]])
	elif supports_timeline_housing(opening): timeline_hook("onFollowerSprogged",[agent["id"]])
	else: promised_hook("onFollowerSprogged",[agent["id"]])


func advance_second_abode() -> void:
	if state["homes"].size()==1:
		var site: Dictionary=opening["definition"]["constants"]["ROCKS_2"]
		var plot := plot_in_radius(state,Vector2(site["x"],site["y"]),site["r"])
		if not plot.is_empty() and world.begin_promised_abode(plot,opening.get("released_builder",-1)):
			promised_hook("onAbodeBuilding",[state["homes"].back()["id"]])
	if state["homes"].size()!=2: return
	for event: Dictionary in world.advance_promised_abode("StandStill" in opening["reactions"].values()):
		promised_hook(event["hook"],[event["id"]])


func advance_growth() -> void:
	for id: int in world.start_growth_construction(): promised_hook("onAbodeBuilding",[id])
	for event: Dictionary in world.advance_promised_abode():
		if event["hook"]=="onEnterHouse": opening["globals"]["entering_follower"]=event["id"]
		promised_hook(event["hook"],[event["id"]])
		opening["globals"].erase("entering_follower")
	var level: Dictionary=opening["definition"]["growth_population_card"]
	if state["followers"].size()>=int(level["population"]):
		preload("res://simulation/progression.gd").discover(state["progression"],level["id"])
		if level["id"] in state["progression"]["discovered"]:
			opening["level_card"]=level["id"]
			clear_message(1018)
			promised_hook("onLevelUpCard",[level["id"]])


func advance_timeline_housing() -> void:
	for id: int in world.start_growth_construction(): timeline_hook("onAbodeBuilding",[id])
	for event: Dictionary in world.advance_promised_abode(): timeline_hook(event["hook"],[event["id"]])
	world.advance_promised_breeding()
	var level: Dictionary=opening["definition"]["timeline_population_card"]
	if state["followers"].size()<int(level["population"]): return
	var progression: Dictionary=state["progression"]
	if not level["id"] in progression["discovered"]:
		preload("res://simulation/progression.gd").discover(progression,level["id"])
	if level["id"] in progression["discovered"]:
		opening["shrine_level_card"]=level["id"]
		timeline_hook("onLevelUpCard",[level["ordinal"]])
	if opening["timeline_step"]==6 and has_shrine_tutorial(opening): start_shrine_tutorial()


func advance_shrine() -> void:
	if int(opening["shrine_step"])<2: return
	if supports_shrine_housing(opening): world.start_growth_construction()
	for event: Dictionary in world.advance_promised_abode():
		if event["hook"]!="onAbodeComplete": continue
		var site: String=world.finish_source_shrine(event["id"])
		if not site.is_empty(): shrine_hook("onTempleComplete",[site])
	world.advance_promised_breeding()
	if not supports_shrine_housing(opening): return
	var level: Dictionary=opening["definition"]["shrine_population_card"]
	if state["followers"].size()<int(level["population"]): return
	var progression: Dictionary=state["progression"]
	if not level["id"] in progression["discovered"]:
		preload("res://simulation/progression.gd").discover(progression,level["id"])
	if level["id"] in progression["discovered"] and not opening.has("belief_level_card"):
		opening["belief_level_card"]=level["id"]
		shrine_hook("onLevelUpCard",[level["ordinal"]])


func level_card_action(show: bool) -> void:
	if supports_discovery(opening):
		var card: String=opening["leash_level_card"]
		if show:
			preload("res://simulation/progression.gd").complete(state,card)
			events.append({"type":"campaign_show_card","card":card})
		leash_hook("onCardShown" if show else "onCardDismissed",[opening["definition"]["leash_population_card"]["source_id"]])
		return
	if opening["phase"]=="belief":
		var card: String=opening["belief_level_card"]
		if show:
			if not card in state["progression"]["completed"]: preload("res://simulation/progression.gd").complete(state,card)
			events.append({"type":"campaign_show_card","card":card})
		belief_hook("onCardShown" if show else "onCardDismissed",[opening["definition"]["shrine_population_card"]["source_id"]])
		return
	if opening["phase"]=="shrine":
		var card: String=opening["shrine_level_card"]
		if show:
			if not card in state["progression"]["completed"]: preload("res://simulation/progression.gd").complete(state,card)
			events.append({"type":"campaign_show_card","card":card})
		shrine_hook("onCardShown" if show else "onCardDismissed",[card])
		return
	if show:
		events.append({"type":"campaign_show_card","card":opening["level_card"]})
		promised_hook("onCardShown",[opening["level_card"]])
	else: promised_hook("onCardDismissed",[opening["level_card"]])


func run_callback(name: String) -> void:
	var index := int(opening["checkpoint"])
	if index<0 or index>=opening["definition"]["route"].size(): return
	var entry: Dictionary = opening["entries"][index]
	if entry.has(name): vm.invoke(entry[name],[entry])
	elif name=="onArrived": next_checkpoint()
	elif name=="onBlocked": vm.hook("defaultFollowerBlockedBehaviour")
	if not vm.error.is_empty(): opening["error"]=vm.error


func next_checkpoint() -> void:
	if int(opening["checkpoint"])==opening["definition"]["route"].size()-1:
		vm.hook("clearInitialFollowersTarget")
		opening["phase"]="trailing"
		opening["camera_locked"]=true
		opening["globals"]["hackStopFollowerCheck"]=true
		opening["globals"]["onStartPlayTriggered"]=true
		vm.invoke(opening["definition"]["waiting_hooks"]["onListening"])
		events.append({"type":"campaign_stage","stage":"trailing"})
		return
	var starting: bool = opening["phase"]!="trail"
	clear_message(29)
	opening["globals"]["bIgnoreFollowerBlocked"]=false
	opening["globals"]["bIgnoreFollowerBlocked2"]=false
	opening["globals"]["blockedFollowerObj"]=null
	api("StopReaction",[opening["globals"].get("assessLandReaction")])
	opening["globals"]["assessLandReaction"]=null
	opening["checkpoint"]+=1
	opening["globals"]["currentBlockage"]=int(opening["checkpoint"])
	opening["persistent"]["TrailBlockage"]=int(opening["checkpoint"])
	opening["last_topology"]=-1
	opening["blocked"]=false
	opening["movement_paused"]=false
	for agent: Dictionary in followers(): agent["path"]=[]
	opening["revision"]+=1
	opening["phase"]="trail"
	if starting: vm.invoke(opening["definition"]["trail_hooks"]["onListening"])
	vm.hook("setInitialFollowersTarget")
	events.append({"type":"campaign_stage","stage":"trail","checkpoint":opening["checkpoint"]})


func followers() -> Array:
	return state["followers"].filter(func(agent: Dictionary) -> bool: return int(agent["id"]) in opening["protected"])


func next_promised_step() -> void:
	opening["phase"]="promised_land"
	opening["promised_step"]+=1
	if opening["promised_step"]==opening["definition"]["promised_steps"].size():
		opening["persistent"]["PromisedLandProgress"]=1337 # Original completeTutorial sentinel.
		return
	enter_promised_step()


func enter_promised_step() -> void:
	var step := int(opening["promised_step"])
	opening["persistent"]["PromisedLandProgress"]=step+1
	var available: bool=step<2 or (supports_first_plot(opening) or supports_expansion(opening) or supports_growth(opening) or supports_level_card(opening) or supports_first_chest(opening) or step==10 and opening["definition"].has("timeline_steps")) and opening["definition"].has("first_abode_model")
	opening["handoff"]={"tutorial":"PromisedLand","step":step,"available":available}
	events.append({"type":"campaign_handoff","tutorial":"PromisedLand","step":step,"available":available})
	if available:
		if step==9: world.initialize_authored_chests()
		if step==2: opening["globals"]["firstPlotPosition"]={"1":null,"2":null,"3":null}
		if step==3: opening["globals"]["sprog_unlocked"]=false
		if step==4: opening["globals"]["sprog_unlocked"]=true
		if step==6: opening["globals"]["sprog_unlocked"]=true
		if step==7: opening["globals"]["sprog_unlocked"]=false
		promised_hook("onListening",[])


static func rock_alive(data: Dictionary,cell: int) -> bool:
	return SourceRocks.alive(data,cell)


static func can_tap_rock(data: Dictionary,cell: int) -> bool:
	var story: Dictionary = data["opening"]
	var root := SourceRocks.canonical_cell(data,cell)
	var first: bool=story["phase"]=="promised_land" and story["promised_step"]==1 and story["activity_exception"]==ROCK_ID_BASE+root
	return (first or supports_expansion(story) or supports_growth(story) or supports_timeline_housing(story) or supports_shrine_housing(story) or supports_discovery(story)) and rock_alive(data,cell) and preload("res://simulation/influence.gd").contains(data,root%int(data["width"]),root/int(data["width"]))


func tap_rock(cell: int) -> void:
	cell=SourceRocks.canonical_cell(state,cell)
	var p: Dictionary = state["progression"]
	p["rock_taps"][str(cell)]=int(p["rock_taps"].get(str(cell),0))+1
	if int(p["rock_taps"][str(cell)])<int(opening["definition"]["object_config"]["taps_to_destroy_rock"]): return
	var rock := SourceRocks.at(state,cell)
	var reward:=0
	if not rock.is_empty():
		for dz in range(int(rock["size_z"])):
			for dx in range(int(rock["size_x"])):
				p["rock_taps"][str((int(rock["origin_z"])+dz)*int(state["width"])+int(rock["origin_x"])+dx)]=int(p["rock_taps"][str(cell)])
		var rules: Dictionary=opening["definition"].get("rock_belief",{})
		var unlocks:=preload("res://simulation/source_unlocks.gd")
		if not rules.is_empty() and unlocks.enabled(p,"TreeRockBelief"):
			var type:=str(int(rock["type"]))
			var base:=int(rules["amounts"].get(type,0))
			if base==0: base=rules["default_amount"]
			reward=int(base*float(rules["multipliers"].get(type,1)) if unlocks.enabled(p,rules["unlock"]) else base)
			state["belief"]+=reward
	p["rock_revision"]+=1
	var id := ROCK_ID_BASE+cell
	for key: String in opening["reaction_objects"].keys():
		if opening["reaction_objects"][key]==id: api("StopReaction",[int(key)])
	events.append({"type":"rock_removed","id":id,"cell":cell,"belief":reward})
	if supports_discovery(opening): discovery_hook("onRockDestroyed",[id])
	elif opening["phase"]=="shrine": shrine_hook("onRockDestroyed",[id])
	elif supports_timeline_housing(opening): timeline_hook("onRockDestroyed",[id])
	else: promised_hook("onRockDestroyed",[id])
	if not vm.error.is_empty(): opening["error"]=vm.error


func advance() -> void:
	for waiter: Dictionary in DayCycle.advance(opening["clock"],opening["definition"]["day_cycle"],0.1): vm.invoke(waiter["callback"],waiter["args"])
	var due: Array = opening["scheduled"].filter(func(item: Dictionary) -> bool: return int(item["tick"])<=int(state["tick"]))
	for item: Dictionary in due:
		if not opening["scheduled"].has(item): continue
		opening["scheduled"].erase(item)
		if item.get("action","")=="worship":
			opening["phase"]="worship"
			show_message(4)
			opening["scheduled"].append({"tick":int(state["tick"])+150,"action":"begin_trail"})
		elif item.get("action","")=="begin_trail":
			if opening["phase"]=="worship": acknowledge(4)
		else: vm.invoke(item["callback"],item["args"])
	if not vm.error.is_empty(): opening["error"]=vm.error
	if not opening["error"].is_empty(): return
	if opening.erase("resume_card_tutorial") and supports_level_card(opening) and opening["promised_step"]==8: promised_hook("onPostLoad",[])
	if opening.erase("resume_timeline") and supports_timeline(opening):
		opening["globals"]["onStartPlayTriggered"]=false
		opening["timeline_open"]=false
		for message: Dictionary in opening["messages"].duplicate():
			if int(message["id"])>=2000: clear_message(int(message["id"]))
		set_timeline_step(int(opening["timeline_step"]))
		opening["globals"]["onStartPlayTriggered"]=true
		timeline_hook("onStartPlay")
	if supports_timeline_housing(opening):
		if not opening["handoff"]["available"]: set_timeline_step(int(opening["timeline_step"]))
		advance_timeline_housing()
		return
	if opening["phase"]=="timeline" and opening["timeline_step"]==6 and has_shrine_tutorial(opening):
		start_shrine_tutorial()
		return
	if opening["phase"]=="shrine":
		if opening["shrine_step"]==5 and has_belief_tutorial(opening):
			set_belief_step(0)
			return
		if opening.erase("resume_shrine_card"):
			clear_message(3002)
			shrine_hook("onPostLoad")
		advance_shrine()
		return
	if supports_discovery(opening):
		advance_discovery()
		return
	if opening["phase"]=="belief":
		if opening["belief_step"]==4 and opening["definition"].has("discovery_site_id"):
			next_discovery_step()
			return
		if opening.erase("resume_belief"):
			opening["arrows"]={}
			if opening["belief_step"]==1:
				clear_message(4001)
				belief_hook("onPostLoad")
			else:
				clear_message(4002)
				clear_message(4003)
				belief_hook("onListening")
		return
	if opening["phase"]=="promised_land" and (supports_expansion(opening) and opening["promised_step"]==3 or supports_growth(opening) or supports_first_chest(opening) or opening["promised_step"]==10 and opening["definition"].has("timeline_steps")) and not opening["handoff"]["available"]: enter_promised_step()
	if supports_first_plot(opening):
		refresh_first_plot()
		if not state["homes"].is_empty():
			for event: Dictionary in world.advance_promised_abode(): promised_hook(event["hook"],[event["id"]])
	elif supports_expansion(opening) and opening["promised_step"]==5: advance_second_abode()
	if opening["phase"]=="promised_land" and int(opening["promised_step"]) in [5,6] and opening.has("released_builder"):
		world.advance_promised_breeding()
	if supports_growth(opening): advance_growth()
	if opening["phase"]=="promised_land":
		if not vm.error.is_empty(): opening["error"]=vm.error
		return
	var agents := followers()
	if agents.size()!=2: return
	if opening["phase"] in ["rescue","embrace","worship"]:
		var dry := true
		for agent: Dictionary in agents:
			if world.height_at(roundi(agent["x"]),roundi(agent["z"]))<=0: dry=false
		if not dry:
			opening["phase"]="rescue"
			opening["scheduled"]=[]
			opening["rescue_tick"]=-1
			show_message(2)
			show_message(3)
			for agent: Dictionary in agents: agent["state"]="drowning" if world.height_at(roundi(agent["x"]),roundi(agent["z"]))<=0 else "idle"
			return
		if opening["phase"]=="rescue":
			opening["phase"]="embrace"
			opening["rescue_tick"]=int(state["tick"])
			opening["messages"]=[]
			opening["scheduled"].append({"tick":int(state["tick"])+60,"action":"worship"})
			events.append({"type":"source_sound","event":"PLAYSOUND_OPENINGTUTORIAL_FOLLOWERSSAVED"})
		for agent: Dictionary in agents: agent["state"]="worshipping" if opening["phase"]=="worship" else ("hugging_take" if agent.get("female",false) else "hugging_give")
		return
	if not opening["phase"] in ["trail","trailing"] or opening["movement_paused"]: return
	if "StandStill" in opening["reactions"].values():
		for agent: Dictionary in agents: agent["state"]="idle"
		return
	var entry: Dictionary = opening["entries"][int(opening["checkpoint"])]
	var target := Vector2(entry["Target"]["x"],entry["Target"]["y"])
	var topology: int = state["terrain_revision"]
	var any_blocked := false
	var blocked_ids: Array = []
	for agent: Dictionary in agents:
		var position := Vector2(agent["x"],agent["z"])
		if position.distance_squared_to(target)<4:
			agent["state"]="idle"
			agent["path"]=[]
			continue
		if agent["path"].is_empty() and agent["state"]=="waiting" and opening["blocked"] and int(opening["last_topology"])==topology:
			agent["state"]="waiting"
			any_blocked=true
			blocked_ids.append(int(agent["id"]))
			continue
		if agent["path"].is_empty() or int(opening["last_topology"])!=topology:
			agent["path"]=route_to_target(agent,target)
		if agent["path"].is_empty():
			agent["state"]="waiting"
			any_blocked=true
			blocked_ids.append(int(agent["id"]))
			continue
		var cell := int(agent["path"][0])
		var destination := Vector2(cell%int(state["width"]),cell/int(state["width"]))
		var speed: float = float(world.follower_values(agent).get("RouteSpeed",opening["definition"]["constants"]["base_follower_speed"]))*float(opening["reaction_speed"])
		var next := position.move_toward(destination,speed*0.1)
		agent["x"]=next.x
		agent["z"]=next.y
		agent["state"]="walking"
		if next.distance_squared_to(destination)<0.000001: agent["path"].pop_front()
	var checkpoint := int(opening["checkpoint"])
	if opening["phase"]=="trail" and any_blocked and not opening["globals"]["bIgnoreFollowerBlocked"]:
		var leading: Variant = vm.hook("getLeadingFollowerId")
		if int(leading) in blocked_ids: vm.invoke(opening["definition"]["trail_hooks"]["onFollowerBlocked"],[leading])
	if not vm.error.is_empty(): opening["error"]=vm.error
	if checkpoint!=int(opening["checkpoint"]): return
	opening["blocked"]=any_blocked
	opening["last_topology"]=topology
	# The original one-second observer callback owns arrival, not render frames
	# or this movement loop. Its per-follower checkpoint history also gates catch-up.


func route_to_target(agent: Dictionary,target: Vector2) -> Array:
	var start := Vector2i(roundi(agent["x"]),roundi(agent["z"]))
	var candidates: Array[Vector2i] = []
	for dz in range(-2,3):
		for dx in range(-2,3):
			var cell := Vector2i(roundi(target.x)+dx,roundi(target.y)+dz)
			if Vector2(cell).distance_squared_to(target)<4 and world.height_at(cell.x,cell.y)>0: candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return Vector2(a).distance_squared_to(target)<Vector2(b).distance_squared_to(target))
	for cell: Vector2i in candidates:
		var path: Array = world._route(start,cell)
		if not path.is_empty(): return path
	# A blocked follower first approaches the obstacle; it must not stop at the
	# beginning of the route just because the destination is currently unreachable.
	var frontier: Array[Vector2i] = [start]
	var previous := {start:start}
	var best := start
	var cursor := 0
	while cursor<frontier.size():
		var current := frontier[cursor]
		cursor+=1
		if Vector2(current).distance_squared_to(target)<Vector2(best).distance_squared_to(target): best=current
		for direction: Vector2i in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
			var next := current+direction
			if previous.has(next) or world.height_at(next.x,next.y)<=0 or world._occupied(next.x,next.y): continue
			if absi(world.height_at(current.x,current.y)-world.height_at(next.x,next.y))>1: continue
			previous[next]=current
			frontier.append(next)
	var approach: Array = []
	while best!=start:
		approach.push_front(best.y*int(state["width"])+best.x)
		best=previous[best]
	return approach


func api(name: String,args: Array) -> Variant:
	match name:
		"advanceBlockage": next_checkpoint()
		"currentTutorialStep":
			if args[0]=="Leash" and opening.has("leash_step"):
				var steps: Array=opening["definition"]["discovery"]["Leash"]
				if int(opening["leash_step"])>=steps.size(): return null
				var hooks: Dictionary=steps[opening["leash_step"]]["hooks"].duplicate()
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="Discovery" and supports_discovery(opening):
				var hooks: Dictionary=opening["definition"]["discovery"]["Discovery"][opening["discovery_step"]]["hooks"].duplicate()
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="Belief" and opening["phase"]=="belief" and opening["belief_step"]<opening["definition"]["belief_steps"].size():
				var hooks: Dictionary=opening["definition"]["belief_steps"][int(opening["belief_step"])]["hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="ShrineOfExpansion" and opening["phase"]=="shrine" and opening["shrine_step"]<opening["definition"]["shrine_steps"].size():
				var hooks: Dictionary=opening["definition"]["shrine_steps"][int(opening["shrine_step"])]["hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="Timeline" and (supports_timeline(opening) or supports_timeline_housing(opening)):
				var hooks: Dictionary=opening["definition"]["timeline_steps"][int(opening["timeline_step"])]["hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="Trail" and opening["phase"] in ["trailing","arrival"]:
				var hooks: Dictionary = opening["definition"]["waiting_hooks" if opening["phase"]=="trailing" else "arrival_hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="PromisedLand" and opening["phase"]=="promised_land" and (int(opening["promised_step"])<2 or supports_first_plot(opening) or supports_expansion(opening) or supports_growth(opening) or supports_first_chest(opening)):
				var hooks: Dictionary = opening["definition"]["promised_steps"][int(opening["promised_step"])]["hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			opening["error"]="Unsupported campaign tutorial stage query."
		"nextTrailStep":
			if opening["phase"]=="trailing":
				opening["phase"]="arrival"
				events.append({"type":"campaign_stage","stage":"arrival"})
				vm.invoke(opening["definition"]["arrival_hooks"]["onListening"])
			elif opening["phase"]=="arrival": opening["phase"]="trail_complete"
			else: opening["error"]="Unsupported campaign trail-stage transition."
		"nextPromisedLandStep": next_promised_step()
		"nextTimelineStep": set_timeline_step(int(opening.get("timeline_step",-1))+1)
		"nextShrineOfExpansionStep": set_shrine_step(int(opening["shrine_step"])+1)
		"nextBeliefStep": set_belief_step(int(opening["belief_step"])+1)
		"nextFarmingStep": set_farming_step(int(opening["farming_step"])+1)
		"nextSuperFastStep": set_superfast_step(int(opening["superfast_step"])+1)
		"nextDiscoveryStep": next_discovery_step()
		"nextLeashStep":
			opening["leash_step"]+=1
			opening["persistent"]["LeashProgress"]=opening["leash_step"]+1 if opening["leash_step"]<6 else 1337
			leash_hook("onListening")
		"nextEventsStep":
			opening["events_step"]=int(opening.get("events_step",-1))+1
			var step: int=opening["events_step"]
			opening["persistent"]["EventsProgress"]=step+1 if step==0 else 1337
			opening["handoff"]={"tutorial":"Events","step":step,"available":step==0}
			events.append({"type":"campaign_handoff","tutorial":"Events","step":step,"available":step==0})
			dock_event_hook("onListening")
		"IsEventComplete": return int(args[0])==1 and opening["persistent"].get("EventVoyageProgress",0)>=5
		"tryPushFacebookStickyTab": pass
		"LeashGetReleasePos":
			return {"multiple":[args[0]["x"],args[0]["z"]]}
		"WhatCanBeSeenFromPoint":
			var site: Dictionary=world.source_dock_site()
			if not site.is_empty() and world.source_shrine_bounds(site).has_point(Vector2i(roundi(args[0]),roundi(args[1]))) and not site.get("repaired",false):
				return site["id"]
		"ClearObjectSelection":
			opening["globals"].erase("selectedWorldObject")
			events.append({"type":"campaign_clear_selection"})
		"SelectMission":
			if int(args[0])==3 and opening.get("leash_step")==1:
				opening["leash_mission_pending"]=true
				events.append({"type":"campaign_select_mission","mission":3})
		"nextPitOfDoomStep":
			var step:=mini(2,int(opening["pit_step"])+1)
			opening["pit_step"]=step
			opening["persistent"]["PitOfDoomProgress"]=2 if step==1 else 1337
			opening.erase("pit_card_open")
			if step==1 or opening.get("handoff",{}).get("tutorial")=="PitOfDoom":
				opening["handoff"]={"tutorial":"PitOfDoom","step":step,"available":step==1 and opening["definition"].has("pit_sacrifice")}
				events.append({"type":"campaign_handoff"}.merged(opening["handoff"]))
		"IsPointInAreaOfInfluence": return world.can_act_at(float(args[0]),float(args[1]))
		"AbodeInRadius": return api("GetFirstAbodeInRadius",args)!=null
		"HashString": return args[0]
		"HashEquals": return args[0]==args[1]
		"GetFirstTempleInRadius":
			var center := Vector2(args[0],args[1])
			var best := float(args[2])*float(args[2])
			var nearest: Variant=null
			for site: Dictionary in state["progression"]["shrines"]:
				var distance := center.distance_squared_to(Vector2(site["x"],site["z"]))
				if distance<=best:
					best=distance
					nearest=site["id"]
			return nearest
		"TemplePos","IsTempleComplete":
			if name=="TemplePos" and (args[0] is int or args[0] is float):
				var settlement:=preload("res://simulation/campaign_economy.gd").settlement(state,int(args[0]))
				if not settlement.is_empty():
					var x: int=settlement["x"]
					var z: int=settlement["z"]
					return {"multiple":[x,z,preload("res://simulation/source_terrain.gd").surface_height(world.source_raw_height_at(x,z))]}
			elif args[0] is String:
				for site: Dictionary in state["progression"]["shrines"]:
					if site["id"]!=args[0]: continue
					if name=="IsTempleComplete": return site["complete"] or site.get("repaired",false)
					return {"multiple":[site["x"],site["z"],preload("res://simulation/source_terrain.gd").surface_height(world.source_shrine_layer(site))]}
		"FindHouseInterestedInObject":
			if str(args[0])==world.source_shrine_site().get("id",""): return world.source_shrine_builder_home()
		"GetFollowerTarget":
			for follower: Dictionary in state["followers"]:
				if follower["id"]==args[0]: return follower.get("repair_site")
		"setTutorialStep":
			if args[0]=="Timeline": set_timeline_step(maxi(0,int(args[1])-1))
			elif args[0]=="Farming": set_farming_step(maxi(0,int(args[1])-1))
			else: opening["error"]="Unsupported campaign tutorial reset."
		"LockTimelineInput": opening["timeline_input_lock"]=int(args[0])
		"PopulationCount": return state["followers"].size()
		"AbodeType":
			for home: Dictionary in state["homes"]:
				if home["id"]!=args[0]: continue
				if home.get("kind","")=="farm": return opening["globals"]["FIELD_TYPE"]
				if home.get("script_abode_type",0)!=0: return home["script_abode_type"]
				return null
		"AbodePos":
			for home: Dictionary in state["homes"]:
				if home["id"]==args[0]: return {"multiple":[home["anchor_x"],home["anchor_z"]]}
			if args[0] is int or args[0] is float:
				var item:=preload("res://simulation/campaign_economy.gd").settlement(state,int(args[0]))
				if not item.is_empty(): return {"multiple":[item["x"],item["z"]]}
		"AbodeIsFarm":
			for home: Dictionary in state["homes"]:
				if home["id"]==args[0]: return home.get("kind","")=="farm"
			return false
		"FollowerJob":
			for follower: Dictionary in state["followers"]:
				if follower["id"]==args[0]: return opening["globals"]["JOB_FARMER"] if follower.get("profession")=="farmer" else opening["globals"]["JOB_BUILDER"]
		"CenterScreen":
			var start: Dictionary=state["camera_start"]
			var center: Array=opening["observer"].get("center",[start["x"],start["z"]])
			return {"multiple":[center[0],center[1],preload("res://simulation/source_terrain.gd").surface_height(world.source_raw_height_at(center[0],center[1]))]}
		"AbodeFillBelief":
			for home: Dictionary in state["homes"]:
				if home["id"]==args[0]: home["stored"]=maxi(int(home["stored"]),int(home["max_belief"]))
		"AbodeFillFood":
			for home: Dictionary in state["homes"]:
				if home["id"]==args[0] and home.get("kind","")=="farm": home["harvest_accumulator"]=float(home["max_belief"])
		"Belief": return state["belief"]
		"SetBelief": state["belief"]=int(args[0])
		"GetHeightAtPoint": return preload("res://simulation/source_terrain.gd").surface_height(world.source_raw_height_at(float(args[0]),float(args[1])))
		"GetSculptLayers": return {"multiple":args[0]["layers"]}
		"WorldPosContextToXYZ": return {"multiple":args[0]["position"]}
		"min": return minf(float(args[0]),float(args[1]))
		"max": return maxf(float(args[0]),float(args[1]))
		"DisableHUDElement","EnableHUDElement":
			if args[0]==opening["globals"].get("en_HudComponent",{}).get("Belief",-1): opening["belief_hud_hidden"]=name=="DisableHUDElement"
		"CardComplete","CardOwned": return preload("res://simulation/source_unlocks.gd").owns(state["progression"],str(args[0]),"completed" if name=="CardComplete" else "discovered")
		"GetFirstPlotInRadius":
			var plot := plot_in_radius(state,Vector2(args[0],args[1]),float(args[2]))
			return null if plot.is_empty() else PLOT_HANDLE+int(plot["id"])
		"PlotInRadius": return not plot_in_radius(state,Vector2(args[0],args[1]),float(args[2])).is_empty()
		"ProcessPlotsInRadius":
			var registry: Dictionary=state.get("source_plots",{})
			for id: int in registry.get("active",[]):
				var plot: Dictionary=registry["slots"][id]
				if preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(args[0],args[1]),float(args[2])): vm.invoke(args[3],[PLOT_HANDLE+id])
		"PlotPos":
			var plot := first_plot_in_range(state,args[0])
			if plot.is_empty(): return {"multiple":[]}
			var half := float(plot["size"])*0.5
			return {"multiple":[float(plot["x"])+half,float(plot["z"])+half,plot["height"]]}
		"SelectPLOT":
			var plot := first_plot_in_range(state,args[0])
			if plot.is_empty(): opening.erase("selected_plot")
			else:
				var half := float(plot["size"])*0.5
				opening["selected_plot"]={"handle":args[0],"x":float(plot["x"])+half,"z":float(plot["z"])+half,"size":int(plot["size"])}
		"GetFirstAbodeInRadius":
			var best: Variant=null
			var distance := INF
			for home: Dictionary in state["homes"]:
				if home.get("kind","")!="": continue
				var range_ := Vector2(home["anchor_x"],home["anchor_z"]).distance_to(Vector2(args[0],args[1]))
				if range_<=float(args[2])+float(home["span"])*0.5 and range_<distance: best=home["id"]; distance=range_
			return best
		"ProcessAbodesInRadius":
			if not (args[0] is float or args[0] is int) or not (args[1] is float or args[1] is int):
				opening["error"]="The authored abode query needs a map position."
				return null
			for home: Dictionary in state["homes"]:
				if not home.get("kind","") in ["","farm"]: continue
				if Vector2(home["anchor_x"],home["anchor_z"]).distance_to(Vector2(args[0],args[1]))<=float(args[2]): vm.invoke(args[3],[home["id"]])
		"ProcessBiggestClumpOfAbodesOfType":
			var houses: Array=[]
			for home: Dictionary in state["homes"]:
				if home.get("kind","")!="": continue
				houses.append({"id":home["id"],"x":home["anchor_x"],"z":home["anchor_z"],"type":home["script_abode_type"],"state":int(home["progress"]>=home["build_ticks"])})
			var include: bool=bool(args[3]) if args.size()>3 and args[3] is bool else bool(opening["definition"]["belief_rules"]["include_unfinished_default"])
			var ids := preload("res://simulation/source_abode_clumps.gd").biggest(houses,int(args[0]),float(args[1]),opening["definition"]["belief_rules"],include)
			for id: int in ids: vm.invoke(args[2],[id])
		"AbodeCanSprog":
			if args[0]==null: return false
			if opening["phase"]=="shrine" or supports_discovery(opening): return world.inspect({"type":"sprog","home_id":args[0]})["ok"]
			return opening["globals"].get("sprog_unlocked",false) and not release_candidate(state,int(args[0])).is_empty()
		"AbodeState","AbodeIsFull","AbodeBreedTime","AbodeLockBreed":
			for home: Dictionary in state["homes"]:
				if home["id"]!=args[0]: continue
				match name:
					"AbodeState": return int(home["progress"]>=home["build_ticks"])
					"AbodeIsFull": return home["residents"]>=home["capacity"]
					"AbodeBreedTime": return float(home["birth_ticks"]-home.get("breed_ticks",0))*0.1
					"AbodeLockBreed": home["breed_locked"]=bool(args[1]); return null
			return false
		"UnlockActivity","LockActivity":
			if int(args[0])==2: opening["globals"]["sprog_unlocked"]=name=="UnlockActivity"
		"GetFirstFollowerInRadius":
			var best: Variant=null
			var distance := float(args[2])
			for agent: Dictionary in state["followers"]:
				if agent["state"]=="indoors": continue
				var range_ := Vector2(agent["x"],agent["z"]).distance_to(Vector2(args[0],args[1]))
				if range_<=distance: best=agent["id"]; distance=range_
			return best
		"FollowerInRadius":
			for agent: Dictionary in followers():
				if agent["state"]!="indoors" and Vector2(agent["x"],agent["z"]).distance_to(Vector2(args[0],args[1]))<=float(args[2]): return true
			return false
		"ShowUI","ShowUIWithCb":
			if args.size()>1 and MESSAGE_GROUPS.has(args[0]): show_message(int(args[1])+int(MESSAGE_GROUPS[args[0]]),args[2] if args.size()>2 else null)
		"ClearUI":
			if args.size()>1 and MESSAGE_GROUPS.has(args[0]): clear_message(int(args[1])+int(MESSAGE_GROUPS[args[0]]))
		"HideTable","UnhideTable":
			if not opening.has("hidden_tables"): opening["hidden_tables"]=[]
			if name=="HideTable" and not args[0] in opening["hidden_tables"]: opening["hidden_tables"].append(args[0])
			elif name=="UnhideTable": opening["hidden_tables"].erase(args[0])
		"ArrowCreate":
			var id: int=opening.get("next_arrow",1)
			opening["next_arrow"]=id+1
			if not opening.has("arrows"): opening["arrows"]={}
			opening["arrows"][str(id)]={"parameters":args.duplicate(true),"objects":[]}
			return id
		"ArrowAddObject","ArrowRemoveObject":
			var arrow: Dictionary=opening.get("arrows",{}).get(str(int(args[0])),{})
			if not arrow.is_empty():
				if name=="ArrowAddObject": arrow["objects"].append(args[1])
				else: arrow["objects"].erase(args[1])
		"ArrowDestroy": opening.get("arrows",{}).erase(str(int(args[0])))
		"After","NonPausingAfter":
			opening["scheduled"].append({"tick":int(state["tick"])+maxi(1,roundi(float(args[0])*10)),"callback":args[1],"args":args.slice(2)})
		"Console": pass
		"ForceSaveGame": events.append({"type":"campaign_autosave"})
		"PlaySound": events.append({"type":"source_sound","event":str(args[0])})
		"Sunrise","Midday","Sunset","Midnight": return opening["definition"]["day_cycle"]["functions"][name]["value"]
		"TimeOfDay":
			if not args.is_empty(): opening["clock"]["time"]=fposmod(float(args[0]),float(opening["definition"]["day_cycle"]["period"]))
			return float(opening["clock"]["time"])/float(opening["definition"]["day_cycle"]["period"])
		"Config":
			if args.size()==2 and args[0]=="TimeOfDaySpeed": opening["clock"]["speed"]=float(args[1])
			else: opening["error"]="Unsupported campaign config operation."
		"AtTimeOfDay": opening["clock"]["waiters"].append({"time":fposmod(float(args[0]),float(opening["definition"]["day_cycle"]["period"])),"callback":args[1],"args":args.slice(2)})
		"Unlock":
			if not state["progression"].has("script_unlocks"): state["progression"]["script_unlocks"]={}
			state["progression"]["script_unlocks"][str(args[0])]=true
		"TriggerVFX":
			var id := int(opening["next_effect"])
			opening["next_effect"]+=1
			opening["effects"][str(id)]={"name":str(args[0]),"args":args.slice(1).duplicate(true)}
			events.append({"type":"campaign_vfx_start","id":id,"name":str(args[0]),"args":args.slice(1).duplicate(true)})
			return id
		"StopVFXInstance":
			opening["effects"].erase(str(int(args[0])))
			events.append({"type":"campaign_vfx_stop","id":int(args[0])})
		"ClearAlertByID":
			if not args.is_empty() and args[0]!=null: opening["error"]="Unsupported campaign alert handle."
		"CreateReaction":
			var id := int(opening["next_reaction"])
			opening["next_reaction"]+=1
			opening["reactions"][str(id)]=str(args[0])
			if args[0]=="TutorialGoTo":
				opening["movement_paused"]=false
				opening["blocked"]=false
				opening["last_topology"]=-1
				for agent: Dictionary in followers(): agent["path"]=[]
			else:
				for agent: Dictionary in followers():
					if agent["state"]!="indoors": agent["state"]="scared" if args[0]=="TutorialAtPromisedLandScared" else ("idle" if args[0]=="StandStill" else "assessing")
			return id
		"AttachReaction":
			var id := int(api("CreateReaction",[args[0]]))
			opening["reaction_objects"][str(id)]=args[1]
			return id
		"StopReaction":
			if not args.is_empty() and args[0]!=null:
				var key := str(int(args[0]))
				if opening["reactions"].get(key)=="TutorialGoTo": opening["movement_paused"]=true
				opening["reactions"].erase(key)
				opening["reaction_objects"].erase(key)
		"GetFirstRockInRadius":
			var center := Vector2(args[0],args[1])
			var radius := float(args[2])
			var best := radius*radius+0.000001
			var result: Variant = null
			for rock: Dictionary in SourceRocks.entries(state):
				var cell := SourceRocks.cell(state,rock)
				var distance := center.distance_squared_to(Vector2(rock["x"],rock["z"]))
				if distance<best and rock_alive(state,cell): best=distance; result=ROCK_ID_BASE+cell
			for z in range(maxi(0,floori(center.y-radius)),mini(int(state["width"]),ceili(center.y+radius)+1)):
				for x in range(maxi(0,floori(center.x-radius)),mini(int(state["width"]),ceili(center.x+radius)+1)):
					var cell := z*int(state["width"])+x
					if not SourceRocks.at(state,cell).is_empty(): continue
					var distance := center.distance_squared_to(Vector2(x,z))
					if distance<best and rock_alive(state,cell): best=distance; result=ROCK_ID_BASE+cell
			return result
		"SetActivityLockException": opening["activity_exception"]=args[0]
		"ClearActivityLockException": opening["activity_exception"]=null
		"SetTreeRegen": opening["tree_regeneration"]=bool(args[0])
		"DisplayAction":
			var id := int(opening["next_action"])
			opening["next_action"]+=1
			opening["actions"][str(id)]=args.duplicate(true)
			events.append({"type":"campaign_action_start","id":id,"args":args.duplicate(true)})
			return id
		"ClearAction":
			opening["actions"].erase(str(int(args[0])))
			events.append({"type":"campaign_action_stop","id":int(args[0])})
		"Persist":
			if args.size()>1: opening["persistent"][str(args[0])]=args[1]
			return opening["persistent"].get(str(args[0]),0)
		"FollowerPos":
			for agent: Dictionary in followers():
				if int(agent["id"])==int(args[0]): return {"multiple":[agent["x"],agent["z"]]}
			return {"multiple":[null,null]}
		"ProcessFollowersInRadius":
			var center := Vector2(args[0],args[1])
			var agents: Array=state["followers"] if supports_growth(opening) else followers()
			for agent: Dictionary in agents:
				if agent["state"]=="indoors" and int(agent["id"])!=opening["globals"].get("entering_follower",-1): continue
				if Vector2(agent["x"],agent["z"]).distance_squared_to(center)<=float(args[2])*float(args[2]): vm.invoke(args[3],[int(agent["id"])])
		"table.insert":
			var table: Dictionary = args[0]
			table[str(Interpreter.table_length(table)+1)]=args[1]
		"table.sort":
			var values: Array=[]
			for index in range(1,Interpreter.table_length(args[0])+1): values.append(Interpreter.table_get(args[0],index))
			values.sort_custom(func(a: Variant,b: Variant) -> bool: return Interpreter.truth(vm.invoke(args[1],[a,b])))
			for index in range(values.size()): args[0][Interpreter.table_key(args[0],index+1)]=values[index]
		"Vec2DistanceSq": return Vector2(float(args[0])-float(args[2]),float(args[1])-float(args[3])).length_squared()
		"Table":
			if args.size() in [3,4] and args[0]=="reactions0" and args[1] in ["AgressiveSpeedMult","PassiveSpeedMult"]:
				if args.size()==3: return opening["reaction_speed"]
				opening["reaction_speed"]=float(args[3])
			else: opening["error"]="Unsupported campaign table operation."
		"IsValidPath":
			var start := Vector2i(roundi(float(args[0])),roundi(float(args[1])))
			var target := Vector2i(roundi(float(args[2])),roundi(float(args[3])))
			return world.height_at(target.x,target.y)>0 and (start==target or not world._route(start,target).is_empty())
		"IsPointOnScreen": return point_visible(float(args[0]),float(args[1]),float(args[2]))
		"GetStepAtPoint":
			return world.source_step_at(float(args[0]),float(args[1]))
		"TeleportFollower":
			for agent: Dictionary in followers():
				if int(agent["id"])==int(args[0]):
					agent["x"]=float(args[1]); agent["z"]=float(args[2]); agent["path"]=[]
					events.append({"type":"campaign_catch_up","cause":"trailing_path_repair" if opening["phase"]=="trailing" else "offscreen","id":int(agent["id"]),"x":agent["x"],"z":agent["z"]})
		"TriggerTipGameObject":
			var id := int(opening["next_tip"])
			opening["next_tip"]+=1
			opening["tips"][str(id)]={"follower":int(args[0]),"key":str(args[1])}
			return id
		"TriggerTip3D":
			var id: int=opening["next_tip"]
			opening["next_tip"]+=1
			opening["tips"][str(id)]={"position":[args[0],args[1],args[2]],"key":str(args[3])}
			return id
		"ClearTip":
			if not args.is_empty() and args[0]!=null: opening["tips"].erase(str(int(args[0])))
		"SetCamera","LockCamera","UnlockCamera","UnlockZooming":
			if name in ["LockCamera","UnlockCamera"]: opening["camera_locked"]=name=="LockCamera"
			elif name=="UnlockZooming": opening["zoom_locked"]=false
			events.append({"type":"campaign_camera","action":name,"args":args.duplicate(true)})
		"Console","string.format": pass # Source diagnostics, not game decisions.
		_:
			opening["error"]="Unsupported campaign callback: "+name
	return null


func observe(command: Dictionary) -> void:
	opening["observer"]={"mode":"orthographic","projection":command["projection"].duplicate()}
	if command.has("center"): opening["observer"]["center"]=command["center"].duplicate()
	if command.get("ended",false) and opening["phase"]=="trail":
		vm.hook("cameraEndUpdate")
		if not vm.error.is_empty(): opening["error"]=vm.error
	elif command.get("ended",false) and supports_first_chest(opening):
		promised_hook("onCameraPanEnd",[])
		if not vm.error.is_empty(): opening["error"]=vm.error


func sculpt_started(context: Dictionary) -> void:
	if opening["phase"]=="belief": vm.hook("onSculptStarted",[context])
	if not vm.error.is_empty(): opening["error"]=vm.error


func sculpt_completed(context: Dictionary={}) -> void:
	if opening["phase"]=="trail": vm.invoke(opening["definition"]["trail_hooks"]["onSculptComplete"])
	elif supports_growth(opening): promised_hook("onSculptComplete",[])
	elif supports_discovery(opening): discovery_hook("onSculptComplete",[context])
	elif opening["phase"]=="belief":
		vm.hook("onSculptComplete",[context])
		belief_hook("onSculptComplete",[context])
	else:
		clear_message(1)
		clear_message(3)
	if not vm.error.is_empty(): opening["error"]=vm.error


func sculpt_failed(context: Dictionary={}) -> void:
	if opening["phase"]=="trailing": vm.invoke(opening["definition"]["waiting_hooks"]["onSculptFailed"])
	elif opening["phase"]=="belief" and not context.is_empty():
		vm.hook("onSculptFailed",[context])
		belief_hook("onSculptFailed",[context])
	if not vm.error.is_empty(): opening["error"]=vm.error


func point_visible(x: float,z: float,cutoff: float) -> bool:
	# Headless self-play explicitly uses an all-seeing observer until a replay or
	# presentation submits its orthographic projection. No renderer is queried.
	if opening["observer"]["mode"]=="all": return true
	var projection: Array = opening["observer"]["projection"]
	var height: float = world.height_at(roundi(x),roundi(z))*0.3
	var u: float = projection[0]*x+projection[1]*z+projection[2]*height+projection[3]
	var v: float = projection[4]*x+projection[5]*z+projection[6]*height+projection[7]
	return u>=cutoff and u<=1-cutoff and v>=cutoff and v<=1-cutoff


static func valid_observation(command: Dictionary) -> bool:
	if not command.get("projection") is Array or command["projection"].size()!=8 or not command.get("ended",false) is bool: return false
	for value: Variant in command["projection"]:
		if not (value is float or value is int) or not is_finite(value) or absf(value)>1000000: return false
	if command.has("center"):
		if not command["center"] is Array or command["center"].size()!=2: return false
		for value: Variant in command["center"]:
			if not (value is float or value is int) or not is_finite(value) or value<0 or value>1023: return false
	return true


static func valid(data: Variant) -> bool:
	if data is Dictionary and not preload("res://simulation/authored_chests.gd").valid(data): return false
	if not data is Dictionary: return false
	if not data.get("definition") is Dictionary or not data.get("globals") is Dictionary or not data.get("persistent") is Dictionary: return false
	if not data.get("protected") is Array or not data.get("messages") is Array or not data.get("scheduled") is Array: return false
	var definition: Dictionary = data["definition"]
	var rain:=preload("res://simulation/campaign_rain.gd")
	if definition.has("rain") and not rain.valid_rules(definition["rain"]): return false
	if data.has("rain_cast") and (not definition.has("rain") or not rain.valid_point(data["rain_cast"],1024)): return false
	if definition.has("fountain") and not preload("res://simulation/campaign_fountain.gd").valid_rules(definition["fountain"]): return false
	if definition.has("cliff_sculpt") and not preload("res://simulation/campaign_cliff_sculpt.gd").valid_rules(definition["cliff_sculpt"]): return false
	if definition.has("belief_collector") and not preload("res://simulation/campaign_belief_collector.gd").valid_rules(definition["belief_collector"]): return false
	if definition.has("rock_belief"):
		var rocks: Variant=definition["rock_belief"]
		if not rocks is Dictionary or rocks.get("card")!="Card_RockBelief_1" or rocks.get("unlock")!="RockBelief_1": return false
		if not integer(rocks.get("population"),1,100000) or not integer(rocks.get("default_amount"),1,1000000): return false
		if not rocks.get("amounts") is Dictionary or not rocks.get("multipliers") is Dictionary: return false
		for type in range(20,27):
			if not integer(rocks["amounts"].get(str(type)),0,1000000) or not integer(rocks["multipliers"].get(str(type)),1,1000): return false
	for key: String in ["fountain_card_open","resume_fountain_card","happiness_hint_shown","fountain_tutorial_done"]:
		if not data.get(key,false) is bool: return false
	if data.has("first_fountain") and not integer(data["first_fountain"],1,1000000000000): return false
	if data.has("fountain_hint_until") and not integer(data["fountain_hint_until"],0,1000000000000): return false
	if not SourceRocks.valid(definition): return false
	if definition.has("plot_environment") and not preload("res://simulation/source_biomes.gd").valid(definition["plot_environment"]): return false
	if definition.has("house_selection") and not preload("res://simulation/source_houses.gd").valid(definition["house_selection"]): return false
	if definition.has("house_base_stats") and not preload("res://simulation/source_house_base_stats.gd").valid(definition["house_base_stats"]): return false
	if definition.has("house_environment") and not preload("res://simulation/source_house_environment.gd").valid(definition["house_environment"]): return false
	if definition.has("house_surroundings_rules") and not preload("res://simulation/source_house_surroundings.gd").valid_rules(definition["house_surroundings_rules"]): return false
	if definition.has("temple_effects") and not preload("res://simulation/source_temple_effects.gd").valid_content(definition["temple_effects"]): return false
	if definition.has("build_candidate_values"):
		if not preload("res://simulation/source_build_candidates.gd").valid_values(definition["build_candidate_values"]): return false
		for row: Dictionary in definition.get("house_selection",[]):
			if not definition["build_candidate_values"].has(row["id"]): return false
	if definition.has("rock_motion_config") and not preload("res://simulation/source_rock_motion.gd").valid_config(definition["rock_motion_config"]): return false
	if definition.has("tree_response_config") and not preload("res://simulation/source_tree_response.gd").valid_config(definition["tree_response_config"]): return false
	if definition.has("plot_resize_rules") and not preload("res://simulation/source_plot_resize.gd").valid_rules(definition["plot_resize_rules"]): return false
	if definition.has("plot_conversion_rules") and not preload("res://simulation/source_plot_conversion.gd").valid_rules(definition["plot_conversion_rules"]): return false
	if definition.has("build_start_rules") and not preload("res://simulation/source_build_start.gd").valid_rules(definition["build_start_rules"]): return false
	if definition.has("plot_cost") and not preload("res://simulation/source_plot_cost.gd").valid_definition(definition): return false
	if definition.has("house_constructor"):
		if not preload("res://simulation/source_house_constructor.gd").valid_content(definition["house_constructor"]): return false
	if definition.has("house_pool_rules"):
		if not definition["house_pool_rules"] is Dictionary or not preload("res://simulation/source_plot_schedule.gd").integer_between(definition["house_pool_rules"].get("capacity"),1,65535): return false
	if definition.has("house_terrain_rules") and not preload("res://simulation/source_house_terrain_frame.gd").valid_rules(definition["house_terrain_rules"]): return false
	if definition.has("progression_modifier_rules") and not preload("res://simulation/source_progression_modifiers.gd").valid_rules(definition["progression_modifier_rules"]): return false
	if definition.has("target_reference_rules") and not preload("res://simulation/source_target_references.gd").valid_rules(definition["target_reference_rules"]): return false
	if definition.has("action_sequences") and not preload("res://simulation/source_action_sequence.gd").valid_content(definition["action_sequences"]): return false
	if definition.has("action_entry") and not preload("res://simulation/source_action_entry.gd").valid_content(definition["action_entry"]): return false
	if definition.has("action_controller") and not preload("res://simulation/source_action_controller.gd").valid_content(definition["action_controller"]): return false
	if definition.has("plot_field") and not preload("res://simulation/source_plot_field.gd").valid(definition["plot_field"]): return false
	if definition.has("influence_rules") and not preload("res://simulation/source_influence.gd").valid_rules(definition["influence_rules"]): return false
	if not definition.get("route") is Array or definition["route"].size()!=14 or not definition.get("program") is Dictionary or not definition.get("messages") is Dictionary: return false
	if not definition.get("constants") is Dictionary or not definition.get("program",{}).get("functions") is Dictionary: return false
	if not definition.get("day_cycle") is Dictionary or not DayCycle.valid(data.get("clock"),definition["day_cycle"]): return false
	if not definition.get("arrival_hooks") is Dictionary or not data.get("effects") is Dictionary or not integer(data.get("next_effect"),1,1000000000000): return false
	if not definition.get("promised_steps") is Array or definition["promised_steps"].size()!=11 or not definition.get("object_config") is Dictionary: return false
	if not integer(data.get("promised_step"),-1,11) or not integer(data.get("next_action"),1,1000000000000): return false
	if data.get("phase")=="timeline":
		if not definition.get("timeline_steps") is Array or definition["timeline_steps"].size()!=6 or not integer(data.get("timeline_step"),0,6): return false
		if not data.get("timeline_open",false) is bool or not integer(data.get("timeline_input_lock",0),0,3): return false
	if data.get("phase")=="shrine":
		if not has_shrine_tutorial(data) or not definition["shrine_steps"] is Array or definition["shrine_steps"].size()!=5 or not integer(data.get("shrine_step"),0,5): return false
	if data.get("phase")=="belief":
		if not has_belief_tutorial(data) or not integer(data.get("belief_step"),0,4): return false
		if not data.get("hidden_tables",[]) is Array or not data.get("arrows",{}) is Dictionary: return false
		if not integer(data.get("next_arrow",1),1,1000000000000): return false
		for arrow: Variant in data.get("arrows",{}).values():
			if not arrow is Dictionary or not arrow.get("objects") is Array or not arrow.get("parameters") is Array: return false
	if supports_discovery(data):
		if not definition.get("discovery") is Dictionary or not definition.get("discovery_site_id") is String: return false
		for group: String in ["Discovery","PitOfDoom"]:
			var steps: Variant=definition["discovery"].get(group)
			if not steps is Array or steps.size()!=(3 if group=="Discovery" else 2): return false
			for step: Variant in steps:
				if not step is Dictionary or not step.get("hooks") is Dictionary: return false
		if not integer(data.get("discovery_step"),0,2) or not integer(data.get("pit_step"),0,2): return false
		if definition.has("pit_sacrifice") and not preload("res://simulation/campaign_pit.gd").valid_rules(definition["pit_sacrifice"]): return false
		if data.has("pit_totals"):
			var totals: Variant=data["pit_totals"]
			if not totals is Dictionary or not integer(totals.get("followers"),0,1000000000): return false
			if not integer(totals.get("gems"),int(totals["followers"]),5*int(totals["followers"])): return false
		if not data.get("pit_card_open",false) is bool: return false
		if data.has("leash_step"):
			if not definition.get("leash_population_card") is Dictionary or not definition["discovery"].get("Leash") is Array or definition["discovery"]["Leash"].size()!=6: return false
			if not integer(data["leash_step"],0,6) or not data.get("leash_mission_pending",false) is bool or not data.get("dock_card_open",false) is bool: return false
			if data["leash_step"]>2 and not definition.get("dock_site_id") is String: return false
			if data.get("leash_level_card")!=definition["leash_population_card"].get("id"): return false
		if data.has("events_step") and (not integer(data["events_step"],0,1) or not definition["discovery"].get("Events") is Array): return false
		if data.has("farming_step"):
			var steps: Variant=definition["discovery"].get("Farming")
			if not steps is Array or steps.size()!=5 or not integer(data["farming_step"],0,5) or not data.get("farming_placing",false) is bool: return false
			if data.has("farming_preview"):
				var draft: Variant=data["farming_preview"]
				if not draft is Dictionary or not integer(draft.get("x"),0,1023) or not integer(draft.get("z"),0,1023) or not draft.get("members") is Array: return false
				if draft["members"].is_empty() or not integer(draft.get("capacity"),1,1000000): return false
				for id: Variant in draft["members"]:
					if not integer(id,1,1000000000000): return false
		if data.has("superfast_step"):
			var steps: Variant=definition["discovery"].get("SuperFast")
			if not steps is Array or steps.size()!=5 or not integer(data["superfast_step"],0,5): return false
	if not data.get("actions") is Dictionary or not data.get("reaction_objects") is Dictionary or not data.get("tree_regeneration") is bool: return false
	if data.has("selected_plot"):
		var plot: Variant=data["selected_plot"]
		if not plot is Dictionary or not integer(plot.get("handle"),PLOT_HANDLE,PLOT_HANDLE+1023) or not integer(plot.get("size"),1,12): return false
		for axis: String in ["x","z"]:
			var point: Variant=plot.get(axis)
			if not (point is int or point is float) or not is_finite(float(point)) or point<0 or point>=1024: return false
	if data.get("activity_exception")!=null and not integer(data["activity_exception"],ROCK_ID_BASE,ROCK_ID_BASE+1024*1024-1): return false
	if not definition.get("helpers") is Dictionary or not definition.get("trail_hooks") is Dictionary or not definition.get("waiting_hooks") is Dictionary or not data.get("globals",{}).get("initialFollowers") is Dictionary: return false
	for key: String in ["reactions","tips","observer"]:
		if not data.get(key) is Dictionary: return false
	if not data["observer"].get("mode") in ["all","orthographic"]: return false
	if data["observer"]["mode"]=="orthographic" and not valid_observation(data["observer"]): return false
	for key: String in ["next_reaction","next_tip"]:
		if not integer(data.get(key),1,1000000000000): return false
	for key: String in ["camera_locked","zoom_locked"]:
		if not data.get(key) is bool: return false
	var band: Variant = definition.get("coastal_free_band")
	if not band is Dictionary or not integer(band.get("min"),0,255) or not integer(band.get("max"),0,255) or band["min"]>band["max"]: return false
	if not data.get("entries") is Array or data["entries"].size()!=definition["route"].size() or not data.get("submerged_levels") is Dictionary: return false
	var floor: Variant = definition.get("raw_floor")
	if not (floor is Array or floor is PackedByteArray) or floor.size()!=1024*1024: return false
	for height: Variant in floor:
		if not integer(height,0,255): return false
	for key: Variant in data["submerged_levels"]:
		if not key is String or not key.is_valid_int() or int(key)<0 or int(key)>=1024*1024 or not integer(data["submerged_levels"][key],0,19): return false
	if data["protected"].size()!=2 or data["protected"][0]==data["protected"][1]: return false
	for id: Variant in data["protected"]:
		if not integer(id,1,1000000): return false
	for key: String in ["blocked","movement_paused"]:
		if not data.get(key) is bool: return false
	for key: String in ["last_topology","rescue_tick","revision"]:
		if not integer(data.get(key),-1,1000000000000): return false
	var speed: Variant = data.get("reaction_speed")
	if not (speed is int or speed is float) or not is_finite(float(speed)) or speed<0 or speed>1000: return false
	if not data.get("error") is String or data["error"].length()>1000 or data["messages"].size()>64 or data["scheduled"].size()>2048: return false
	for message: Variant in data["messages"]:
		if not message is Dictionary or not integer(message.get("id"),1,100000) or not definition["messages"].has(str(int(message["id"]))): return false
		if not integer(message.get("visible_tick",0),0,1000000000000): return false
		if not message.has("callback") or not (message["callback"]==null or message["callback"] is Dictionary or message["callback"] is String): return false
		if int(message["id"])==29 and not integer(message.get("option"),0,4): return false
	for item: Variant in data["scheduled"]:
		if not item is Dictionary or not integer(item.get("tick"),0,1000000000000): return false
		if item.has("action"):
			if not item["action"] in ["worship","begin_trail"]: return false
		elif not item.get("args") is Array or not (item.get("callback") is String or item.get("callback") is Dictionary): return false
	for entry: Variant in data["entries"]:
		if not entry is Dictionary or not entry.get("Target") is Dictionary: return false
		for axis: String in ["x","y"]:
			var coordinate: Variant = entry["Target"].get(axis)
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or coordinate<0 or coordinate>=1024: return false
	if not data.get("phase") in ["rescue","embrace","worship","trail","trailing","arrival","trail_complete","promised_land","timeline","shrine","belief","discovery"]: return false
	var checkpoint: Variant = data.get("checkpoint")
	if not integer(checkpoint,-1,14): return false
	if data["phase"] in ["trailing","arrival"] and checkpoint!=13: return false
	return not (data["phase"]=="trail" and (checkpoint<0 or checkpoint>=14))


static func integer(value: Variant,minimum: int,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value==int(value) and value>=minimum and value<=maximum


static func sculpt_cost(state: Dictionary,edits: Array,fallback: int) -> int:
	var opening: Dictionary = state["opening"]
	var floor: Variant = opening["definition"]["raw_floor"]
	var band: Dictionary = opening["definition"]["coastal_free_band"]
	for edit: Dictionary in edits:
		var cell: int = edit["cell"]
		var previous := int(state["terrain"][cell])+19 if int(state["terrain"][cell])>0 else int(opening["submerged_levels"].get(str(cell),floor[cell]))
		# Global onSculptFailed identifies the free 17..24 coastal band.
		if mini(previous,int(edit["height"])+19)<int(band["min"]) or maxi(previous,int(edit["height"])+19)>int(band["max"]): return fallback
	return 0
