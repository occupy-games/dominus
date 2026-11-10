extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func capture(name: String) -> void:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../build/screenshots/"+name+".png")
	print("Captured ",name)


func run() -> void:
	var content := preload("res://infrastructure/adventure_content.gd")
	content.progress_path="res://../build/capture-challenges-profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(content.progress_path))
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	await capture("dominus-logo-menu")
	app.show_campaign()
	app.session.set_process(false)
	# Native self-play must never write the player's real Homeworld save.
	app.session.store.database_path="res://../build/capture-challenges-homeworld.sqlite"
	for id: String in ["event_01__ex01_map05_championintro","event_04__ex04_map01_swamptut1","event_02a__ex02a_map01_expshrineintroeasy","event_03a__ex03a_map01_meteorbarrage"]:
		app.show_adventure(id)
		app.session.set_process(false)
		app.screen.voyage_hud.launch.pressed.emit()
		app.session.advance_elapsed(0.2)
		app.screen.world_view.zoom=65 if id.contains("expshrine") else (95 if id.contains("meteorbarrage") else 40)
		app.screen.world_view.update_camera()
		await capture("voyage-"+id)
	app.show_adventure("event_01__ex01_map01_coretutorial")
	app.session.set_process(false)
	app.session.submit({"type":"start_voyage","followers":8})
	app.session.submit({"type":"sculpt_drag","x":23,"z":23,"nx":0,"nz":1,"layer":1,"distance":3,"dx":4,"dz":3,"radius":1})
	for batch in range(122): app.session.advance_elapsed(0.5)
	await capture("voyage-native-score-rewards")
	app.screen.voyage_return_requested.emit()
	app.show_game(false)
	app.session.set_process(false)
	app.screen.progression_panel.open_card("Sticker_Textile_1")
	await capture("voyage-stickers-in-homeworld")
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Original voyage challenges, reward transfer and Dominus logo presented")
	quit()
