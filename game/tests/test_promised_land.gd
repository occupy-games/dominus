extends SceneTree

const World = preload("res://simulation/world.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")
const Store = preload("res://infrastructure/world_store.gd")
const SourceRocks = preload("res://simulation/authored_rocks.gd")
var failures := 0


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func has_message(world: RefCounted,id: int) -> bool:
	return world._state["opening"]["messages"].any(func(message: Dictionary) -> bool: return int(message["id"])==id)


func run() -> void:
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["first_abode_values"]["values"]["capacity"]==2 and definition["story"]["first_abode_values"]["values"]["build time"]==7.5,"The next abode must receive its native inherited unit data rather than the older map's shelter values")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	var player := Player.new()
	for tick in range(4000):
		if world._state["opening"]["phase"]=="promised_land" or not world._state["opening"]["error"].is_empty(): break
		world.step(player.commands(world))
	var opening: Dictionary = world._state["opening"]
	check(opening["phase"]=="promised_land" and opening["promised_step"]==0 and opening["error"].is_empty(),"The real trail must start Promised Land's original arrival callback")
	var first_cell := 123*1024+161
	var first_id := Opening.ROCK_ID_BASE+first_cell
	var authored := SourceRocks.at(world._state,122*1024+160)
	check(authored.get("source_type")=="rock1" and authored.get("type")==25 and authored.get("model_name")=="boulder6","The first rock must use the native CSV type/model dispatch, not packed byte 157 modulo seven")
	check(world.plot_obstruction(160,122)=="rock" and world.plot_obstruction(161,122)=="rock","Every occupied part of the authored two-by-two rock must obstruct construction, including cells with zero density bytes")
	check(opening["globals"].get("rockObj")==first_id and opening["reaction_objects"].values().has(first_id),"The source must attach its rock reaction to the actual nearest authored rock")
	var tap := {"type":"tap_object","cell":first_cell}
	check(not world.inspect(tap)["ok"],"The arrival activity lock must prevent removing the rock before its explanation")
	check(not world.inspect({"type":"open_chest","id":"reward:5"})["ok"],"The first chest must remain locked before its source tutorial")
	for tick in range(69): world.step()
	check(not has_message(world,1001),"Promised Land's first message must wait the original seven seconds")
	world.step()
	check(has_message(world,1001),"The original localized arrival explanation must appear on its authored tick")
	# Read the message long enough for the already scheduled sunset transition.
	for tick in range(30): world.step()
	world.step([{"type":"campaign_ack","id":1001}])
	check(has_message(world,1002) and opening["promised_step"]==0,"Acknowledging the first explanation must show the separate original rock explanation")
	var rock_message: Dictionary = opening["messages"].filter(func(message: Dictionary) -> bool: return int(message["id"])==1002)[0]
	check(rock_message.get("object")==first_id and rock_message.get("anchor")=={"kind":"rock","x":161,"z":123},"The rock explanation must anchor to its source object rather than an invented screen location")
	var store := Store.new()
	store.database_path="res://../build/test-promised-land.sqlite"
	check(store.save_world(world.export_state()).get("ok",false),"The original rock explanation and midnight schedule must save through SQLite")
	var saved := store.load_world()
	var restored := World.new()
	check(saved.get("ok",false) and restored.restore(saved.get("data",{}),RandomNumberGenerator.new()),"The source callback, object handle and pending midnight freeze must reload")
	for tick in range(250): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Pending original story and day-clock callbacks must continue exactly after reload")
	var midnight := float(definition["story"]["day_cycle"]["functions"]["Midnight"]["value"])
	check(opening["clock"]["speed"]==0 and float(opening["clock"]["time"])>=midnight and float(opening["clock"]["time"])<midnight+0.51,"The original callback must freeze the source clock at native midnight")
	world.step([{"type":"campaign_ack","id":1002}])
	check(opening["promised_step"]==1 and has_message(world,1003) and has_message(world,1004),"The source must enter its remove-rock step with both original instructions")
	check(opening["activity_exception"]==first_id and opening["actions"].size()==1 and opening["tree_regeneration"],"The source's object exception, hand-action request and regeneration flag must be retained")
	var before := world.snapshot(false)
	check(world.inspect(tap)["ok"] and world.query_copy().inspect(tap)["ok"],"Live and detached command queries must agree on the source rock exception")
	check(world.inspect({"type":"tap_object","cell":122*1024+160})["ok"],"Clicking another occupied part must select the same original rock")
	check(world.snapshot(false)==before,"Command inspection must not mutate callback aliases, object state or schedules")
	check(not world.inspect({"type":"tap_object","cell":124*1024+161})["ok"] and not world.inspect({"type":"tap_tree","cell":first_cell})["ok"],"The exception must unlock exactly the authored rock, not other rocks or trees")
	var events := world.step([{"type":"tap_object","cell":122*1024+160}])
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="rock_removed" and event["id"]==first_id),"A normal accepted click must remove the actual authored rock")
	check(not Opening.rock_alive(world._state,first_cell) and not world.inspect(tap)["ok"],"The removed rock must disappear and reject repeated collection")
	for z in range(122,124):
		for x in range(160,162):
			check(world.plot_obstruction(x,z)!="rock" and not Opening.rock_alive(world._state,z*1024+x),"Removing the source object must clear its entire rock footprint once")
	check(Opening.rock_alive(world._state,124*1024+161),"Clearing the authored object must preserve neighboring packed scenery outside its footprint")
	check(opening["promised_step"]==2 and opening["handoff"].get("available") and opening["error"].is_empty(),"Rock removal must start the source abode tutorial")
	check(not has_message(world,1003) and not has_message(world,1004) and opening["actions"].is_empty() and opening["activity_exception"]==null and not opening["tree_regeneration"],"Original rock destruction must clear its instructions, action and activity exception")
	check(world._state["belief"]==0 and world._state["progression"]["first_card_tick"]==-1 and not "Card_Spirituality" in world._state["progression"]["discovered"],"This source rock must not trigger the older opening's belief/card reward")
	check(world._state["homes"].is_empty(),"The rock alone must not create an abode")
	check(world._state.has("source_plots") and preload("res://simulation/source_plot_registry.gd").valid(world._state["source_plots"]),"The played source map must maintain authoritative plots at the abode handoff")
	var first_plots: Array = preload("res://simulation/source_plot_registry.gd").snapshot(world._state["source_plots"])["plots"].filter(func(plot: Dictionary) -> bool: return preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(161,123),1.0))
	check(first_plots.is_empty(),"Rock clearing without additional sculpting must not silently flatten the original first-tent corner")
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and not Opening.rock_alive(restored._state,first_cell),"The cleared original rock and pending next stage must survive save/load")
	var invalid := world.export_state()
	invalid["state"]["opening"]["definition"]["rock_objects"][0]["origin_x"]=159
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"A malformed authored footprint must reject before restoring source object state")
	for tick in range(9): world.step()
	check(has_message(world,1005) and not world.inspect({"type":"campaign_ack","id":1005})["ok"],"The delayed original plot tip must wait for real flat ground")
	var selected := false
	var building := false
	var mid_build_reloaded := false
	for tick in range(500):
		if not opening["error"].is_empty() or opening["promised_step"]>=3: break
		world.step(player.commands(world))
		selected=selected or opening.has("selected_plot")
		building=building or has_message(world,1006)
		if building and not mid_build_reloaded:
			var construction := world.export_state()
			check(store.save_world(construction)["ok"],"The ongoing source construction must save")
			mid_build_reloaded=restored.restore(store.load_world().get("data",{}),RandomNumberGenerator.new())
			check(mid_build_reloaded and restored.export_state()==construction,"The first abode and its assigned paths must reload exactly")
			if not mid_build_reloaded: break
			world=restored
			opening=world._state["opening"]
	check(selected and building,"The real plot and abode tutorial must run through accepted player commands")
	check(opening["promised_step"]==3 and opening["handoff"]["available"] and opening["error"].is_empty(),"The actual first abode must finish and unlock the second-plot tutorial: %s %s"%[opening["promised_step"],opening["error"]])
	var previous := world.export_state()
	var prior: Dictionary=previous["state"]["opening"]
	prior["handoff"]["available"]=false
	prior["messages"]=[]
	for name: String in ["getSecondRock","getSecondAbode","getFirstBuilder","countAbodes","resetTimeOfDaySpeed"]:
		prior["definition"]["helpers"].erase(name)
		prior["globals"].erase(name)
	prior["definition"]["day_cycle"]["functions"].erase("Sunrise")
	prior["definition"]["program"].erase("local_function_names")
	previous["state"]["homes"][0].erase("breeder_count")
	previous["state"]["homes"][0].erase("birth_ticks")
	for follower: Dictionary in previous["state"]["followers"]: follower.erase("indoors_home")
	check(store.save_world(previous)["ok"],"An earlier opening preview save must remain readable")
	var session := preload("res://application/game_session.gd").new()
	check(session.load_game(store.database_path)["ok"],"The game session must load the earlier second-plot handoff")
	world=session.world
	session.free()
	world.step()
	opening=world._state["opening"]
	check(opening["handoff"]["available"] and has_message(world,1009),"Loading the old handoff must enter the original second-plot callback")
	if not world._state["homes"].is_empty():
		var abode: Dictionary=world._state["homes"][0]
		check(abode["residents"]==2 and abode["capacity"]==2 and abode["build_ticks"]==75 and abode["model_id"]=="tents.group.bin:dff1563f","The authored tent must house the two original followers using its source assembly and stats")
		var release := {"type":"sprog","home_id":abode["id"]}
		check(not world.inspect(release)["ok"],"The second-plot activity lock must prevent early release")
		for tick in range(250):
			if not opening["error"].is_empty() or opening["promised_step"]>=4: break
			world.step(player.commands(world))
		check(opening["promised_step"]==4 and has_message(world,1011),"Source rock removal must reveal the original Builder prompt")
		check(world.inspect(release)["ok"],"The first full abode must offer one builder")
		world.step([release,release])
		check(opening["promised_step"]==5 and abode["residents"]==1 and world._state["followers"].size()==2,"Releasing the builder must leave a breeder in the abode and preserve the population")
		check(opening["clock"]["speed"]==5 and opening["clock"]["waiters"].any(func(waiter: Dictionary) -> bool: return waiter["callback"]=="resetTimeOfDaySpeed"),"The original release must schedule the source sunrise speed reset")
		for tick in range(400):
			if not opening["error"].is_empty() or has_message(world,1016): break
			world.step(player.commands(world))
		check(has_message(world,1016) and world._state["homes"].size()==2,"The released builder must build and occupy the second real abode")
		for tick in range(65): world.step()
		var second: Dictionary=world._state["homes"].back()
		check(second.get("breed_locked",false) and second["residents"]==1,"Waiting at the source explanation must pause breeding before a second resident arrives")
		check(store.save_world(world.export_state())["ok"] and restored.restore(store.load_world().get("data",{}),RandomNumberGenerator.new()),"A paused breed timer and its recursive source callback must survive reload")
		world=restored
		opening=world._state["opening"]
		world.step([{"type":"campaign_ack","id":1016}])
		check(opening["promised_step"]==6 and opening["error"].is_empty(),"The second abode must advance through the source breeding prompt: %s %s"%[opening["promised_step"],opening["error"]])
		for tick in range(330): world.step()
		check(world._state["homes"].back()["residents"]==2 and world._state["followers"].size()==4,"Releasing the pause must fill both tents through actual births")
		check(opening["clock"]["speed"]==1 and opening["error"].is_empty(),"The native sunrise callback must restore the source time speed")
		var old_growth := world.export_state()
		var old_opening: Dictionary=old_growth["state"]["opening"]
		old_opening["handoff"]["available"]=false
		old_opening["definition"].erase("growth_population_card")
		old_opening["messages"]=[]
		var resumed := World.new()
		check(resumed.restore(old_growth,RandomNumberGenerator.new()) and resumed.resume_opening_handoff(definition["story"]),"The earlier two-tent save must accept the newly supported growth callbacks")
		world=resumed
		world.step()
		opening=world._state["opening"]
		var card: Dictionary=opening["definition"]["growth_population_card"]
		check(opening["handoff"]["available"] and not card["id"] in world._state["progression"]["discovered"],"The original card must stay undiscovered below its population milestone")
		for tick in range(1600):
			if not opening["error"].is_empty() or opening["promised_step"]!=6: break
			world.step(player.commands(world))
		check(opening["promised_step"]==7 and opening["error"].is_empty(),"The authored settlement must reach its population reward: %s %s"%[opening["promised_step"],player.diagnostic])
		check(world._state["followers"].size()==10 and world._state["homes"].size()==5 and world._state["homes"].all(func(home: Dictionary) -> bool: return home["residents"]==home["capacity"]),"Ten followers must actually live in five completed tents")
		var progression: Dictionary=world._state["progression"]
		check(card["id"] in progression["discovered"] and not card["id"] in progression["completed"] and progression["rules"]["research_cards"][card["id"]]["research_needed"]==1,"The population reward must be the original unfinished one-point research card")
		var show := {"type":"campaign_show_level_card"}
		check(world.inspect(show)["ok"],"The real card prompt must offer the population reward")
		var shown := world.step([show])
		check(opening["promised_step"]==8 and shown.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_show_card" and event["card"]==card["id"]) and shown.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave"),"Showing the card must run its source callback and request its autosave")
		check(store.save_world(world.export_state())["ok"],"The source card autosave must preserve the campaign state")
		var reopened := preload("res://application/game_session.gd").new()
		check(reopened.load_game(store.database_path)["ok"],"The population-card autosave must load through the application")
		reopened.world.step()
		check(reopened.world._state["opening"]["promised_step"]==9,"The original card reload hook must continue to the chest handoff")
		reopened.free()
		world.step([{"type":"campaign_dismiss_level_card"}])
		check(opening["promised_step"]==9 and opening["handoff"]["available"],"Dismissing the card must enter the original chest tutorial")
		verify_first_chest(world,store)
		verify_timeline(world,store)
		verify_mud_hut_growth(world,store)
		verify_shrine(world,store)
	print("Source Promised Land arrival, rock exception and midnight callbacks: %d failures"%failures)
	quit(1 if failures else 0)


func verify_first_chest(world: RefCounted,store: RefCounted) -> void:
	var opening: Dictionary=world._state["opening"]
	check(opening["error"].is_empty() and opening["promised_step"]==9 and has_message(world,1028),"The source chest explanation must follow the population card")
	var descriptor: Dictionary=opening["definition"]["first_chest"]
	check(descriptor["id"]==5 and descriptor["x"]==177 and descriptor["z"]==147 and descriptor["reward"]=="Sticker_Tools_1","The first chest must retain its actual scoped CSV ID, position and typed reward")
	var row: Dictionary=world.snapshot(false)["progression"]["chests"][0]
	check(row["id"]=="reward:5" and row["type"]=="treasure1" and row["exposed"] and not row["opened"],"The original chest constructor must produce the exposed beach chest")
	var outside := {"type":"campaign_view","projection":[0.03125,0,0,0.5-150.0/32,0,0.03125,0,0.5-120.0/32],"ended":true}
	world.step([outside,{"type":"campaign_ack","id":1028}])
	check(has_message(world,1029) and has_message(world,1030) and not has_message(world,1031),"An offscreen chest must show the original search guidance")
	var visible := {"type":"campaign_view","projection":[0.03125,0,0,0.5-177.0/32,0,0.03125,0,0.5-147.0/32],"ended":true}
	world.step([visible])
	check(has_message(world,1031) and not has_message(world,1029) and not has_message(world,1030),"Panning to the chest must switch to the original click instruction")
	for tick in range(68): world.step()
	check(has_message(world,1031) and not has_message(world,1032),"The source gold hint must retain its seven-second lifetime")
	world.step()
	check(has_message(world,1032) and not has_message(world,1031),"The source seven-second callback must replace the gold hint")
	var command := {"type":"open_chest","id":"reward:5"}
	var before: Dictionary=world.export_state()
	check(world.inspect(command)["ok"] and world.query_copy().inspect(command)["ok"] and world.export_state()==before,"Live and detached chest queries must be pure and agree")
	check(not world.inspect({"type":"open_chest","id":"reward:2"})["ok"],"Unknown chest IDs must stay unavailable")
	var events: Array=world.step([command,command])
	check(events.filter(func(event: Dictionary) -> bool: return event["type"]=="chest_opening").size()==1 and opening["opened_chests"]==1,"Repeated clicks must begin the source chest opening once")
	check(preload("res://simulation/research.gd").stock(world._state["progression"],"Sticker_Tools_1")==0 and world.snapshot(false)["progression"]["chests"][0]["opening"],"Animation must begin before the original timed sticker grant")
	for tick in range(4): world.step()
	check(store.save_world(world.export_state())["ok"],"A partially opened native chest must save through SQLite")
	var restored := World.new()
	check(restored.restore(store.load_world()["data"],RandomNumberGenerator.new()),"The native chest's exact float32 timer and capacity must reload")
	events=[]
	for tick in range(6):
		world.step()
		events.append_array(restored.step())
	check(world.export_state()==restored.export_state(),"The resumed native chest timer, reward and original callbacks must match continuous play")
	check(opening["promised_step"]==10 and opening["handoff"]["available"] and opening["error"].is_empty(),"The source StickerReceived callback must schedule the original Timeline transition")
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave"),"The source first-sticker callback must request its autosave")
	check(preload("res://simulation/research.gd").stock(world._state["progression"],"Sticker_Tools_1")==1 and not world.inspect(command)["ok"],"The original chest must yield exactly one usable TECH sticker")
	check(preload("res://simulation/research.gd").inspect(world._state["progression"],{"type":"research_card","card":opening["level_card"],"sticker":"Sticker_Tools_1"})["ok"],"The chest's actual sticker must fit New Age Shelters")
	for tick in range(11): world.step(); restored.step()
	check(world.snapshot(false)["progression"]["chests"].is_empty() and world.export_state()==restored.export_state(),"The source disappearance delay must remove the consumed chest identically after reload")
	check(store.save_world(world.export_state())["ok"] and restored.restore(store.load_world()["data"],RandomNumberGenerator.new()),"The consumed source ID and empty pool must persist")
	restored.step()
	check(restored.snapshot(false)["progression"]["chests"].is_empty() and preload("res://simulation/research.gd").stock(restored._state["progression"],"Sticker_Tools_1")==1,"Reloading a consumed chest must preserve its single reward without respawning it")


func verify_timeline(world: RefCounted,store: RefCounted) -> void:
	var opening: Dictionary=world._state["opening"]
	var card: String=opening["level_card"]
	var assign := {"type":"research_card","card":card,"sticker":"Sticker_Tools_1"}
	var enter := {"type":"campaign_timeline_open"}
	var leave := {"type":"campaign_timeline_close"}
	check(opening["phase"]=="timeline" and opening["timeline_step"]==0 and opening["persistent"]["PromisedLandProgress"]==1337 and opening["persistent"]["TimelineProgress"]==1,"The original half-second transition must finish Promised Land and begin Timeline")
	check(has_message(world,2001) and has_message(world,2002) and world.inspect(enter)["ok"] and not world.inspect(assign)["ok"],"The source opening instruction must gate sticker assignment")
	var events: Array=world.step([enter])
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_timeline_opened") and opening["timeline_step"]==1 and opening["timeline_open"] and opening["timeline_input_lock"]==2 and has_message(world,2003),"Opening the actual Timeline must run its first explanation and input lock")
	check(not world.inspect(assign)["ok"] and not world.inspect(leave)["ok"] and not world.inspect({"type":"sculpt_drag","x":160,"z":120,"nx":1,"nz":0,"layer":1,"distance":1,"radius":0})["ok"],"The original explanation lock must block assignment, exit and world sculpting")
	world.step([{"type":"campaign_ack","id":2003}])
	check(has_message(world,2004) and not has_message(world,2003),"The source card explanation must lead to its separate resource explanation")
	check(store.save_world(world.export_state())["ok"],"A partly read source Timeline must save")
	var resumed := preload("res://application/game_session.gd").new()
	check(resumed.load_game(store.database_path)["ok"],"The partly read Timeline must load through the application")
	resumed.world.step()
	check(resumed.world._state["opening"]["timeline_step"]==0 and has_message(resumed.world,2001) and not resumed.world._state["opening"]["timeline_open"],"The original onListening reload fallback must restart the unopened Timeline")
	for tick in range(40):
		if resumed.world._state["opening"]["timeline_step"]==4: break
		resumed.world.step(Player.new().commands(resumed.world))
	check(card in resumed.world._state["progression"]["completed"] and resumed.world._state["opening"]["timeline_step"]==4,"An actual reloaded tutorial must complete through ordinary player commands")
	resumed.free()
	world.step([{"type":"campaign_ack","id":2004}])
	check(has_message(world,2005) and not world.inspect(assign)["ok"],"The sticker explanation must remain a separate source acknowledgement")
	world.step([{"type":"campaign_ack","id":2005}])
	check(opening["timeline_step"]==2 and opening["timeline_input_lock"]==1 and has_message(world,2006) and has_message(world,2007) and world.inspect(assign)["ok"] and not world.inspect(leave)["ok"],"Acknowledging all original explanations must enable the compatible resource drop and retain the exit lock")
	var before: Dictionary=world.export_state()
	check(world.query_copy().inspect(assign)["ok"] and world.export_state()==before,"A detached resource-drop preview must preserve authoritative stock and tutorial callbacks")
	events=world.step([assign,assign])
	check(events.filter(func(event: Dictionary) -> bool: return event["type"]=="claim_card").size()==1 and events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave"),"The source completion must occur once and request its original autosave")
	check(opening["timeline_step"]==3 and opening["timeline_input_lock"]==0 and has_message(world,2008) and world.inspect(leave)["ok"] and not has_message(world,2007),"Completing the card must unlock the original exit instruction")
	check(preload("res://simulation/research.gd").stock(world._state["progression"],"Sticker_Tools_1")==0 and preload("res://simulation/source_availability.gd").owned(opening["chest_capacity"],"Sticker_Tools_1")==0 and card in world._state["progression"]["completed"],"The actual typed drop must consume one Tools sticker in both stock and source capacity and complete New Age Shelters")
	check(store.save_world(world.export_state())["ok"],"The original completed-card autosave must persist")
	var reopened := preload("res://application/game_session.gd").new()
	check(reopened.load_game(store.database_path)["ok"],"The completed-card autosave must load")
	reopened.world.step()
	check(reopened.world._state["opening"]["timeline_step"]==4 and card in reopened.world._state["progression"]["completed"],"The original completed-card reload fallback must return to Homeworld")
	reopened.free()
	events=world.step([leave])
	check(opening["timeline_step"]==4 and not opening["timeline_open"] and opening["handoff"]["available"] and has_message(world,2010) and not has_message(world,2008) and opening["error"].is_empty(),"The ordinary exit must start the source first-mud-hut tutorial")
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_timeline_closed"),"The simulation must tell presentation to close the Timeline")


func verify_mud_hut_growth(world: RefCounted,store: RefCounted) -> void:
	var opening: Dictionary=world._state["opening"]
	var descriptor: Dictionary=opening["definition"]["mud_hut"]
	var level: Dictionary=opening["definition"]["timeline_population_card"]
	check(level["id"]=="Card_RepairTemple" and level["population"]==16 and level["ordinal"]==2,"The next milestone must use Homeworld6's scoped population table")
	check(world._state["homes"].all(func(home: Dictionary) -> bool: return home["build_ticks"]==75),"Completing the card must preserve the five tents' original construction duration")
	world.step([{"type":"campaign_ack","id":2010}])
	check(has_message(world,2009) and not level["id"] in world._state["progression"]["discovered"],"The source tutorial must request population 16 before awarding Repair Temples")
	var player := Player.new()
	var first_hut := {}
	for tick in range(350):
		world.step(player.commands(world))
		for home: Dictionary in world._state["homes"]:
			if home.get("source_house")==descriptor["source_id"] and home["progress"]>0:
				first_hut=home
				break
		if not first_hut.is_empty(): break
	check(not first_hut.is_empty(),"A released Builder must start the source mud hut on an actual reachable plot")
	if first_hut.is_empty(): return
	check(first_hut["model_id"]=="lowlandrural2.group.bin:dff1563f" and first_hut["build_ticks"]==120 and first_hut["capacity"]==2 and first_hut["build_capacity"]==1 and first_hut["birth_ticks"]==50,"The new abode must use the original model, build time, staffing and occupancy")
	check(first_hut["progress"]<first_hut["build_ticks"] and first_hut["residents"]==0,"New construction must finish before a resident moves in")
	check(store.save_world(world.export_state())["ok"],"An active source mud-hut build must save")
	var restored := World.new()
	check(restored.restore(store.load_world()["data"],RandomNumberGenerator.new()),"The assigned Builder and its unfinished hut must reload")
	var saw_hint := false
	for tick in range(750):
		var commands := player.commands(world)
		world.step(commands)
		restored.step(commands)
		if not saw_hint and has_message(world,2011):
			saw_hint=true
			var hint: Dictionary=opening["messages"].filter(func(item: Dictionary) -> bool: return int(item["id"])==2011)[0]
			var completed: Array=world._state["homes"].filter(func(home: Dictionary) -> bool: return home["id"]==hint.get("object") and home.get("source_house")==descriptor["source_id"] and home["progress"]==home["build_ticks"])
			check(opening["timeline_step"]==5 and opening["belief_hud_hidden"] and not completed.is_empty() and hint["anchor"]=={"kind":"plot","x":completed[0]["anchor_x"],"z":completed[0]["anchor_z"]},"The native mud-hut completion must advance Timeline and anchor the source tip to the built abode")
		if opening["timeline_step"]==6 or not opening["error"].is_empty(): break
	check(saw_hint and opening["timeline_step"]==6 and opening["persistent"]["TimelineProgress"]==1337 and opening["error"].is_empty(),"The original Timeline must complete at its second population card")
	check(world._state["followers"].size()==16 and world._state["homes"].size()==8 and world._state["homes"].all(func(home: Dictionary) -> bool: return home["residents"]==2 and home["progress"]==home["build_ticks"]),"Sixteen followers must occupy eight completed homes through actual construction and births")
	check(opening.get("shrine_level_card")==level["id"] and level["id"] in world._state["progression"]["discovered"] and not has_message(world,2009),"The second population milestone must reveal the original Repair Temples card and clear its reminder")
	var info: Dictionary=world.inspect_building(first_hut["id"])
	var artwork := preload("res://infrastructure/building_info.gd").record(info)
	check(info["source_house"]==descriptor["source_id"] and info["occupants"]==2 and info["capacity"]==2 and str(artwork.get("texture_path","")).contains("Info_Abode_Straw"),"The completed mud hut must show its own source art and occupancy")
	check(world.export_state()==restored.export_state(),"Construction, occupancy, native callbacks and the reward must continue identically after reload")


func verify_shrine(world: RefCounted,store: RefCounted) -> void:
	var opening: Dictionary=world._state["opening"]
	var site: Dictionary=world.source_shrine_site()
	check(opening["phase"]=="shrine" and opening["shrine_step"]==0 and has_message(world,3001),"The population milestone must enter the original Shrine of Expansion listener")
	var activate := {"type":"campaign_activate_shrine","id":site["id"]}
	check(site["id"]=="1012" and site["x"]==165 and site["z"]==144 and not world.inspect(activate)["ok"],"The source Beacon must begin unactivated at its authored position")
	var events: Array=world.step([{"type":"campaign_show_level_card"}])
	check(opening["shrine_step"]==1 and has_message(world,3002) and events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_show_card" and event["card"]=="Card_RepairTemple") and events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave"),"Restore Ruins must show the original immediate-effect explanation and request its autosave")
	check(store.save_world(world.export_state())["ok"],"The Restore Ruins popup must save")
	var resumed := preload("res://application/game_session.gd").new()
	check(resumed.load_game(store.database_path)["ok"],"The Restore Ruins popup must reload through the session")
	resumed.world.step()
	check(resumed.world._state["opening"]["shrine_step"]==2 and has_message(resumed.world,3003) and not has_message(resumed.world,3002),"The original card reload hook must enter the repair instruction")
	resumed.free()
	world.step([{"type":"campaign_dismiss_level_card"}])
	check(opening["shrine_step"]==2 and has_message(world,3003) and has_message(world,3009),"Dismissing Restore Ruins must show the source Beacon instructions")
	var player := Player.new()
	var work := {}
	for tick in range(300):
		world.step(player.commands(world))
		for home: Dictionary in world._state["homes"]:
			if home.get("shrine_id")==site["id"] and float(home["temple_work"])>0:
				work=home
				break
		if not work.is_empty(): break
	check(not work.is_empty() and opening["shrine_step"]==3 and world.dwelling_count()==8 and site["started"],"Releasing a reachable Builder must start the Beacon before making another house")
	if work.is_empty(): return
	check(work["model_id"]=="shrineexpansion.group.bin:dff1563f" and work["build_ticks"]==600 and work["build_capacity"]==2 and world._state["followers"].size()==16,"The work record must retain the authored Beacon assembly, duration, staffing and existing population")
	check(not world.can_act_at(160,166) and not world.inspect(activate)["ok"],"Working on the Beacon must leave its area and activation locked")
	check(store.save_world(world.export_state())["ok"],"A working Beacon must save with its float32 progress and assigned Builders")
	var restored := World.new()
	check(restored.restore(store.load_world()["data"],RandomNumberGenerator.new()),"The active Beacon repair must reload")
	for tick in range(900):
		var commands := player.commands(world)
		world.step(commands)
		restored.step(commands)
		if site.get("repaired",false): break
	check(site.get("repaired",false) and not site["complete"] and opening["shrine_step"]==3 and has_message(world,3005) and has_message(world,3006) and world.inspect(activate)["ok"],"Finished repairs must show the original activation hints and leave the Beacon awaiting its card click")
	check(not world.can_act_at(160,166) and not site["card"] in world._state["progression"]["discovered"],"Completed work alone must leave the Beacon reward and area locked")
	check(world.export_state()==restored.export_state(),"Construction, worker assignments and the pending reward must match after a mid-repair reload")
	check(store.save_world(world.export_state())["ok"] and restored.restore(store.load_world()["data"],RandomNumberGenerator.new()) and restored.inspect(activate)["ok"],"The unclaimed Beacon card must survive a separate reload")
	events=world.step([activate,activate])
	restored.step([activate,activate])
	check(site["complete"] and opening["shrine_step"]==4 and world._state["progression"].get("reward_history",{}).get(site["card"])==1 and not world.inspect(activate)["ok"],"The Beacon card must activate the source site and grant its reward once")
	check(events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave") and has_message(world,3007),"Activation must request the original autosave and start the population-24 prompt")
	for tick in range(21): world.step(); restored.step()
	check(world.can_act_at(160,166) and world.export_state()==restored.export_state(),"The two original influence areas and returning Builders must advance identically after activation")
	for tick in range(1300):
		if opening["shrine_step"]==5 or not opening["error"].is_empty(): break
		world.step(player.commands(world))
	check(opening["shrine_step"]==5 and opening["persistent"]["ShrineOfExpansionProgress"]==1337 and opening["error"].is_empty(),"The Shrine tutorial must finish through its original population-24 callback")
	check(world.dwelling_count()==12 and world._state["followers"].size()==24 and opening.get("belief_level_card","") in world._state["progression"]["discovered"],"The source belief advance must come from 24 real residents in 12 homes")
	verify_belief(world,store)


func verify_belief(world: RefCounted,store: RefCounted) -> void:
	var opening: Dictionary=world._state["opening"]
	check(opening["phase"]=="belief" and opening.get("belief_step")==0 and opening["belief_hud_hidden"] and has_message(world,4007),"The 24-follower milestone must enter the original Belief card listener")
	if opening.get("belief_step",-1)!=0: return
	var show := {"type":"campaign_show_level_card"}
	var dismiss := {"type":"campaign_dismiss_level_card"}
	var events: Array=world.step([show])
	check(opening["belief_step"]==1 and has_message(world,4001) and world._state["belief"]==0 and events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave"),"Showing Power of Prayer must request the source autosave before adding tutorial belief")
	check(store.save_world(world.export_state())["ok"],"The Power of Prayer card must save its source callback state")
	var session := preload("res://application/game_session.gd").new()
	check(session.load_game(store.database_path)["ok"],"The Power of Prayer autosave must reload")
	if session.world!=null:
		session.world.step()
		check(session.world._state["opening"].get("belief_step")==2 and not has_message(session.world,4001) and session.world._state["belief"]==500,"The source card reload must open the collection step and grant the desktop starting balance")
	session.free()
	world.step([dismiss])
	check(opening["belief_step"]==2 and not opening["belief_hud_hidden"] and world._state["belief"]==500 and has_message(world,4002) and has_message(world,4003),"Dismissing Power of Prayer must expose the real belief balance and collection instructions")
	var arrows: Dictionary=opening.get("arrows",{})
	if arrows.is_empty():
		check(false,"The original collection listener must select a house clump")
		return
	var selected: Array=arrows.values()[0]["objects"].duplicate()
	check(selected.size()>=1 and selected.size()<=4,"The original callback must limit the chosen house clump to four")
	for home: Dictionary in world._state["homes"]:
		if home.get("script_abode_type")==2:
			check(home["stored"]==home["max_belief"],"The original tutorial fill must use the Beach Hut's inherited belief capacity")
	check(not world.inspect({"type":"collect"})["ok"],"The collection tutorial must require an individual house click")
	var collected := 0
	for id: int in selected:
		var command := {"type":"collect","home_id":id}
		var preview: Dictionary=world.inspect(command)
		check(preview["ok"] and preview.get("amount")==20,"Every highlighted Beach Hut must offer its actual stored belief on one click")
		collected+=int(preview.get("amount",0))
		world.step([command])
		check(not world.inspect(command)["ok"],"A second click on an emptied house must collect nothing")
		if id==int(selected[0]) and opening["belief_step"]==2:
			var reloaded := World.new()
			check(reloaded.restore(world.export_state(),RandomNumberGenerator.new()),"Collection progress must persist with its remaining house handles")
			reloaded.prepare_loaded_opening()
			reloaded.step()
			check(reloaded._state["opening"].get("belief_step")==3 and reloaded._state["belief"]==500+collected,"The original reload shortcut must enter the grass lesson without collecting again")
	check(opening["belief_step"]==3 and opening["persistent"]["BeliefCollected"]==1 and arrows.is_empty() and has_message(world,4004),"The last collection must clear its original guidance and show the belief counter explanation")
	check(world._state["belief"]==500+collected and world._state["collected"]==collected,"Collected belief must move from the houses into the player's balance exactly once")
	var waited := World.new()
	check(waited.restore(world.export_state(),RandomNumberGenerator.new()),"The source timed grass hint must survive a save")
	for tick in range(298): waited.step()
	check(has_message(waited,4004) and not waited._state["opening"]["globals"].get("waitingForGrassSculpt",false),"The original grass hint must wait the full thirty seconds without an acknowledgement")
	waited.step()
	check(not has_message(waited,4004) and (has_message(waited,4006) or waited._state["opening"]["belief_step"]==4),"The original timer must start the grass instruction or take its authored skip branch")
	world.step([{"type":"campaign_ack","id":4004}])
	if opening["belief_step"]==3:
		check(opening["globals"].get("waitingForGrassSculpt",false) and has_message(world,4006),"Acknowledging the counter must expose the source grass-layer target")
		var commands := Player.new().commands(world)
		var paid: Array=commands.filter(func(command: Dictionary) -> bool: return command["type"]=="sculpt_drag" and world.inspect(command)["cost"]>0)
		check(paid.size()==1,"The grass lesson must be playable through a real charged drag on the source map")
		if not paid.is_empty():
			var cost: int=world.inspect(paid[0])["cost"]
			var before: int=world._state["belief"]
			world.step(paid)
			check(world._state["belief"]==before-cost,"Completing the grass drag must charge its validated geometry cost")
	check(opening["phase"]=="discovery" and opening["belief_step"]==4 and opening["persistent"]["BeliefProgress"]==1337 and opening["handoff"]["tutorial"]=="Discovery" and opening["error"].is_empty(),"The original grass callback must finish the Belief tutorial and hand off to Discovery")
	if opening["phase"]=="discovery":
		verify_discovery(world,store)
		check(opening.get("pit_step")==1,"The played scenario must finish the Pit reward lesson")


func verify_discovery(world: RefCounted,store: RefCounted) -> void:
	var opening: Dictionary=world._state["opening"]
	var site: Dictionary=world.source_shrine_site()
	check(site["id"]=="1031" and site["x"]==170 and site["z"]==162 and site["build_ticks"]==1000 and site["build_capacity"]==3,"The Pit must use the authored site, repair time and Builder capacity")
	var activate := {"type":"campaign_activate_shrine","id":site["id"]}
	var dismiss := {"type":"campaign_dismiss_level_card"}
	check(not world.inspect(activate)["ok"],"The Pit card must stay unavailable while its site is ruined")
	var player := Player.new()
	var saved_repair := false
	for tick in range(4500):
		if site.get("repaired",false) or not opening["error"].is_empty(): break
		world.step(player.commands(world) if tick%5==0 else [])
		if site.get("started",false) and not saved_repair:
			saved_repair=true
			var state: Dictionary=world.export_state()
			var restored := World.new()
			check(store.save_world(state)["ok"] and restored.restore(store.load_world()["data"],RandomNumberGenerator.new()),"The Pit's Builder assignment and site must survive a mid-repair save")
			check(restored.export_state()==state and not restored.inspect(activate)["ok"],"An in-progress repair must reload without losing work or exposing its reward")
	check(saved_repair and site.get("repaired",false) and world.dwelling_count()>12 and opening["error"].is_empty(),"The regular housing and Builder commands must reach and repair the original Pit: "+player.diagnostic)
	if not site.get("repaired",false): return
	var home: Dictionary=world._state["homes"].filter(func(item: Dictionary) -> bool: return item.get("script_abode_type")==2 and item["residents"]>0)[0]
	var collect := {"type":"collect","home_id":home["id"]}
	check(world.inspect(collect)["ok"],"An occupied Beach Hut must replenish belief during Discovery")
	world.step([collect])
	for tick in range(20): world.step()
	check(home["stored"]>0 and world.inspect_building(home["id"])["belief_per_hour"]>0,"A collected Beach Hut must start gathering belief again")
	check(world.inspect(activate)["ok"] and not site["complete"],"Repair must expose a separate claim action")
	var events: Array=world.step([activate,activate])
	check(site["complete"] and not world.inspect(activate)["ok"] and world._state["progression"]["reward_history"].get(site["card"])==1,"The Pit must grant its own card only once")
	check(events.has({"type":"campaign_show_card","card":"Card_PitOfSacrifice"}) and has_message(world,5101) and world.inspect(dismiss)["ok"],"Claiming the Pit must show its original card and explanation")
	check(store.save_world(world.export_state())["ok"],"The open Pit card must save")
	events=world.step([dismiss])
	check(events.has({"type":"campaign_autosave"}) and opening["pit_step"]==1 and not world.inspect(dismiss)["ok"],"Dismissing the Pit card must request the authored autosave")
	var session := preload("res://application/game_session.gd").new()
	check(session.load_game(store.database_path)["ok"],"The Pit card save must load through the game session")
	if session.world!=null:
		var restored: RefCounted=session.world
		restored.step()
		check(restored._state["opening"]["pit_step"]==1 and not has_message(restored,5101) and not restored.inspect(dismiss)["ok"],"The source startup callback must advance a saved Pit card to the next lesson")
		check(restored._state["progression"]["reward_history"].get(site["card"])==1,"Reload must preserve the card without awarding it again")
	session.free()
