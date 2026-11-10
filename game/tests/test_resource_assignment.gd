extends SceneTree

const Session = preload("res://application/game_session.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func mouse(position_: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=position_
	event.global_position=position_
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	root.push_input(event,true)


func motion(position_: Vector2,relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=position_
	event.global_position=position_
	event.relative=relative
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)


func drag_resource(source: Control,target: Control) -> void:
	var start := source.get_global_rect().get_center()
	var end := target.get_global_rect().get_center()
	motion(start,Vector2.ZERO)
	mouse(start,true)
	motion(start+Vector2(0,-24),Vector2(0,-24))
	await process_frame
	check(root.gui_is_dragging(),"Dragging from the resource strip must start an actual Godot UI drag")
	motion(end,end-start-Vector2(0,-24))
	await process_frame
	mouse(end,false)
	await process_frame


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	session.new_campaign(preload("res://tests/fixtures/campaign_economy.gd").definition())
	session.receive_voyage_rewards({"earned":{"Sticker_ReligiousObject_3":2,"Sticker_Textile_1":1,"Sticker_Rare_Settlement":1}},preload("res://infrastructure/adventure_content.gd").reward_rules())
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=session.inspect
	screen.intent.connect(session.submit)
	root.add_child(screen)
	session.changed.connect(screen.apply_snapshot)
	screen.apply_snapshot(session.presentation_snapshot())
	screen.progression_panel.open_card("Card_DoubleClick")
	await process_frame
	await process_frame
	var panel: Control=screen.progression_panel
	var payload := {"type":"dominus_resource","resource":"Sticker_ReligiousObject_3"}
	var original := session.world.export_state()
	check(panel.detail_card._can_drop_data(Vector2.ZERO,payload),"The advance portrait must accept its actual required resource")
	check(not panel.detail_card._can_drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Textile_1"}),"An unrelated resource must not be assignable to the advance")
	check(session.world.export_state()==original,"Hover previews and invalid drops must not spend stock or change research")
	await drag_resource(panel.resource_slots["Sticker_ReligiousObject_3"],panel.detail_card)
	session.advance_elapsed(0.1)
	var state := session.presentation_snapshot()
	check(state["progression"]["inventory"]["Sticker_ReligiousObject_3"]==1,"The first real UI drop must consume exactly one owned resource")
	check(state["progression"]["assigned_resources"].get("Card_DoubleClick",{}).get("Card_ReligiousObject_1")==1,"The assigned resource must belong to its target card")
	check(not "Card_DoubleClick" in state["progression"]["completed"] and not session.inspect({"type":"dig","x":30,"z":30})["ok"],"A partially supplied advance must remain locked")
	check(state["progression"]["card_progress"]["Card_DoubleClick"]=={"filled":1,"total":2,"complete":false},"The card's progress must reflect its partial assignment")
	check(panel.detail_card.applied_resources.size()==1 and panel.detail_card.progress==0.5,"The portrait must retain the applied resource artwork and half-filled bar")
	var codec := Store.new()
	var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(session.world.export_state()))))
	check(session.world.restore(saved,RandomNumberGenerator.new()),"Partially assigned resources must survive the production save codec")
	var database := "/private/tmp/dominus-resource-assignment-%d.sqlite3"%OS.get_process_id()
	session.store.database_path=database
	check(session.save_game().get("ok",false) and session.load_game().get("ok",false),"A partially supplied card must survive the real SQLite save/load path")
	DirAccess.remove_absolute(database)
	check(session.presentation_snapshot()["progression"]["assigned_resources"]["Card_DoubleClick"]["Card_ReligiousObject_1"]==1,"Loading SQLite must preserve the card's spent resource")
	var branch := preload("res://simulation/world.gd").new()
	check(branch.restore(saved,RandomNumberGenerator.new()),"A legacy completion continuation must restore")
	branch.step([{"type":"claim_card","card":"Card_DoubleClick"}])
	check(branch.snapshot(false)["progression"]["inventory"]["Sticker_ReligiousObject_3"]==0 and "Card_DoubleClick" in branch.snapshot(false)["progression"]["completed"],"Compatible completion commands must charge only the unassigned remainder")
	var malformed: Dictionary=saved.duplicate(true)
	malformed["state"]["progression"]["assigned_resources"]["Card_DoubleClick"]["Card_ReligiousObject_1"]=-1
	check(not branch.restore(malformed,RandomNumberGenerator.new()),"Invalid assignment counters must be rejected before restoration")
	session.refresh_queries()
	screen.apply_snapshot(session.presentation_snapshot())
	await process_frame
	await process_frame
	await drag_resource(panel.resource_slots["Sticker_ReligiousObject_3"],panel.detail_card)
	session.advance_elapsed(0.1)
	state=session.presentation_snapshot()
	check(state["progression"]["inventory"]["Sticker_ReligiousObject_3"]==0 and "Card_DoubleClick" in state["progression"]["completed"],"The final drop must finish the advance without charging its recipe again")
	check(session.inspect({"type":"dig","x":30,"z":30})["ok"],"The completed advance must enable the ordinary terrain command")
	check(not session.inspect({"type":"research_card","card":"Card_DoubleClick","sticker":"Sticker_ReligiousObject_3"})["ok"],"Completed advances must reject further resource assignments")
	panel.open_card("Card_Settlement_Farming")
	await process_frame
	await process_frame
	await drag_resource(panel.resource_slots["Sticker_Rare_Settlement"],panel.detail_card)
	session.advance_elapsed(0.1)
	state=session.presentation_snapshot()
	check("Card_Settlement_Farming" in state["progression"]["completed"] and "GodPower_PlaceSettlement_2" in state["progression"]["powers"],"Typed resources dropped on an advance must unlock its playable power")
	# Gallery portraits are targets too, without first opening their details.
	panel.open_card("Card_MaxRank_2")
	var target: Control=panel.gallery_items["Card_AbodeType1_Rank1"].get_child(0)
	check(target._can_drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Textile_1"}),"The gallery portrait must expose the same authoritative drop gate")
	target._drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Textile_1"})
	session.advance_elapsed(0.1)
	check(session.world.house_spec()["rank"]==2,"Dropping on the gallery card must apply the actual abode upgrade")
	if "--capture-resource-assignment" in OS.get_cmdline_user_args():
		panel.open_card("Card_DoubleClick")
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("res://../build/resource-assignment.png")
	screen.queue_free()
	session.queue_free()
	await process_frame
	await process_frame
	print("Original resource dragging, partial assignments and card completion: %d failures"%failures)
	quit(1 if failures else 0)
