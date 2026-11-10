extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var app: Variant=load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	for frame in range(12): await process_frame
	var size_before := DisplayServer.window_get_size()
	var mode_before := DisplayServer.window_get_mode()
	app.show_campaign()
	for frame in range(12): await process_frame
	print("WINDOW before ",size_before," mode ",mode_before," after ",DisplayServer.window_get_size()," mode ",DisplayServer.window_get_mode())
	if DisplayServer.window_get_size()!=size_before or DisplayServer.window_get_mode()!=mode_before:
		push_error("Starting a campaign must preserve the user's maximized window")
		quit(1)
		return
	print("Campaign preserved native window mode ",mode_before," and size ",size_before)
	app.queue_free()
	await process_frame
	quit()
