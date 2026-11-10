extends SceneTree

const FrontEnd = preload("res://application/front_end.tscn")
var failures := 0


func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func run() -> void:
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	await process_frame
	app.screen.new_world_button.pressed.emit()
	await process_frame
	var view: Variant = app.screen
	app.session.set_process(false)
	check(view.world_view.terrain.mesh != null, "New world must render the terrain")
	check(view.world_view.actor_nodes.size() == 5, "Followers and sheep must be presented")
	var edge: Dictionary = app.session.find_edge(16, 3, 1)
	check(edge.get("ok", false), "A land edge must be available for the gesture")
	view.drag = edge
	view.drag_start = Vector2(edge["x"], edge["z"])
	view.world_view.layer_drag = true
	var before: Dictionary = app.session.world.snapshot()
	var mesh_before: Mesh = view.world_view.terrain.mesh
	view.on_drag(view.drag_start + Vector2(edge["nx"], edge["nz"]))
	check(view.world_view.terrain.mesh != mesh_before, "Dragging must rebuild live preview geometry")
	check(app.session.world.snapshot() == before, "Live geometry previews must not mutate the simulation")
	view.finish_drag()
	app.session.advance_elapsed(0.1)
	check(app.session.world.snapshot()["sculpted"] == 1, "Release must commit the geometry-modifying drag")
	check(view.snapshot["terrain"] == app.session.world.snapshot()["terrain"], "Presentation must receive committed terrain")
	# A second preview is cancelled, preserving the authoritative geometry.
	edge = app.session.find_edge(16, 3, 1)
	view.drag = edge
	view.drag_start = Vector2(edge["x"], edge["z"])
	view.preview_delta = Vector2i(999, 999)
	view.world_view.layer_drag = true
	before = app.session.world.snapshot()
	view.on_drag(view.drag_start + Vector2(edge["nx"], edge["nz"]))
	view.cancel_drag()
	check(app.session.world.snapshot() == before and not view.world_view.layer_drag, "Cancel must discard the drag")
	view.choose_tool("home")
	var command: Dictionary = {}
	for z in range(10, 23):
		for x in range(10, 23):
			if command.is_empty() and app.session.inspect({"type": "home", "x": x, "z": z})["ok"]:
				command = {"type": "home", "x": x, "z": z}
	view.on_action(Vector2i(command["x"], command["z"]), Vector2(command["x"], command["z"]))
	for i in range(120):
		app.session.advance_elapsed(0.2)
	check(view.snapshot["completed_homes"] == 1 and view.world_view.home_nodes.size() == 1, "HUD input must build and present a completed home")
	view.on_action(Vector2i(command["x"], command["z"]), Vector2(command["x"], command["z"]))
	check(view.home_panel.visible and "100%" in view.home_info.text, "Clicking a dwelling must open its contextual status")
	view.pause_button.pressed.emit()
	check(app.session.paused, "Pause control must stop simulation")
	var tick: int = app.session.world.snapshot()["tick"]
	app.session.advance_elapsed(1)
	check(app.session.world.snapshot()["tick"] == tick, "Paused world must not advance")
	app.show_menu()
	await process_frame
	check(app.screen.continue_button.disabled == false, "Menu must allow continuing the live world")
	app.screen.continue_button.pressed.emit()
	await process_frame
	check(app.screen.snapshot["tick"] == tick, "Returning through the menu must preserve state")
	# Dispatch actual viewport input through picking, HUD routing and the gesture controller.
	app.show_game(true)
	await process_frame
	app.session.set_process(false)
	view = app.screen
	edge = app.session.find_edge(30, 16, 1)
	var start_world: Vector3 = view.world_view.world_position(edge["x"], edge["z"]) + Vector3(edge["nx"], 0, edge["nz"]) * 0.2
	var end_world := start_world + Vector3(edge["nx"], 0, edge["nz"]) * 1.5
	var start_screen: Vector2 = view.world_view.camera.unproject_position(start_world)
	var end_screen: Vector2 = view.world_view.camera.unproject_position(end_world)
	var down := InputEventMouseButton.new()
	down.position = start_screen
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	check(view.world_view.layer_drag, "A pointer press on a visible terrace must grab the layer")
	var move := InputEventMouseMotion.new()
	move.position = end_screen
	move.relative = end_screen - start_screen
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move, true)
	check(not view.drag_command.is_empty(), "Pointer motion must generate a layer edit preview")
	var up := InputEventMouseButton.new()
	up.position = end_screen
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up, true)
	app.session.advance_elapsed(0.1)
	check(app.session.world.snapshot()["sculpted"] == 1, "Real pointer release must commit the layer drag")
	app.queue_free()
	await process_frame
	print("Gameplay and layer-drag integration: %d failures" % failures)
	quit(1 if failures else 0)
