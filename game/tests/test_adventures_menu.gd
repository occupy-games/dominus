extends SceneTree

var failures := 0


func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures+=1


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	check(app.screen.adventures_button!=null,"Main menu must expose Adventures")
	app.screen.adventures_button.pressed.emit()
	check(app.screen.items.size()>200,"Adventures must browse the original voyage inventory")
	var first: String = app.screen.selected
	app.screen.select_mission("event_01__ex01_map05_championintro")
	check(not app.screen.start_button.disabled,"The original champion challenge must now be playable")
	app.show_campaign()
	app.session.set_process(false)
	var home: Node = app.session
	var home_state: Dictionary = home.world.export_state()
	app.show_adventures()
	app.screen.start_button.pressed.emit()
	app.session.set_process(false)
	check(app.home_session==home and app.session!=home,"Island visits must park the original campaign session")
	check(app.screen.voyage_hud.ready_panel.visible,"A voyage must offer follower selection before its timer starts")
	check(not app.screen.original_hud.visible,"Settlement cards must not cover the voyage HUD")
	check(app.screen.world_view.prop_nodes.size()==4,"Original boat, sail, dock and goal must render")
	var dock_found := false
	for prop: Node3D in app.screen.world_view.prop_nodes.values():
		if prop.has_method("set_stage") and prop.components.size()>2: dock_found=true
	check(dock_found,"The source dock must render its full component assembly")
	app.screen.voyage_hud.launch.pressed.emit()
	app.session.advance_elapsed(0.5)
	check(app.screen.snapshot["voyage"]["phase"]=="running" and not app.screen.voyage_hud.ready_panel.visible,"Launch must start the authoritative timer and release followers")
	app.screen.voyage_retry_requested.emit()
	app.session.set_process(false)
	check(app.screen.snapshot["voyage"]["phase"]=="ready" and app.home_session==home,"Retry must reset the island while keeping Homeworld")
	app.screen.voyage_return_requested.emit()
	check(app.session==home and not is_instance_valid(app.home_session),"Return by boat must restore the original session")
	check(home.world.export_state()==home_state,"An island visit must not advance, reset or mutate Homeworld")
	app.show_menu()
	app.screen.continue_button.pressed.emit()
	app.session.set_process(false)
	check(app.session==home and not app.screen.snapshot.has("voyage"),"Continue must resume Homeworld after a boat trip")
	check(home.world.export_state()==home_state,"Recreating Homeworld presentation must preserve its simulation")
	app.show_adventure(first)
	app.session.set_process(false)
	var path := "res://../build/adventure-menu-save.sqlite"
	check(app.session.save_game(path)["ok"],"An island visit must support named saves")
	app.show_adventures()
	app.show_game(false)
	app.session.set_process(false)
	app.load_world_path(path)
	app.session.set_process(false)
	check(app.home_session==home and app.screen.snapshot.has("voyage"),"Loading a voyage from Homeworld must park the current campaign")
	app.screen.voyage_return_requested.emit()
	check(app.session==home and home.world.export_state()==home_state,"Returning from a loaded voyage must preserve Homeworld too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Adventures menu, boat visit and Homeworld return: %d failures"%failures)
	quit(1 if failures else 0)
