extends SceneTree

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	app.screen.goal_panel.visible = false
	for frame in range(12): await process_frame
	while app.screen.world_view.terrain.is_streaming(): await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://../build/screenshots/original-homeworld-opening.png")
	print("Native original Homeworld captured")
	app.queue_free()
	await process_frame
	quit()
