extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func capture(path: String) -> void:
	for frame in range(10): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaigns()
	await capture("res://../build/screenshots/campaign-map-selector.png")
	app.screen.select_map("hubworld_02")
	app.screen.start_button.pressed.emit()
	app.session.set_process(false)
	if app.session.presentation_snapshot()["campaign"]["map_id"] != "hubworld_02":
		push_error("Campaign selection started the wrong map")
		quit(1)
		return
	for frame in range(90): await process_frame
	await capture("res://../build/screenshots/campaign-hubworld-02.png")
	if app.screen.world_view.bathymetry != preload("res://infrastructure/campaign_content.gd").map_definition("hubworld_02")["bathymetry"]:
		push_error("Campaign presentation used the wrong bathymetry")
		quit(1)
		return
	app.queue_free()
	await process_frame
	print("Native campaign selector and selected-map presentation verified")
	quit()
