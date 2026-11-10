extends SceneTree

const World = preload("res://simulation/world.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
var failures := 0
var definition: Dictionary


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func view(left: float,top: float,width: float,height: float,ended: bool = false) -> Dictionary:
	return {"type":"campaign_view","projection":[1.0/width,0,0,-left/width,0,1.0/height,0,-top/height],"ended":ended}


func fixture(checkpoint: int) -> RefCounted:
	# Controlled source-callback fixtures; these are not full trail playthroughs.
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	var opening: Dictionary = world._state["opening"]
	opening["phase"]="trail"
	opening["checkpoint"]=checkpoint
	var controller := Opening.new()
	controller.configure(world,world._state,[])
	for record: Dictionary in opening["globals"]["initialFollowers"].values(): record["blockage"]=checkpoint-1
	return world


func run() -> void:
	definition=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := fixture(1)
	var state: Dictionary = world._state
	state["followers"][0]["x"]=164.0; state["followers"][0]["z"]=61.0
	state["followers"][1]["x"]=164.0; state["followers"][1]["z"]=62.0
	var controller := Opening.new()
	var output: Array = []
	controller.configure(world,state,output)
	controller.observe(view(0,0,10,10))
	controller.vm.hook("checkOnPreTutorialFollowers")
	check(state["opening"]["error"].is_empty() and controller.vm.error.is_empty(),"Original observer helpers must execute without unsupported calls")
	check(state["opening"]["globals"]["bFollowerOffscreen"] and "StandStill" in state["opening"]["reactions"].values(),"Both followers offscreen early in the trail must create the source stand-still reaction")
	check(not state["opening"]["camera_locked"] and not state["opening"]["zoom_locked"],"Scrolling tutorial must unlock camera and zoom")
	check(has_message(state,10) and has_message(state,11) and state["opening"]["tips"].size()==1,"The original scrolling instructions and follower tip must appear once")
	var positions: Array = [Vector2(state["followers"][0]["x"],state["followers"][0]["z"]),Vector2(state["followers"][1]["x"],state["followers"][1]["z"])]
	for tick in range(20): world.step()
	check(Vector2(state["followers"][0]["x"],state["followers"][0]["z"])==positions[0] and Vector2(state["followers"][1]["x"],state["followers"][1]["z"])==positions[1],"Offscreen pause must stop authoritative movement, independently of rendering")
	check(state["opening"]["tips"].size()==1,"Repeated source checks must not duplicate the follower tooltip")
	world.step([view(160,58,10,10)])
	check("StandStill" in state["opening"]["reactions"].values(),"A changed view must wait for the source pan/zoom-end hook before resuming")
	world.step([view(160,58,10,10,true)])
	check(not "StandStill" in state["opening"]["reactions"].values() and state["opening"]["persistent"].get("CameraUnlocked")==1,"Showing either follower at camera-end must resume the pair and persist the first camera tutorial")
	check(not has_message(state,10) and not has_message(state,11) and has_message(state,12) and state["opening"]["tips"].is_empty(),"Source resume must replace the scrolling hints and clear the follower tip")
	check(state["opening"]["globals"]["followerOffscreenCutoff"]==0.0125,"Later offscreen checks must use the authored narrower screen margin")
	controller.configure(world,state,output)
	controller.vm.hook("startScrollingTutorial")
	check(state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==10 and item["callback"]!=null),"After camera unlock, the original alert must retain its focus-on-followers callback")
	controller.acknowledge(10)
	check(output.any(func(event: Dictionary) -> bool: return event.get("action")=="SetCamera" and event["args"][2]==0.3),"Acknowledging the alert must request the original follower camera focus and zoom ratio")
	check(state["opening"]["camera_locked"] and not state["opening"]["globals"].has("x"),"Camera focus must briefly lock the view and retain local multiple-return variables in their function scope")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Observer projection, reaction handles and callback schedules must restore as plain simulation data")
	for tick in range(10): world.step(); restored.step()
	check(world.export_state()==restored.export_state() and not state["opening"]["camera_locked"],"The original one-second camera unlock and observer checks must continue identically after restore")
	var bad := view(0,0,10,10)
	bad["projection"][0]=NAN
	check(not world.inspect(bad)["ok"],"Non-finite camera observations must be rejected before mutation")
	bad["projection"]=[]
	check(not world.inspect(bad)["ok"],"Incomplete camera observations must be rejected")
	# Only the previous dry, offscreen checkpoint is eligible for this follower.
	world=fixture(5)
	state=world._state
	state["followers"][0]["x"]=164.0; state["followers"][0]["z"]=58.0
	state["followers"][1]["x"]=135.0; state["followers"][1]["z"]=66.0
	state["opening"]["globals"]["initialFollowers"]["1"]["blockage"]=3
	controller.configure(world,state,output)
	controller.observe(view(160,54,10,10,true))
	check(state["followers"][0]["x"]==164,"Visible trailing followers must never be teleported")
	controller.observe(view(136,64,10,10,true))
	check(state["followers"][0]["x"]==164,"A visible candidate destination must never receive an offscreen catch-up")
	var cell := 68*1024+140
	var original_height: int = state["terrain"][cell]
	state["terrain"][cell]=0
	state["opening"]["submerged_levels"][str(cell)]=19
	controller.observe(view(0,0,10,10,true))
	check(state["followers"][0]["x"]==164,"Catch-up must reject an authored target that has become water")
	state["terrain"][cell]=original_height
	controller.observe(view(0,0,10,10,true))
	check(state["followers"][0]["x"]==140 and state["followers"][0]["z"]==68 and state["opening"]["globals"]["initialFollowers"]["1"]["blockage"]==4,"Only the original offscreen dry checkpoint may catch up the trailing follower")
	check(controller.vm.error.is_empty() and state["opening"]["error"].is_empty(),"Loop break and source method dispatch must finish without script errors")
	# A waiting trailing follower must not suppress a new blocked event from the
	# leader, or prevent its next path segment from being planned.
	world=fixture(1)
	state=world._state
	state["followers"][0]["x"]=165.0; state["followers"][0]["z"]=62.0
	state["followers"][0]["state"]="walking"
	state["followers"][1]["x"]=161.0; state["followers"][1]["z"]=60.0
	state["followers"][1]["state"]="waiting"
	state["opening"]["blocked"]=true
	state["opening"]["last_topology"]=state["terrain_revision"]
	for tick in range(80):
		world.step()
		if state["opening"]["entries"][1].get("blockedTriggered",false): break
	check(Vector2(state["followers"][0]["x"],state["followers"][0]["z"])!=Vector2(165,62) and state["opening"]["entries"][1].get("blockedTriggered",false),"A previously blocked companion must not freeze the leader or suppress the source obstacle callback")
	# The source's #BLOCKAGES is 13, despite the table also containing index 0.
	world=fixture(13)
	state=world._state
	for follower: Dictionary in state["followers"]: follower["x"]=157.0; follower["z"]=121.0
	controller.configure(world,state,output)
	controller.vm.hook("checkOnPreTutorialFollowers")
	check(state["opening"]["phase"]=="trailing" and state["opening"]["checkpoint"]==13 and controller.vm.error.is_empty(),"Source table length and method dispatch must enter the trailing-follower stage at the final checkpoint")
	print("Authored trail camera observation and guarded catch-up: %d failures"%failures)
	quit(1 if failures else 0)


func has_message(state: Dictionary,id: int) -> bool:
	return state["opening"]["messages"].any(func(item: Dictionary) -> bool: return int(item["id"])==id)
