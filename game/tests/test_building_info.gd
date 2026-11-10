extends SceneTree

const Session = preload("res://application/game_session.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
const Info = preload("res://infrastructure/building_info.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	root.size=Vector2i(1000,760)
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	session.new_campaign(preload("res://tests/fixtures/campaign_economy.gd").definition())
	session.submit({"type":"home","x":12,"z":12,"rank":1})
	session.advance_elapsed(0.1)
	var state := session.presentation_snapshot()
	check(state["homes"].size()==1,"The building detail check requires an actual constructed plot")
	if state["homes"].is_empty(): session.free(); quit(1); return
	var id := int(state["homes"][0]["id"])
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=session.inspect
	screen.inspect_building=session.inspect_building
	screen.resolve_building_info=Info.record
	screen.building_info_labels=Info.content()["labels"]
	screen.intent.connect(session.submit)
	root.add_child(screen)
	session.changed.connect(screen.apply_snapshot)
	screen.apply_snapshot(state)
	var before := session.world.export_state()
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	check(screen.selected_home==id and screen.building_panel.dock.visible,"Selecting an abode must reveal its original-style info buttons")
	check(session.world.export_state()==before,"Selecting an abode must not upgrade, collect, spend, or queue a sculpt")
	check(screen.building_panel.picture.texture!=null and screen.building_panel.title.text=="Shelter","The selection must use the source tent illustration and localized title")
	check(screen.building_panel.stats["progress"]<1,"Construction must display the selected building's actual progress")
	var query: Dictionary=session.inspect_building(id)
	query["occupants"]=9999
	check(session.inspect_building(id)["occupants"]!=9999,"Building queries must detach their values from authoritative state")
	# The Info control must open the real window without issuing gameplay input.
	var info_button: TextureButton=screen.building_panel.dock.get_child(2).get_child(0)
	info_button.pressed.emit()
	check(screen.building_panel.popup.visible,"The Info button must open the building details")
	for batch in range(300): session.advance_elapsed(0.5)
	state=session.presentation_snapshot()
	var home: Dictionary=state["homes"][0]
	check(screen.building_panel.stats["complete"] and screen.building_panel.stats["occupants"]==home["residents"],"An open detail window must follow actual completion and occupancy changes")
	check(screen.building_panel.occupancy.text=="%d / %d"%[home["residents"],home["capacity"]],"Occupied and available space must be legible in the selection row")
	check(screen.building_panel.row_values.has("LOC_ROWNAME_HOME_TIME_TILL_FULL"),"The completed abode must show the original next-follower row")
	var stable_rows: Array=screen.building_panel.rows.get_children()
	screen.update_home_info()
	check(screen.building_panel.rows.get_children()==stable_rows,"Live numeric updates must retain the existing row controls")
	# Production inspection uses supplied authoritative work state. Distinguish
	# a deployed worker from one currently harvesting; no gameplay is advanced.
	var production_state: Dictionary=session.world.export_state()["state"]
	var field: Dictionary=home.duplicate(true)
	field["id"]=9999
	field["rank"]=1
	field["capacity"]=1
	field["harvest_rate"]=2.0
	field["harvest_accumulator"]=10.0
	field["max_belief"]=50
	production_state["homes"].append(field)
	production_state["followers"][0]["workplace"]=9999
	production_state["followers"][0]["state"]="walking"
	for kind: String in ["farm","mine"]:
		field["kind"]=kind
		var waiting := preload("res://simulation/building_stats.gd").inspect(production_state,9999)
		check(waiting["workers"]==1 and waiting["workers_working"]==0 and waiting["harvest_seconds"]<0,"A travelling %s worker must not produce a false harvest countdown"%kind)
		production_state["followers"][0]["state"]="farming" if kind=="farm" else "mining"
		var working := preload("res://simulation/building_stats.gd").inspect(production_state,9999)
		check(working["workers_working"]==1 and working["harvest_seconds"]==20.0,"The %s countdown must use actual batch progress and active workers"%kind)
		screen.building_panel.present(working,Info.record(working),false,false)
		check(screen.building_panel.picture.texture!=null and screen.building_panel.row_values.has("LOC_ROWNAME_%s_WORKERS"%["FARM" if kind=="farm" else "MINE"]),"The %s detail must show its own original illustration and work rows"%kind)
		production_state["followers"][0]["state"]="walking"
	screen.update_home_info()
	if "--capture-building-info" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("res://../build/building-info.png")
	# Exact-number persistence and the threaded query owner must expose the same values.
	var codec := preload("res://infrastructure/world_store.gd").new()
	var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(session.world.export_state()))))
	check(session.world.restore(saved,RandomNumberGenerator.new()),"Building stats must survive actual world restoration")
	session.refresh_queries()
	var direct := session.inspect_building(id)
	session.threaded=true
	check(session.inspect_building(id)==direct,"Threaded building inspection must use the detached query world")
	root.size=Vector2i(640,480)
	await process_frame
	await process_frame
	var panel: Rect2=screen.building_panel.popup.get_global_rect()
	check(root.get_visible_rect().encloses(panel),"The original-style details must remain inside a smaller window")
	screen.building_panel.popup.hide()
	screen.is_paused=true
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	check(screen.selected_home==id and screen.building_panel.dock.visible,"Paused games must still allow inspecting buildings")
	screen.queue_free()
	session.queue_free()
	await process_frame
	await process_frame
	print("Original building selection, live statistics and detached queries: %d failures"%failures)
	quit(1 if failures else 0)
