extends SceneTree

func _initialize() -> void:
	run.call_deferred()


func capture(path: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	var view: Variant = app.screen.world_view
	var rock := Vector2i(-1,-1)
	for z in range(156,177):
		for x in range(165,186):
			if rock.x>=0: break
			var command: Dictionary = view.progression_at(Vector2(x,z))
			if command.get("type")=="tap_object" and app.session.inspect(command)["ok"]: rock=Vector2i(x,z)
	if rock.x<0:
		push_error("No original rock available near the start")
		quit(1)
		return
	for tap in range(2):
		app.screen.on_action(rock,Vector2(rock))
		app.session.advance_elapsed(0.1)
	for tick in range(34): app.session.advance_elapsed(0.1)
	while view.terrain.is_streaming(): await process_frame
	await capture("res://../build/screenshots/original-card-discovery-roboto.png")
	app.screen.progression_panel.confirm_button.pressed.emit()
	app.session.advance_elapsed(0.1)
	app.screen.progression_panel.visible=false
	view.focus=Vector3(218-511.5,0,247-511.5)
	view.zoom=12
	view.update_camera()
	for frame in range(3): await process_frame
	while view.terrain.is_streaming(): await process_frame
	print("Chest view: height ",view.height_at(218,247)," focus ",view.focus," region ",view.terrain_region," tiles ",view.terrain.chunks.size()," processing ",view.is_processing())
	print("Chest pick: ",view.progression_at(Vector2(218,247)))
	await capture("res://../build/screenshots/original-chest-freed.png")
	app.screen.on_action(Vector2i(218,247),Vector2(218,247))
	app.session.advance_elapsed(0.1)
	print("Chest reward: ",app.screen.snapshot["progression"]["last_reward"]," panel ",app.screen.progression_panel.visible)
	await create_timer(1.3).timeout
	await capture("res://../build/screenshots/original-chest-reward-roboto.png")
	print("Native original rock discovery, card completion and chest reward presented")
	app.queue_free()
	await process_frame
	quit()
