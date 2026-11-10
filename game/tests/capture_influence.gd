extends SceneTree

func _initialize() -> void:
	run.call_deferred()


func capture(path: String) -> void:
	for frame in range(3): await process_frame
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	var player := preload("res://simulation/campaign_player.gd").new()
	while app.screen.world_view.terrain.is_streaming(): await process_frame
	await capture("res://../build/screenshots/influence-opening.png")
	for tick in range(850):
		if tick%10==0:
			for command: Dictionary in player.commands(app.session.world): app.session.submit(command)
		app.session.advance_elapsed(0.1)
		app.screen.progression_panel.visible=false
		if tick%20==0: await process_frame
		if app.screen.snapshot["followers"].size()>=6: break
	while app.screen.world_view.terrain.is_streaming(): await process_frame
	await capture("res://../build/screenshots/influence-expanded.png")
	var state: Dictionary = app.screen.snapshot
	if state["followers"].size()<6 or state["progression"]["player_level"]<2:
		push_error("Native self-play did not earn an expansion")
		quit(1)
		return
	print("Native influence expanded through player commands: %d followers, level %d" % [state["followers"].size(),state["progression"]["player_level"]])
	app.queue_free()
	await process_frame
	quit()
