extends SceneTree

const FrontEnd = preload("res://application/front_end.tscn")
const SurfaceCamera = preload("res://presentation/world/surface_camera.gd")
const BasePlane = preload("res://presentation/world/plane_surface.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func run() -> void:
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	var view: Variant = app.screen.world_view
	var initial_focus: Vector3 = view.focus
	var initial_zoom: float = view.zoom
	var pan := InputEventPanGesture.new()
	pan.position = Vector2(600,400)
	pan.delta = Vector2(12,-8)
	view._unhandled_input(pan)
	check(not view.focus.is_equal_approx(initial_focus) and view.focus.y == initial_focus.y,"Two-finger trackpad movement must pan parallel to the base plane")
	check(view.zoom == initial_zoom,"Two-finger navigation must not zoom")
	check((view.focus-initial_focus).dot(view.camera.global_basis.x)>0,"Horizontal trackpad navigation must use the newly requested swapped direction")
	var initial_yaw: float = view.yaw
	var initial_elevation: float = view.elevation
	initial_focus = view.focus
	pan.shift_pressed = true
	view._unhandled_input(pan)
	check(view.yaw != initial_yaw and view.elevation != initial_elevation,"Shift + two-finger movement must change both bearing and viewing angle")
	check(view.focus == initial_focus,"Changing the angle must retain the base-plane focus")
	check(view.elevation > initial_elevation, "Negative vertical Shift gesture must raise the viewing angle after reversal")
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = Vector2(600,400)
	pinch.factor = 1.2
	view._unhandled_input(pinch)
	check(is_equal_approx(view.zoom/initial_zoom,pow(1.2,-0.1)),"Pinch must use one tenth of the previous logarithmic zoom sensitivity")
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(600,400)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 0.1
	initial_zoom = view.zoom
	view._unhandled_input(wheel)
	check(is_equal_approx(view.zoom/initial_zoom,pow(0.82,0.01)),"High-resolution wheel deltas must retain their fractional strength")
	var snapshot: Dictionary = app.session.presentation_snapshot()
	check(snapshot["trees"].is_read_only() and snapshot["trees"][0].is_read_only(),"Cached scenery must be detached and immutable")
	var terrain: Variant = view.terrain
	var before := Time.get_ticks_usec()
	view.zoom_by(6.0)
	for step in range(24):
		pan.shift_pressed = false
		view._unhandled_input(pan)
	var event_ms := (Time.get_ticks_usec()-before)/1000.0
	check(event_ms < 100,"Navigation events must enqueue work rather than rebuilding large terrain meshes")
	await process_frame
	check(terrain.worker.is_started() or not terrain.pending.is_empty(),"Large-map terrain must stream through the worker")
	for frame in range(60): await create_timer(0.002).timeout
	check(not terrain.chunks.is_empty(),"Streaming must produce visible source-derived terrain tiles")
	var templates: int = view.tree_templates.size()
	view.update_trees()
	check(view.tree_templates.size()==templates,"Camera movement must reuse existing source tree meshes")
	var built: int=view.trees.builds
	view.update_trees()
	check(view.trees.builds==built,"An unchanged camera region must reuse persistent scenery tiles")
	for tile: Node3D in view.trees.get_children():
		for batch: Node in tile.get_children(): check(batch is MultiMeshInstance3D,"Scenery must use source-mesh or source-imposter batches rather than one draw node per object")
	var nav := SurfaceCamera.new()
	nav.surface = BasePlane.new()
	root.add_child(nav)
	var uv: Vector2 = nav.focus
	var span: float = nav.span
	nav._unhandled_input(pan)
	check(nav.focus != uv and nav.span == span,"Example-world trackpad must use the same pan convention")
	pan.shift_pressed = true
	var pitch: float = nav.elevation
	nav._unhandled_input(pan)
	check(nav.elevation > pitch,"Example-world Shift + trackpad must use the same reversed vertical direction")
	nav.queue_free()
	app.queue_free()
	await process_frame
	print("Trackpad navigation and streamed terrain: %d failures; 25 navigation events %.2f ms" % [failures,event_ms])
	quit(1 if failures else 0)
