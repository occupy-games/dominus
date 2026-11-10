extends SceneTree
## Native rendering check: no timing information is added to the player's HUD.


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
	while view.terrain.is_streaming(): await process_frame
	app.screen.toggle_menu()
	await capture("res://../build/screenshots/campaign-settings-in-view.png")
	app.screen.toggle_menu()
	view.zoom_by(5.0)
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(240):
		var pan := InputEventPanGesture.new()
		pan.delta = Vector2(0.4,0.2)
		pan.shift_pressed = frame > 120
		view._unhandled_input(pan)
		await process_frame
		var now := Time.get_ticks_usec()
		if frame > 10: times.append((now-previous)/1000.0)
		previous = now
	await capture("res://../build/screenshots/campaign-wide-navigation.png")
	times.sort()
	print("Native wide-view frame intervals: median %.2f ms, p95 %.2f ms, max %.2f ms; %d terrain tiles, %d tree batches" % [times[times.size()/2],times[int(times.size()*0.95)],times.back(),view.terrain.chunks.size(),view.trees.get_child_count()])
	app.queue_free()
	await process_frame
	quit()
