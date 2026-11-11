extends SceneTree

const World = preload("res://simulation/world.gd")
const Progression = preload("res://simulation/progression.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
const ORIGIN := Vector2i(18,20)
const DESTINATION := Vector2i(23,20)
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func run() -> void:
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	data["followers"]=[{"x":ORIGIN.x,"z":ORIGIN.y}]
	data["terrain"][22*int(data["width"])+ORIGIN.x]=0
	var world := World.new()
	world.initialize({"campaign_data":data},RandomNumberGenerator.new())
	var id: int=world._state["followers"][0]["id"]
	var command := {"type":"leash","followers":[id],"home_id":-1,"x":DESTINATION.x,"z":DESTINATION.y}
	check(not world.snapshot(false).has("leash_controls") and not world.inspect(command)["ok"],
		"Homeworld must withhold the controls and command before the original advance")
	Progression.discover(world._state["progression"],"Card_GodPower_TotemActivate")
	Progression.refresh(world._state)
	var saved := world.export_state()
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"Restore a Homeworld save with the original card binding")
	if failures: finish(); return
	var state := restored.snapshot()
	check(state.has("leash_controls") and restored.inspect(command)["ok"],
		"The saved Leashing advance must expose the normal drag controls and reachable order")
	if failures: finish(); return
	var cost: int=state["leash_controls"]["follower_cost"]
	var before: int=state["belief"]
	var water := command.merged({"x":ORIGIN.x,"z":22},true)
	check(not restored.inspect(water)["ok"],"Leashing cannot order a follower to water")
	restored._state["belief"]=cost-1
	check(not restored.inspect(command)["ok"],"Leashing must use the source belief cost")
	restored._state["belief"]=before

	var screen := Screen.new()
	screen.campaign_mode=true
	screen.follower_assets=preload("res://infrastructure/game_content.gd").new().follower_assets()
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=restored.inspect
	var orders: Array=[]
	screen.intent.connect(func(intent: Dictionary) -> void:
		if intent["type"]=="leash": orders.append(intent))
	root.add_child(screen)
	screen.set_process(false)
	screen.apply_snapshot(state)
	var view := screen.world_view
	view.set_process(false)
	view.focus=view.world_position(ORIGIN.x,ORIGIN.y)
	view.zoom=12.0
	view.update_camera()
	var actor: Node3D=view.actor_nodes[id]
	var press := view.camera.unproject_position(actor.position+Vector3.UP*0.35)
	button(view,press,true)
	check(screen.leash_candidate==id,"A normal pointer press must pick the follower in Homeworld")
	screen.advance_lesson_leash(0.20)
	check(not screen.leash_active,"The original hold time must elapse before leashing")
	actor.position+=Vector3(2,0,0)
	check(screen.lesson_follower_at(press)!=id,"The follower must move out of the press's pick radius")
	screen.advance_lesson_leash(0.16)
	check(screen.leash_active and screen.leash_followers==[id],"Holding a walking follower must retain the pressed identity")
	var drop := Vector2(DESTINATION)+Vector2(0.25,-0.15)
	var release := view.camera.unproject_position(view.world_position(drop.x,drop.y))
	button(view,release,false)
	button(view,release,false)
	check(orders.size()==1 and orders[0]["followers"]==[id],"One release must submit exactly one follower order")
	check(not screen.leash_active and screen.pinned_leash_lines.has(id),"Releasing the pointer must immediately pin the leash")
	if failures: screen.free(); finish(); return
	var line: Line2D=screen.pinned_leash_lines[id]
	check(line.points[-1].distance_to(release)<0.1,"The pin must use the dropped position within the tile")
	screen.apply_snapshot(state)
	check(screen.pinned_leash_lines.get(id)==line,"A snapshot before command processing must retain the pending pin")
	view.focus+=Vector3(3,0,-1)
	view.yaw+=0.15
	view.zoom=16
	view.update_camera()
	view.pointer_screen=Vector2.ZERO
	screen.update_pinned_leashes()
	var projected := view.camera.unproject_position(view.world_position(drop.x,drop.y))
	check(line.points[-1].distance_to(projected)<0.1 and line.points[-1].distance_to(release)>1.0,
		"Panning, rotating and zooming must reproject the same world pin")
	var events := restored.step([orders[0],orders[0]])
	screen.apply_snapshot(restored.snapshot(),events)
	check(screen.pending_leash_pins.is_empty() and screen.pinned_leash_lines.get(id)==line,"The accepted order must take over the same tether")
	check(restored._state["belief"]==before-cost,"An accepted leash must charge the source price once")
	var resumed := World.new()
	check(resumed.restore(restored.export_state(),RandomNumberGenerator.new()),"An in-flight leash must persist across saves")
	if failures: screen.free(); finish(); return
	screen.apply_snapshot(state)
	check(screen.pinned_leash_lines.is_empty(),"A world without the order must clear its line")
	screen.apply_snapshot(resumed.snapshot())
	check(screen.pinned_leash_lines.has(id) and screen.pinned_leash_lines[id].points[-1].distance_to(projected)<0.1,
		"Loading the active order must restore its exact pin")
	var follower: Dictionary=resumed._state["followers"][0]
	for tick in range(150):
		if not follower.has("leash_goal"): break
		resumed.step()
	check(not follower.has("leash_goal") and Vector2(follower["x"],follower["z"]).distance_to(drop)<0.01,
		"The leashed follower must reach the exact pin after loading")
	screen.apply_snapshot(resumed.snapshot())
	check(screen.pinned_leash_lines.is_empty(),"The line must disappear when the follower reaches the pin")
	screen.leash_followers.append(id)
	screen.leash_active=true
	button(view,view.camera.unproject_position(view.world_position(ORIGIN.x,22)),false)
	screen.apply_snapshot(resumed.snapshot(),resumed.step([orders.back()]))
	check(screen.pending_leash_pins.is_empty() and screen.pinned_leash_lines.is_empty(),"A rejected water drop must clear its pending pin")
	screen.free()
	check_long_leash()
	finish()


func check_long_leash() -> void:
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	var width := 160
	var origin := Vector2i(8,20)
	var target := Vector2i(147,20)
	var cliff := Vector2i(92,20)
	var terrain := PackedByteArray()
	terrain.resize(width*width)
	for x in range(origin.x,target.x+1): terrain[origin.y*width+x]=clampi(x-36,4,7)
	terrain[cliff.y*width+cliff.x]=9
	var rocks := PackedByteArray()
	rocks.resize(width*width)
	var starts: Array=[]
	for x in range(origin.x,origin.x+3): starts.append({"x":x,"z":origin.y})
	data.merge({"width":width,"terrain":terrain,"rock_field":rocks,"followers":starts},true)
	var world := World.new()
	world.initialize({"campaign_data":data},RandomNumberGenerator.new())
	var state: Dictionary=world._state
	Progression.discover(state["progression"],"Card_GodPower_TotemActivate")
	Progression.refresh(state)
	var follower: Dictionary=state["followers"][0]
	var ids: Array=state["followers"].map(func(agent: Dictionary) -> int: return agent["id"])
	var command:={"type":"leash","followers":ids,"x":target.x,"z":target.y}
	var quote:=world.inspect(command)
	check(quote["ok"] and quote.get("assignments",[{}])[0].get("path",[-1]).is_empty(),
		"The order must retain a destination beyond the original leash limit on a disconnected upper terrace")
	if failures: return
	var belief: int=state["belief"]
	world.step([command,command])
	check(follower["state"]=="waiting" and follower.get("leash_goal")==[target.x,target.y] and state["belief"]==belief-int(quote["cost"]),
		"A blocked ground order must wait and charge the belief cost once")
	var pins: Dictionary=world.snapshot(false)["leash_pins"]
	check(pins.size()==3 and ids.all(func(id: int) -> bool: return pins.get(id)==Vector2(target)),
		"All three followers must retain one common destination while waiting")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"A waiting leash destination must survive a save")
	if failures: return
	check(restored.snapshot(false)["leash_pins"]==pins,"All three pins must survive save and reload")
	var lower:={"type":"lower","x":cliff.x,"z":cliff.y}
	check(restored.inspect(lower)["ok"],"Lowering the cliff by one layer must make a staircase")
	restored.step([lower])
	follower=restored._state["followers"][0]
	check(follower["state"]=="walking" and follower["path"].size()==target.x-origin.x,
		"Connecting the terraces must resume the saved order without another leash")
	var arrived := {}
	for tick in range(2500):
		for agent: Dictionary in restored._state["followers"]:
			if agent.has("leash_goal") or arrived.has(agent["id"]): continue
			arrived[agent["id"]]=Vector2(agent["x"],agent["z"])
		if arrived.size()==3: break
		restored.step()
	check(arrived.size()==3 and arrived.values().all(func(point: Vector2) -> bool: return point.distance_to(Vector2(target))<0.01),
		"All three followers must finish the entire walk to the upper terrace")
	check(restored.snapshot(false)["leash_pins"].is_empty(),"All three tethers must clear after arrival")


func button(view: Node,position: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=position
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	view._unhandled_input(event)


func finish() -> void:
	print("Homeworld follower leashing and hold gesture: %d failures"%failures)
	quit(1 if failures else 0)
