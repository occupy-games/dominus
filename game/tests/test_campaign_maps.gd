extends SceneTree

const Content = preload("res://infrastructure/campaign_content.gd")
const World = preload("res://simulation/world.gd")
const Session = preload("res://application/game_session.gd")
const Picker = preload("res://presentation/menu/campaign_menu.gd")
const Influence = preload("res://simulation/influence.gd")
const Temple = preload("res://simulation/temple_rules.gd")
var failures := 0


func _initialize() -> void:
	create_timer(180).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failures += 1


func verify_weyworld(definition: Dictionary) -> void:
	definition["automatic_settlement"] = false
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	world.initialize({"campaign_data":definition}, random)
	var state := world.snapshot(false)
	var p: Dictionary = state["progression"]
	check(p["rules"]["registered_scope"] == "initialworldsetup7", "Homeworld7 must load Weyworld's own research and rules")
	check(state["belief"] == 25000 and state["wheat"] == 700 and state["ore"] == 500, "Weyworld must start with its authored balances")
	check(p["chests"].size() == 71 and p["chests"][0]["x"] == 100 and p["chests"][0]["z"] == 262, "Weyworld must use its own chest locations")
	check(p["shrines"].size() == 34 and p["shrines"][0]["id"] == "2002", "Weyworld must use its own shrine sites")
	check(p["next_population"] == 350, "Weyworld's first population milestone must be 350")
	check(world.house_spec(1)["wheat_cost"] == 9, "Weyworld must use its own construction costs")
	check(not Influence.contains(state,162,132) and Influence.contains(state,162,132,true), "Weyworld's Astari region must allow powers separately from land and construction actions")
	check(not world.can_act_at(143,250), "The first Weyworld expansion must begin locked")
	var farm: Dictionary=state["homes"].filter(func(home: Dictionary) -> bool: return home.get("anchor_x")==130 and home.get("anchor_z")==255).front()
	var mine: Dictionary=state["homes"].filter(func(home: Dictionary) -> bool: return home.get("anchor_x")==116 and home.get("anchor_z")==293).front()
	var free_sites: Array=state["homes"].filter(func(home: Dictionary) -> bool: return home.has("awaiting_influence"))
	check(free_sites.size()==18 and farm["kind"]=="farm" and mine["kind"]=="mine", "Weyworld must start with its 18 original free harvest sites")
	var ark: Dictionary=state["homes"].front()
	check(ark["kind"]=="ark" and ark["anchor_x"]==88 and ark["anchor_z"]==248 and ark["model_id"]=="arkabode.group.bin:dff1563f", "Weyworld must place the source Ark abode at the arrival site")
	check(ark["progress"]==ark["build_ticks"] and ark["capacity"]==0 and ark["residents"]==0, "A standalone start must have a completed Ark with zero passengers")
	for index in range(2):
		var follower: Dictionary=state["followers"][index+2]
		var scripted: Dictionary=definition["arrival"]["followers"][index]
		check(follower["x"]==scripted["x"] and follower["z"]==scripted["z"] and follower["female"]==scripted["female"],"Weyworld must spawn its scripted followers at the source coordinates")
	var farm_collect := {"type":"collect","home_id":farm["id"]}
	var mine_collect := {"type":"collect","home_id":mine["id"]}
	check(not world.inspect(farm_collect)["ok"] and not world.inspect(mine_collect)["ok"], "Free harvests must wait for the appropriate expansion")
	check(Content.for_state(state)["progression_rules"].has("registered_scope"), "A saved Weyworld must resolve its own scope")
	var legacy := state.duplicate(false)
	legacy["progression"] = {}
	check(not Content.for_state(legacy)["progression_rules"].has("registered_scope"), "An older saved map must retain its existing site registration")
	# Put an idle builder near the actual beacon. Clearing, payment, travel and
	# the full authored repair duration all run through the normal world tick.
	var saved := world.export_state()
	saved["state"]["followers"][0]["x"] = 116.0
	saved["state"]["followers"][0]["z"] = 249.0
	check(world.restore(saved,RandomNumberGenerator.new()), "The nearby-builder scenario must restore on the real Weyworld map")
	var repair := {"type":"repair_shrine","id":"2002"}
	for i in range(8):
		var quote := world.inspect(repair)
		var obstruction: Dictionary = quote.get("obstruction",{})
		if obstruction.is_empty(): break
		var cell := int(obstruction["z"]) * 1024 + int(obstruction["x"])
		var tap := {"type":"tap_tree" if obstruction["kind"] == "tree" else "tap_object","cell":cell}
		check(world.inspect(tap)["ok"], "The beacon's actual scenery must be clearable")
		world.step([tap])
	check(world.inspect(repair).get("resource_cost",{}) == {"ore":100}, "The authored beacon must charge 100 ore")
	if not world.inspect(repair)["ok"]: return
	world.step([repair])
	for i in range(9200):
		if world.can_act_at(143,250): break
		world.step()
	state = world.snapshot(false)
	check(state["homes"].front()["residents"]==0, "The Ark must not breed followers during the campaign")
	check(Temple.completed(state["progression"],"2002") and world.can_act_at(143,250), "Completing beacon 2002 must activate its original expansion gate")
	check(state["ore"] == 400 and not world.inspect(repair)["ok"], "The completed beacon must keep its one-time payment")
	check(world.inspect(farm_collect).get("amount")==1 and world.inspect(mine_collect).get("amount")==2, "Beacon 2002 must fill the newly reachable farm and mine to their source capacity")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and restored.can_act_at(143,250), "Weyworld must keep the expanded region after restoring")
	check(restored.inspect(farm_collect)["ok"] and restored.inspect(mine_collect)["ok"], "A saved full site must remain collectible")
	restored.step([farm_collect,mine_collect,farm_collect,mine_collect])
	var harvested := restored.snapshot(false)
	check(harvested["wheat"]==701 and harvested["ore"]==402 and harvested["belief"]==state["belief"], "Harvest collection must credit each resource exactly once")
	check(world.restore(restored.export_state(),RandomNumberGenerator.new()), "A save after collection must restore")
	world.step()
	check(not world.inspect(farm_collect)["ok"] and not world.inspect(mine_collect)["ok"], "Reloading must not fill the free harvests again")
	verify_weyworld_workers(world,farm,mine)


func verify_weyworld_workers(world: RefCounted,farm: Dictionary,mine: Dictionary) -> void:
	# Stand in for the inherited cards and nearby population while Ark travel is
	# unavailable. The actual fields, terrain, construction and jobs are live.
	var saved: Dictionary=world.export_state()
	var prerequisites := ["Card_Settlement_Farming","Card_Settlement_Mine"]
	for card: String in prerequisites:
		saved["state"]["progression"]["discovered"].append(card)
		saved["state"]["progression"]["completed"].append(card)
	var scenarios := [
		{"x":129,"z":257,"worker":Vector2i(128,257),"field":farm,"power":"GodPower_PlaceSettlement_2","resource":"wheat"},
		{"x":115,"z":299,"worker":Vector2i(114,299),"field":mine,"power":"GodPower_PlaceSettlement_3","resource":"ore"}]
	for index in range(scenarios.size()):
		var start: Vector2i=scenarios[index]["worker"]
		var worker: Dictionary=saved["state"]["followers"][index]
		worker.merge({"x":start.x,"z":start.y,"path":[],"job":-1,"state":"idle","wait":1},true)
	if not world.restore(saved,RandomNumberGenerator.new()): check(false,"Staffing prerequisites must restore"); return
	for scenario: Dictionary in scenarios:
		var build := {"type":"home","x":scenario["x"],"z":scenario["z"],"rank":1}
		var plot := Rect2i(scenario["x"],scenario["z"],5,5)
		for chest: Dictionary in world.snapshot(false)["progression"]["chests"]:
			if not plot.has_point(Vector2i(chest["x"],chest["z"])): continue
			var open := {"type":"open_chest","id":chest["id"]}
			if world.inspect(open)["ok"]: world.step([open])
		for i in range(60):
			var quote: Dictionary=world.inspect(build)
			var obstruction: Dictionary=quote.get("obstruction",{})
			if obstruction.is_empty(): break
			var cell := int(obstruction["z"])*1024+int(obstruction["x"])
			world.step([{"type":"tap_tree" if obstruction["kind"]=="tree" else "tap_object","cell":cell}])
		var proposal: Dictionary=world.inspect(build)
		if not proposal["ok"]: check(false,"Weyworld must allow a nearby abode: %s %s"%[build,proposal]); return
		world.step([build])
	for i in range(300): world.step()
	var settlement_ids: Array=[]
	for scenario: Dictionary in scenarios:
		var cast := {"type":"use_power","power":scenario["power"],"x":scenario["x"],"z":scenario["z"]}
		if not world.inspect(cast)["ok"]: check(false,"An inherited settlement power must work in Weyworld: "+str(cast)); return
		world.step([cast])
		var state: Dictionary=world.snapshot(false)
		var id: int=state["progression"]["settlements"].back()["id"]
		var deploy := {"type":"deploy_worker","id":id}
		var plan: Dictionary=world.inspect(deploy)
		if plan.get("field",{}).get("id")!=scenario["field"]["id"]: check(false,"Deployment must target the existing "+scenario["resource"]+" site"); return
		world.step([deploy])
		var staffed: Dictionary=world.snapshot(false)
		check(staffed["homes"].size()==state["homes"].size() and staffed["belief"]==state["belief"] and staffed["wheat"]==state["wheat"] and staffed["ore"]==state["ore"],"Staffing an existing site must not build or charge for a new plot")
		settlement_ids.append(id)
	for i in range(100): world.step()
	var resumed := World.new()
	if not resumed.restore(world.export_state(),RandomNumberGenerator.new()): check(false,"Workers and partially grown harvests must restore"); return
	for i in range(3500): resumed.step()
	for index in range(scenarios.size()):
		var resource: String=scenarios[index]["resource"]
		var collect := {"type":"collect_settlement","id":settlement_ids[index]}
		var delivered: Dictionary=resumed.inspect(collect).get("settlement",{})
		var before: int=resumed.snapshot(false)[resource]
		var amount := int(delivered.get(resource,0))
		var harvest_size := int(scenarios[index]["field"]["max_belief"])
		check(amount>=harvest_size and amount%harvest_size==0,"The staffed %s site must deliver complete harvests, got %d"%[resource,amount])
		resumed.step([collect])
		check(resumed.snapshot(false)[resource]==before+amount,"The settlement must credit the delivered "+resource)


func run() -> void:
	var maps := Content.maps()
	check(maps[0]["id"] == "homeworld", "Homeworld must be the first campaign")
	var hashes := {}
	var constants := preload("res://infrastructure/live_constants.gd").new()
	constants.initialize(Content.homeworld()["progression_rules"])
	var parsed := constants.read()
	check(parsed.get("ok", false), "All three live tables must parse")
	var count := 0
	for entry: Dictionary in maps:
		if not entry["available"]:
			check(Content.map_definition(entry["id"]).is_empty(), "Unsupported maps must not start a substitute world")
			continue
		var definition := Content.map_definition(entry["id"])
		check(not definition.is_empty(), "Available map must load: " + str(entry["name"]))
		if definition.is_empty(): continue
		var world := World.new()
		var random := RandomNumberGenerator.new()
		random.seed = 2026
		world.initialize({"campaign_data": definition}, random)
		var state := world.snapshot(false)
		check(state["campaign"]["map_id"] == entry["id"] and state["source_map"]["name"] == entry["name"], "Campaign must retain selected map identity")
		check(state["source_map"]["height_sha256"] == entry["height_sha256"], "Campaign must use the selected terrain")
		check(not hashes.has(state["source_map"]["height_sha256"]), "Campaign maps must have different terrain")
		hashes[state["source_map"]["height_sha256"]] = true
		check(state["terrain"] == definition["terrain"], "Terrain must be source-derived without cropping")
		if definition.has("story"):
			check(entry["id"]=="homeworld6" and entry.get("playable_through")=="Ark crossing to Weyworld","The source opening must expose the playable Ark crossing")
			check(state["opening"]["phase"]=="rescue" and state["followers"].size()==2,"Homeworld6 must enter its original rescue through ordinary campaign selection")
			for index in range(definition["followers"].size()):
				var start: Dictionary=definition["followers"][index]
				check(state["followers"][index]["x"]==start["x"] and state["followers"][index]["z"]==start["z"] and state["followers"][index]["state"]=="drowning","The authored opening must preserve both fractional source spawn positions")
			var restored := World.new()
			check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"The menu-selected authored opening must restore")
			world.step()
			restored.step()
			check(world.export_state()==restored.export_state(),"The menu-selected rescue must continue with identical authoritative state and RNG")
			check(Content.for_state(world.snapshot(false))["height_sha256"]==definition["height_sha256"],"The selected opening must resolve its original presentation content after loading")
			continue
		var default_area: Dictionary = state["progression"]["rules"]["influence_areas"][0].duplicate()
		check(world.reconfigure(parsed["changes"]).get("ok", false), "Live tables must apply to " + str(entry["name"]))
		check(world.snapshot(false)["progression"]["rules"]["influence_areas"][0] == default_area, "Reload must keep the selected-map influence registration")
		check(world.reconfigure(parsed["changes"]).get("ok", false), "Repeated reload must succeed")
		check(world.snapshot(false)["progression"]["rules"]["influence_areas"][0] == default_area, "Repeated reload must not accumulate a map offset")
		for index in range(definition["followers"].size()):
			var start: Dictionary = definition["followers"][index]
			check(state["followers"][index]["x"] == start["x"] and state["followers"][index]["z"] == start["z"] and world.height_at(start["x"], start["z"]) > 0, "Use actual dry player starts")
		var player := preload("res://simulation/campaign_player.gd").new()
		for tick in range(240):
			var clearing := player.clear_for_plot(world,world.snapshot(false)) if tick%10==0 else {}
			world.step([clearing] if not clearing.is_empty() else [])
		state = world.snapshot(false)
		check(not state["homes"].is_empty(), "Followers must be able to settle on " + str(entry["name"]))
		var restored := World.new()
		check(restored.restore(world.export_state(), RandomNumberGenerator.new()), "Selected-map state must restore")
		world.step()
		restored.step()
		check(world.snapshot(false) == restored.snapshot(false), "Selected-map continuation must be deterministic")
		print(entry["name"], ": ", state["homes"].size(), " homes")
		count += 1
		await process_frame
	check(count == 8, "All eight supported large-map starts must run")
	verify_weyworld(Content.map_definition("homeworld7"))
	var picker := Picker.new()
	picker.maps = maps
	root.add_child(picker)
	check(picker.selected == "homeworld" and not picker.start_button.disabled, "Picker must default to Homeworld")
	var requested: Array = []
	picker.start_requested.connect(func(id: String) -> void: requested.append(id))
	picker.select_map("homeworld6")
	check(not picker.start_button.disabled and picker.details.text.contains("Ark crossing to Weyworld") and picker.details.text.contains("unfinished"), "Homeworld6 must offer its source opening and disclose the current endpoint")
	picker.start_button.pressed.emit()
	picker.select_map("homeworld7")
	check(picker.title.text == "Weyworld" and not picker.start_button.disabled, "Weyworld must be selectable by its campaign name")
	picker.start_button.pressed.emit()
	check(requested == ["homeworld6","homeworld7"], "Picker must request each chosen map ID")
	picker.queue_free()
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	var definition := Content.map_definition("hubworld_02")
	session.new_campaign(definition)
	var path := "res://../build/map-selection-save.sqlite3"
	check(session.save_game(path).get("ok", false), "Selected map must save to SQLite")
	session.new_campaign(Content.homeworld())
	check(session.load_game(path).get("ok", false), "Selected map must load from SQLite")
	var loaded := session.presentation_snapshot()
	check(loaded["campaign"]["map_id"] == "hubworld_02", "Load must retain the selected map")
	check(Content.for_state(loaded)["bathymetry"] == definition["bathymetry"], "Load must resolve the selected water background, not Homeworld")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	session.queue_free()
	await process_frame
	print("Original large campaign maps: %d failures" % failures)
	quit(1 if failures else 0)
