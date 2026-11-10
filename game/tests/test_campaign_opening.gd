extends SceneTree

const World = preload("res://simulation/world.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
const Content = preload("res://infrastructure/campaign_opening_content.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var data := Content.definition()
	check(not data.is_empty(),"The authored opening must load its verified terrain and script data")
	if data.is_empty(): quit(1); return
	var rng := RandomNumberGenerator.new()
	rng.seed=2026
	var world := World.new()
	world.initialize({"campaign_data":data},rng)
	var initial := world.snapshot(false)
	check(initial["followers"].size()==2 and initial["followers"][0]["x"]==162.7 and initial["followers"][0]["z"]==53.2 and initial["followers"][1]["x"]==163.3 and initial["followers"][1]["z"]==52.8,"Use both original fractional Lua spawn positions, not invented dry starts")
	check(not initial["followers"][0]["female"] and initial["followers"][1]["female"],"The pair must retain their original source gender arguments")
	check(initial["belief"]==0 and world.height_at(163,53)==0 and initial["followers"][0]["state"]=="drowning","The source opening must begin in the water with no belief")
	check(initial["opening"]["definition"].is_read_only(),"Immutable story definitions must be shared rather than copied at every snapshot")
	var detached := initial.duplicate(true)
	detached["opening"]["entries"][0]["Target"]["x"]=1
	check(world.snapshot(false)["opening"]["entries"][0]["Target"]["x"]==164,"Source callback state must remain detached")
	for tick in range(20): world.step()
	check(world.snapshot(false)["followers"][0]["x"]==162.7 and world.snapshot(false)["followers"][0]["state"]=="drowning","Drowning tutorial followers must neither wander nor teleport to shore")
	var rescue := {"type":"sculpt_drag","x":166,"z":58,"nx":0,"nz":-1,"layer":1,"distance":5,"dx":-3,"dz":-5,"radius":1}
	var preview := world.inspect(rescue)
	check(preview["ok"] and preview["cost"]==0,"An ordinary coastal layer drag must be possible at zero belief in the source free band")
	var events := world.step([rescue])
	var saved := world.export_state()
	check(world.height_at(163,53)==1 and world.snapshot(false)["opening"]["phase"]=="embrace","Extending real terrain beneath the followers must rescue them")
	check(world.snapshot(false)["followers"][0]["x"]==162.7 and world.snapshot(false)["followers"][1]["x"]==163.3,"Rescue geometry must not snap or teleport the original pair")
	check(events.any(func(event: Dictionary) -> bool: return event.get("event","")=="PLAYSOUND_OPENINGTUTORIAL_FOLLOWERSSAVED"),"Rescue must emit the original source sound event")
	check(world.snapshot(false)["followers"][0]["state"]=="hugging_give" and world.snapshot(false)["followers"][1]["state"]=="hugging_take","Rescue must expose both sides of the original paired embrace")
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"A rescue in progress must restore without scenes or devices")
	for tick in range(60): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Rescue timing and RNG must continue identically after restore")
	check(world.snapshot(false)["opening"]["phase"]=="worship","The authored six-second embrace must precede worship")
	check(world.inspect({"type":"campaign_ack","id":4})["ok"],"The original saved-followers message must permit its continuation callback")
	world.step([{"type":"campaign_ack","id":4}])
	check(world.snapshot(false)["opening"]["phase"]=="trail" and world.snapshot(false)["opening"]["checkpoint"]==0,"Acknowledging the source message must begin the authored trail")
	for tick in range(160): world.step()
	var reached := world.snapshot(false)
	check(reached["opening"]["checkpoint"]>=1,"The rescued pair must actually navigate the real deformed map to the first source checkpoint")
	check(reached["homes"].is_empty(),"Followers must not begin the older map's automatic settlement during the authored trail")
	for tick in range(200):
		if world._state["opening"]["checkpoint"]==1 and world._state["opening"]["entries"][1].get("blockedTriggered",false): break
		world.step()
	check(world._state["opening"]["checkpoint"]==1 and world._state["opening"]["entries"][1].get("blockedTriggered",false),"The leading follower must reach the authored first cliff and trigger its original blocked instructions")
	var staircase := {"type":"sculpt_drag","x":164,"z":64,"nx":0,"nz":-1,"layer":2,"distance":1,"radius":1}
	check(world.inspect(staircase)["ok"] and world.inspect(staircase)["cost"]==0,"A real layer drag must form the first cliff's missing stair at zero belief")
	world.step([staircase])
	check(not world._state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==9),"The original unblocking callback must wait its authored delay after sculpting")
	world.step()
	check(world._state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==9),"The delayed source path check must recognize the genuinely navigable stair and offer scrolling")
	world.step([{"type":"campaign_ack","id":9},{"type":"campaign_view","projection":[0.05,0,0,-7.75,0,0.05,0,-2.8],"ended":true}])
	check(world._state["opening"]["persistent"].get("CameraUnlocked")==1,"The real first-obstacle continuation must unlock the camera when a follower is visible")
	for tick in range(400):
		if world._state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==13): break
		world.step()
	check(world._state["opening"]["checkpoint"]==2 and world._state["opening"]["movement_paused"] and world._state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==13),"Ordinary rescue and stair drags must let the pair actually reach the source's first land-assessment pause")
	check(world._state["opening"]["error"].is_empty(),"The played opening must not silently encounter an unsupported source callback")
	var store := Store.new()
	store.database_path="res://../build/test-authored-opening.sqlite"
	check(store.save_world(world.export_state()).get("ok",false),"Authored callbacks and schedules must save through SQLite")
	var loaded := store.load_world()
	check(loaded.get("ok",false) and restored.restore(loaded.get("data",{}),RandomNumberGenerator.new()),"Authored callbacks and schedules must reload through SQLite")
	if world.export_state()!=restored.export_state(): difference(world.export_state(),restored.export_state(),"loaded")
	for tick in range(10):
		world.step(); restored.step()
		if world.export_state()!=restored.export_state():
			difference(world.export_state(),restored.export_state(),"tick"+str(tick))
			break
	if world.export_state()!=restored.export_state(): difference(world.export_state(),restored.export_state(),"saved")
	check(world.export_state()==restored.export_state(),"SQLite continuation must preserve fractional followers, source callbacks and pending UI")
	var invalid := world.export_state()
	invalid["state"]["opening"]["protected"]=[1,1]
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Malformed source follower identities must reject before restore")
	invalid=world.export_state()
	invalid["state"]["opening"]["entries"][0]["Target"]["x"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Malformed source targets must reject before restore")
	# Exercise a source callback that pauses for user acknowledgement. This is a
	# controlled callback fixture, not evidence that the complete trail was played.
	var callback := world.export_state()
	callback["state"]["opening"]["checkpoint"]=2
	callback["state"]["opening"]["phase"]="trail"
	callback["state"]["opening"]["error"]=""
	check(restored.restore(callback,RandomNumberGenerator.new()),"The callback fixture must restore")
	var state: Dictionary = restored._state
	var controller := Opening.new()
	controller.configure(restored,state,[])
	controller.run_callback("onArrived")
	check(state["opening"]["movement_paused"] and state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==13 and item["callback"]!=null),"The source too-small-land callback must pause and retain its real closure")
	controller.acknowledge(13)
	check(state["opening"]["checkpoint"]==3 and state["opening"]["error"].is_empty(),"Executing the retained source closure must advance to its next authored checkpoint")
	check(state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==14),"Advancing a checkpoint must preserve the source's timed continuation message")
	FileAccess.open("res://../build/authored-opening-rescue.json",FileAccess.WRITE).store_string(JSON.stringify(saved))
	print("Authored Homeworld6 rescue and source callbacks: %d failures"%failures)
	quit(1 if failures else 0)


func difference(a: Variant,b: Variant,path: String) -> bool:
	if typeof(a)!=typeof(b): print("Type at ",path,": ",typeof(a)," / ",typeof(b)," values ",a," / ",b); return true
	if a is Dictionary:
		for key: Variant in a:
			if not b.has(key): print("Missing key ",path,"/",key); return true
			if difference(a[key],b[key],path+"/"+str(key)): return true
	elif a is Array:
		if a.size()!=b.size(): print("Length at ",path); return true
		for index in range(a.size()):
			if difference(a[index],b[index],path+"/"+str(index)): return true
	elif a!=b: print("Value at ",path,": ",a," / ",b); return true
	return false
