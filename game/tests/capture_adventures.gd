extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func capture(path: String) -> void:
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func run() -> void:
	preload("res://infrastructure/adventure_content.gd").progress_path="res://../build/capture-voyages.json"
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	await capture("res://../build/screenshots/adventures-main-menu.png")
	app.show_adventures()
	await capture("res://../build/screenshots/adventures-menu.png")
	app.screen.start_button.pressed.emit()
	app.session.set_process(false)
	await capture("res://../build/screenshots/adventures-boat.png")
	app.screen.voyage_hud.launch.pressed.emit()
	app.session.advance_elapsed(0.5)
	await capture("res://../build/screenshots/adventures-island.png")
	app.session.submit({"type":"sculpt_drag","x":23,"z":23,"nx":0,"nz":1,"layer":1,"distance":3,"dx":4,"dz":3,"radius":1})
	for tick in range(100): app.session.advance_elapsed(0.5)
	await capture("res://../build/screenshots/adventures-complete.png")
	app.screen.voyage_next_requested.emit()
	app.session.set_process(false)
	app.screen.voyage_hud.launch.pressed.emit()
	app.session.advance_elapsed(0.5)
	await capture("res://../build/screenshots/adventures-second-island.png")
	app.screen.voyage_return_requested.emit()
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Adventures presentation captured")
	quit()
