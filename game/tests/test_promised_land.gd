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
	check(opening["promised_step"]==2 and opening["handoff"].get("available")==false and opening["error"].is_empty(),"The next unported abode stage must remain explicitly unavailable rather than running the older map's building rules")
	check(not has_message(world,1003) and not has_message(world,1004) and opening["actions"].is_empty() and opening["activity_exception"]==null and not opening["tree_regeneration"],"Original rock destruction must clear its instructions, action and activity exception")
	check(world._state["belief"]==0 and world._state["progression"]["first_card_tick"]==-1 and not "Card_Spirituality" in world._state["progression"]["discovered"],"This source rock must not trigger the older opening's belief/card reward")
	check(world._state["homes"].is_empty(),"The unported first abode must not be fabricated from the older map's rules")
	check(world._state.has("source_plots") and preload("res://simulation/source_plot_registry.gd").valid(world._state["source_plots"]),"The played source map must maintain authoritative plots at its unavailable abode handoff")
	var first_plots: Array = preload("res://simulation/source_plot_registry.gd").snapshot(world._state["source_plots"])["plots"].filter(func(plot: Dictionary) -> bool: return preload("res://simulation/source_plots.gd").intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(161,123),1.0))
	check(first_plots.is_empty(),"Rock clearing without additional sculpting must not silently flatten the original first-tent corner")
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and not Opening.rock_alive(restored._state,first_cell),"The cleared original rock and unavailable next stage must survive save/load")
	var invalid := world.export_state()
	invalid["state"]["opening"]["definition"]["rock_objects"][0]["origin_x"]=159
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"A malformed authored footprint must reject before restoring source object state")
	print("Source Promised Land arrival, rock exception and midnight callbacks: %d failures"%failures)
	quit(1 if failures else 0)
