extends SceneTree

const Session = preload("res://application/game_session.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
var failures := 0
var commands: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	var session := Session.new()
	root.add_child(session); session.set_process(false)
	var definition := preload("res://tests/fixtures/campaign_economy.gd").definition()
	definition["progression_rules"]=preload("res://infrastructure/campaign_content.gd").homeworld()["progression_rules"].duplicate(true)
	definition["progression_rules"]["influence_enabled"]=false
	for key: String in ["chests","shrines","objects"]: definition["progression_rules"][key]=[]
	session.new_campaign(definition)
	for x in [12,19,26]: session.submit({"type":"home","x":x,"z":12,"rank":1})
	for batch in range(300): session.advance_elapsed(.5)
	var state := session.presentation_snapshot()
	check(state["homes"].size()==3,"Collection must exercise real occupied, belief-producing houses")
	if state["homes"].size()!=3: session.free(); quit(1); return
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=session.inspect
	screen.inspect_building=session.inspect_building
	screen.resolve_building_info=preload("res://infrastructure/building_info.gd").record
	screen.building_info_labels=preload("res://infrastructure/building_info.gd").content()["labels"]
	screen.intent.connect(func(command: Dictionary) -> void: commands.append(command.duplicate(true)); session.submit(command))
	root.add_child(screen); screen.set_process(false)
	session.changed.connect(screen.apply_snapshot)
	screen.apply_snapshot(state)
	var total := 0
	for home: Dictionary in state["homes"]:
		check(int(home["stored"])>0,"The ordinary house tick must have produced collectible belief")
		total+=int(home["stored"])
	var belief := int(state["belief"])
	var first_id := int(state["homes"][0]["id"])
	var first_amount := int(state["homes"][0]["stored"])
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	check(commands.size()==1 and commands[0]=={"type":"collect","home_id":first_id},"One ordinary world click must request collection immediately")
	check(screen.belief_sweep and not screen.world_view.layer_drag and not screen.building_panel.popup.visible,"A collecting click must start the belief gesture without requiring an info button or sculpting")
	session.advance_elapsed(.1)
	state=session.presentation_snapshot()
	check(state["belief"]==belief+first_amount and state["homes"][0]["stored"]==0,"That single click must credit the stored house belief")
	# A single long pointer motion crosses the middle house as well as the
	# endpoint; returning across the same houses cannot enqueue duplicate spends.
	screen.on_pointer_dragged(Vector2i(26,12))
	check(commands.size()==3,"An unlocked fast drag must collect both crossed houses")
	if commands.size()==3: check(commands[1].get("gesture")=="drag" and commands[2].get("gesture")=="drag","Drag collection must pass through the authoritative source unlock gate")
	screen.on_pointer_dragged(Vector2i(12,12))
	check(commands.size()==3,"The same gesture must collect each house at most once, even with a stale threaded snapshot")
	session.advance_elapsed(.1)
	state=session.presentation_snapshot()
	check(state["belief"]==belief+total,"Click plus drag must collect exactly the three stored amounts")
	for home: Dictionary in state["homes"]: check(home["stored"]==0,"Every crossed house must be debited by simulation")
	screen.world_view.pointer_released.emit()
	check(not screen.belief_sweep and screen.belief_sweep_seen.is_empty(),"Releasing the pointer must end and clear the collection gesture")
	# A saved pre-unlock state may still hold belief. Clicking remains usable;
	# dragging must reject in both UI and simulation until BeliefLeashing.
	var saved := session.world.export_state()
	var p: Dictionary=saved["state"]["progression"]
	for id: String in ["Card_Spirituality","Card_GenerateBelief"]:
		p["discovered"].erase(id); p["completed"].erase(id)
		saved["state"]["campaign"]["cards"].erase(id)
	for home: Dictionary in saved["state"]["homes"]: home["stored"]=maxi(5,int(home.get("min_belief",0)))
	check(session.world.restore(saved,RandomNumberGenerator.new()),"A pre-leashing saved world must remain valid")
	session.refresh_queries(); screen.apply_snapshot(session.presentation_snapshot())
	commands=[]
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	check(commands.size()==1,"A locked drag upgrade must never add a second click to ordinary collection")
	screen.on_pointer_dragged(Vector2i(26,12))
	check(commands.size()==1,"Before the source unlock, dragging cannot collect other houses")
	var second_id := int(saved["state"]["homes"][1]["id"])
	var second_amount := int(saved["state"]["homes"][1]["stored"])
	var dragged := {"type":"collect","home_id":second_id,"gesture":"drag"}
	check(not session.inspect(dragged)["ok"],"Simulation must independently reject pre-unlock drag collection")
	session.world.step([dragged])
	check(session.world._state["homes"][1]["stored"]==second_amount,"A rejected drag must not spend the other house's belief")
	screen.world_view.pointer_released.emit()
	commands=[]; screen.is_paused=true
	screen.on_action(Vector2i(26,12),Vector2(26,12))
	check(commands.is_empty(),"Paused inspection must not collect or queue belief")
	screen.queue_free(); session.queue_free()
	await process_frame; await process_frame
	print("Single-click belief, source-gated drag collection and gesture release: %d failures"%failures)
	quit(1 if failures else 0)
