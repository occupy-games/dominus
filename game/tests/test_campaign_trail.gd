extends SceneTree

const World = preload("res://simulation/world.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


class Terrace extends RefCounted:
	var heights: Dictionary
	var summit := Vector2i(13,10)

	func _occupied(x: int,z: int) -> bool:
		return not heights.has(Vector2i(x,z))

	func height_at(x: int,z: int) -> int:
		return heights.get(Vector2i(x,z),0)

	func can_act_at(x: int,z: int) -> bool:
		return Vector2i(x,z)!=summit


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func verify_physical_ramp() -> void:
	var terrace:=Terrace.new()
	for x in range(10,14): terrace.heights[Vector2i(x,10)]=1
	terrace.heights[terrace.summit]=8
	var state:={"width":32,"belief":100,"opening":{"events_step":1,"definition":{"coastal_free_band":{"min":19,"max":63}}}}
	var start:=Vector2i(10,10)
	var player:=Player.new()
	check(player.sculpt_route(terrace,state,start,terrace.summit,3,8).is_empty(),
		"Three cells cannot reach a terrace seven layers higher by editing the same tile twice")
	for z in range(11,14):
		terrace.heights[Vector2i(10,z)]=1
		terrace.heights[Vector2i(13,z)]=1
	for x in range(11,13): terrace.heights[Vector2i(x,13)]=1
	var path:=player.sculpt_route(terrace,state,start,terrace.summit,3,8)
	check(path.size()==9 and path.back()==Vector3i(13,10,8),"A longer route must connect to the summit at its actual height")
	var seen:={start:true}
	var last:=Vector3i(start.x,start.y,1)
	for step: Vector3i in path:
		var cell:=Vector2i(step.x,step.y)
		check(not seen.has(cell) and absi(last.x-step.x)+absi(last.y-step.y)==1 and absi(last.z-step.z)<=1,
			"A ramp must use adjacent distinct cells with walkable height changes")
		seen[cell]=true
		last=step


func verify_stranded_builder(source: Dictionary) -> void:
	var world := World.new()
	world.initialize({},RandomNumberGenerator.new())
	var width: int=world._state["width"]
	world._state["terrain"].fill(1)
	for z in range(width): world._state["terrain"][z*width+16]=4
	world._state["terrain_revision"]+=1
	var follower: Dictionary=world._state["followers"][0]
	follower.merge({"x":15.0,"z":16.0,"state":"waiting","job":999,"work_x":18,"work_z":16,"path":[]},true)
	check(world._route(Vector2i(15,16),Vector2i(18,16)).is_empty(),"The stranded-Builder fixture must have a real impassable cliff")
	var snapshot := world.snapshot(false)
	snapshot["opening"]={"definition":source,"submerged_levels":{}}
	snapshot["progression"]={"influence_revision":0}
	var before := world.export_state()
	var command := Player.new().grow_promised_land(world,snapshot)
	check(world.export_state()==before,"Finding a Builder connection must preserve simulation state and RNG")
	check(command.get("type")=="sculpt_drag" and world.inspect(command)["ok"],"Self-play must reconnect a stranded Builder with an accepted ordinary terrain drag")
	if command.is_empty(): return
	world.step([command])
	check(not world._route(Vector2i(15,16),Vector2i(18,16)).is_empty(),"The accepted geometry edit must open a walkable route to the Builder's existing job")


func run() -> void:
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	verify_physical_ramp()
	verify_stranded_builder(definition["story"])
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	var player := Player.new()
	var trace: Array = []
	var checkpoints: Array = []
	var acknowledgements: Array = []
	var events: Array = []
	var inward := 0
	var outward := 0
	var restored: RefCounted
	var ticks := 0
	var arrival_tick := -1
	for tick in range(4000):
		ticks=tick
		var state: Dictionary = world._state
		var opening: Dictionary = state["opening"]
		if int(opening["checkpoint"])>=0 and not int(opening["checkpoint"]) in checkpoints: checkpoints.append(int(opening["checkpoint"]))
		if not opening["error"].is_empty(): break
		if opening["phase"]=="arrival" and arrival_tick<0: arrival_tick=tick
		if opening["phase"]=="promised_land": break
		if restored==null and opening["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==19):
			var store := Store.new()
			store.database_path="res://../build/test-authored-trail.sqlite"
			check(store.save_world(world.export_state()).get("ok",false),"The played trail must save its real second assessment closure through SQLite")
			var saved := store.load_world()
			restored=World.new()
			check(saved.get("ok",false) and restored.restore(saved.get("data",{}),RandomNumberGenerator.new()),"The played trail's terrain edits, observer and source callback must reload")
		var commands := player.commands(world)
		for command: Dictionary in commands:
			check(command["type"] in ["sculpt_drag","campaign_ack","campaign_view"] and world.inspect(command)["ok"],"Self-play must use accepted ordinary terrain, tooltip and camera commands")
			if command["type"]=="campaign_ack": acknowledgements.append(command["id"])
			elif command["type"]=="sculpt_drag":
				if int(command["distance"])<0: inward+=1
				else: outward+=1
		if not commands.is_empty(): trace.append({"tick":tick,"commands":commands.duplicate(true)})
		events.append_array(world.step(commands))
		if restored!=null: restored.step(commands)
	check(world._state["opening"]["error"].is_empty(),"All played source callbacks must be supported: "+str(world._state["opening"]["error"]))
	check(world._state["opening"]["phase"]=="promised_land" and checkpoints==range(14),"Ordinary commands must reach all fourteen source trail checkpoints and finish waiting for both followers")
	check(arrival_tick>=0 and ticks-arrival_tick==100,"The original arrival celebration must wait ten simulation seconds before handing off to Promised Land")
	check(world._state["opening"].get("handoff")=={"tutorial":"PromisedLand","step":0,"available":true},"The genuine source handoff must start the supported arrival step of Promised Land")
	check(inward>0 and outward>0,"The actual trail run must exercise inward layer retractions as well as outward bridges")
	check(not events.any(func(event: Dictionary) -> bool: return event["type"] in ["rejected","campaign_catch_up"]),"The full played run must neither reject commands nor teleport its followers")
	for message: int in [4,13,19,25]: check(message in acknowledgements,"The run must acknowledge its real source story pause: "+str(message))
	for follower: Dictionary in world._state["followers"]: check(float(follower["z"])>=119,"Both followers must actually reach the source arrival threshold")
	check(world._state["belief"]==0 and world._state["homes"].is_empty(),"Trail self-play must not inject belief or substitute the older map's settlement rules")
	check(restored!=null and world.export_state()==restored.export_state(),"SQLite continuation must reproduce the remaining trail commands and exact final state")
	var arrival := world.export_state()
	check(preload("res://simulation/source_unlocks.gd").enabled(world._state["progression"],"PlotsAppearClaim"),"The original arrival must persist its scripted plot-claim unlock")
	for effect: String in ["rainbowVFX","godraysVFX"]:
		check(events.any(func(event: Dictionary) -> bool: return event.get("name")==effect and event["type"]=="campaign_vfx_start"),"Arrival must emit the original effect reference: "+effect)
	check(events.filter(func(event: Dictionary) -> bool: return event.get("name")=="birdExplosionVFX").size()==6,"The source bird sequence must emit all six authored positions")
	check(events.filter(func(event: Dictionary) -> bool: return event["type"]=="campaign_vfx_stop").size()==2,"Both long arrival effects must receive their original ten-second stop events")
	check(events.any(func(event: Dictionary) -> bool: return event.get("event")=="PLAYSOUND_OPENINGTUTORIAL_PROMISEDLANDREACHED"),"Arrival must emit its original source audio event")
	check(not world._state["opening"]["reactions"].values().has("TutorialAtPromisedLand") and world._state["opening"]["clock"]["speed"]==5,"The source ten-second continuation must stop cheering and begin the sunset transition")
	for tick in range(120): world.step()
	var clock: Dictionary = world._state["opening"]["clock"]
	var sunset := float(definition["story"]["day_cycle"]["functions"]["Sunset"]["value"])
	check(clock["speed"]==0 and float(clock["time"])>=sunset and float(clock["time"])<sunset+0.51,"The original AtTimeOfDay callback must freeze the source clock when sunset is crossed")
	check(not world._state["opening"]["messages"].any(func(message: Dictionary) -> bool: return int(message["id"])==28),"The source arrival message must clear after twelve seconds")
	var frozen_time: float = clock["time"]
	for tick in range(30): world.step()
	check(clock["time"]==frozen_time,"The sunset callback must actually freeze simulation time rather than depend on rendering")
	var waiting := trailing_fixture(arrival,Vector2(157,115))
	var output: Array = waiting.step()
	check(waiting._state["opening"]["phase"]=="trailing","The first arrival must enter the source's separate waiting stage")
	waiting.step()
	check(waiting._state["opening"]["phase"]=="trailing" and waiting._state["opening"]["camera_locked"],"A reachable trailing follower must continue walking while the source camera is locked")
	var revision: int = waiting._state["terrain_revision"]
	output.append_array(waiting.step([{"type":"sculpt_drag","x":157,"z":111,"nx":1,"nz":0,"layer":1,"distance":-1,"radius":0}]))
	check(waiting._state["terrain_revision"]==revision,"The original waiting-stage activity lock must reject new terrain edits")
	var resumed := World.new()
	check(resumed.restore(waiting.export_state(),RandomNumberGenerator.new()),"Waiting for the second follower must persist its scheduled half-second source loop")
	for tick in range(80):
		output.append_array(waiting.step()); resumed.step()
		if waiting._state["opening"]["phase"]=="arrival": break
	check(waiting._state["opening"]["phase"]=="arrival" and float(waiting._state["followers"][1]["z"])>=119,"Arrival must wait for the actual trailing follower to cross the authored threshold")
	check(not output.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_catch_up"),"A valid trailing path must never be replaced by a teleport")
	check(waiting.export_state()==resumed.export_state(),"The second follower must arrive identically after restoring its waiting-stage schedule")
	var repair := trailing_fixture(arrival,Vector2(100,100))
	output=repair.step()
	output.append_array(repair.step())
	check(repair._state["opening"]["phase"]=="arrival" and output.any(func(event: Dictionary) -> bool: return event.get("cause")=="trailing_path_repair"),"An invalid trailing path must use the distinct repair explicitly authored in the arrival-stage source")
	check(float(repair._state["followers"][1]["x"])==157 and float(repair._state["followers"][1]["z"])==121,"Original path repair must use the final authored target, not an invented nearest dry cell")
	var invalid := arrival.duplicate(true)
	invalid["state"]["opening"]["clock"]["time"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"A malformed day clock must reject before restoring simulation state")
	var cycle := preload("res://simulation/day_cycle.gd")
	var cycle_definition: Dictionary = definition["story"]["day_cycle"]
	var clock_fixture := {"time":float(cycle_definition["period"])-0.2,"speed":1.0,"waiters":[{"time":0.1,"callback":"test_boundary","args":[]}]}
	check(cycle.advance(clock_fixture,cycle_definition,0.15).is_empty(),"A time-of-day callback must not fire before its boundary")
	check(cycle.advance(clock_fixture,cycle_definition,0.2).size()==1 and cycle.advance(clock_fixture,cycle_definition,0.3).is_empty(),"A source clock callback must cross a wrapped day exactly once")
	FileAccess.open("res://../build/authored-trail-playthrough.json",FileAccess.WRITE).store_string(JSON.stringify({"source_sha256":definition["story"]["source_sha256"],"height_sha256":definition["height_sha256"],"ticks":ticks,"checkpoints":checkpoints,"inward":inward,"outward":outward,"trace":trace,"terminal":"promised_land_handoff","failures":failures},"  "))
	print("Authored full trail, terrain gestures and trailing-follower arrival: %d failures"%failures)
	quit(1 if failures else 0)


func trailing_fixture(arrival: Dictionary,position: Vector2) -> RefCounted:
	# Controlled asymmetry/invalid-path checks use the genuinely played terrain.
	var saved := arrival.duplicate(true)
	var state: Dictionary = saved["state"]
	var opening: Dictionary = state["opening"]
	opening["phase"]="trail"
	opening["checkpoint"]=13
	opening["camera_locked"]=false
	opening["movement_paused"]=false
	opening["globals"]["hackStopFollowerCheck"]=false
	opening["globals"]["tutorialGotoReaction"]=1
	opening["globals"]["initialFollowers"]={}
	opening["reactions"]={"1":"TutorialGoTo"}
	opening["next_reaction"]=2
	opening["observer"]={"mode":"all"}
	opening["entries"][13]["blockageCleared"]=false
	opening["messages"]=[]
	opening["scheduled"]=[{"tick":int(state["tick"])+1,"callback":"checkOnPreTutorialFollowers","args":[]}]
	for i in range(2):
		var agent: Dictionary = state["followers"][i]
		agent["x"]=157.0 if i==0 else position.x
		agent["z"]=119.5 if i==0 else position.y
		agent["state"]="idle"
		agent["path"]=[]
		opening["globals"]["initialFollowers"][str(i+1)]={"id":agent["id"],"blockage":12}
	var world := World.new()
	check(world.restore(saved,RandomNumberGenerator.new()),"The asymmetric trailing-follower fixture must restore")
	return world
