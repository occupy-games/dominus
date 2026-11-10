extends SceneTree

const FrontEnd = preload("res://application/front_end.tscn")
const Layout = preload("res://simulation/example_layout.gd")
const PlaneSurface = preload("res://presentation/world/plane_surface.gd")
const Actors = preload("res://presentation/world/actors.gd")
var failures := 0


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func run() -> void:
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	await process_frame
	app.screen.example_button.pressed.emit()
	await process_frame
	var view: Variant = app.screen
	var layout: Dictionary = app.example_layout
	var usable := 0
	for model: Dictionary in app.catalog.models:
		if model["material_status"] == "source_texture": usable += 1
	check(usable > 3000 and layout["items"].size() == usable, "Example must contain every usable source model, including LODs and parts")
	check(layout["categories"].size() >= 10 and layout["bounds"].size.x > 500, "Example must provide a large categorized plane")
	check(layout == Layout.new().build(app.catalog.models), "Exhibit layout must be reproducible without presentation")
	var ids := {}
	var bins := {}
	for item: Dictionary in layout["items"]:
		check(not ids.has(item["id"]), "Every source record must have exactly one exhibit")
		ids[item["id"]] = true
		var rect: Rect2 = item["footprint"].grow(2.0)
		check(layout["bounds"].encloses(rect), "World bounds must contain the entire exhibit: " + item["id"])
		var tested := {}
		for x in range(floori(rect.position.x / 16), ceili(rect.end.x / 16) + 1):
			for y in range(floori(rect.position.y / 16), ceili(rect.end.y / 16) + 1):
				var key := Vector2i(x, y)
				for neighbor: Dictionary in bins.get(key, []):
					if tested.has(neighbor["id"]): continue
					tested[neighbor["id"]] = true
					check(not rect.intersects(neighbor["rect"]), "Exhibits need inspection clearance: " + item["id"] + " / " + neighbor["id"])
				if not bins.has(key): bins[key] = []
				bins[key].append({"id": item["id"], "rect": rect})
	for id: String in layout["excluded"]: check(not ids.has(id), "Unresolved material must not get a substitute asset")
	check(view.tree_items.size() == usable, "Navigator must expose every exhibit")
	# Validate every source mesh can actually become a Godot ArrayMesh.
	var checked := 0
	for model: Dictionary in app.catalog.models:
		if model["material_status"] != "source_texture": continue
		var data: Dictionary = app.catalog.model_data(model["id"])
		check(data.get("texture_resource") is Texture2D, "Every usable mesh must load its original texture: " + model["id"])
		var instance := Actors.mesh(data)
		check(instance.mesh.get_surface_count() == 1 and instance.mesh.get_faces().size() == int(model["triangles"]) * 3, "Every usable mesh must render: " + model["id"])
		instance.free()
		checked += 1
		if checked % 200 == 0: await process_frame
	var nav: Variant = view.navigation
	nav.focus_on(Vector2(50, 50), 10, 2.0)
	var y: float = nav.camera.position.y
	nav.pan(Vector2(1, -1).normalized(), 10)
	check(is_equal_approx(nav.camera.position.y, y) and nav.pivot_height == 2.0, "Pan must stay parallel to the base plane without following terrain height")
	var before: Vector3 = nav.camera.position
	var press := InputEventMouseButton.new()
	press.position = Vector2(600, 400)
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	root.push_input(press)
	var event := InputEventMouseMotion.new()
	event.position = Vector2(600, 400)
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	event.relative = Vector2(120, 50)
	root.push_input(event)
	check(not nav.camera.position.is_equal_approx(before), "RMB drag must orbit the camera")
	press.pressed = false
	root.push_input(press)
	nav.zoom_at(Vector2(600, 400), 0.001)
	check(nav.span == nav.minimum_span, "Zoom must reach close component inspection distance")
	nav.zoom_at(Vector2(600, 400), 1e9)
	check(nav.span == nav.maximum_span, "Zoom must reach a full large-world overview")
	# A tilted plane proves navigation uses the base tangent frame, not global XZ.
	var plane := PlaneSurface.new()
	plane.orientation = Basis(Vector3.RIGHT, 0.5)
	nav.surface = plane
	nav.focus_on(Vector2(50, 50), 15, 0)
	var normal: Vector3 = plane.frame_at(nav.focus).basis.y
	var altitude: float = nav.camera.position.dot(normal)
	nav.pan(Vector2(1, 1), 8)
	check(is_equal_approx(nav.camera.position.dot(normal), altitude), "Navigation must remain parallel to an arbitrarily oriented base plane")
	nav.surface = PlaneSurface.new()
	var part_id := "tents.group.bin:45c20b56"
	view.select_model(part_id)
	check(view.selected_id == part_id and view.detail_panel.visible and view.nodes.has(part_id), "Selecting a component must frame and inspect its actual source mesh")
	view.search.text = "tents"
	view.search.text_changed.emit("tents")
	await process_frame
	check(view.tree_items.size() > 0 and view.tree_items.size() < usable, "Search must narrow the source/category tree")
	var saved_focus: Vector2 = nav.focus
	view.library_requested.emit(part_id)
	await process_frame
	check(app.screen.selected_path == "model:" + part_id, "Exhibit must link to the exact source model in the library")
	app.screen.leave()
	await process_frame
	check(app.screen.navigation.focus.is_equal_approx(saved_focus), "Returning from inspection must preserve the example-world camera")
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Large example world and surface navigation: %d models, %d failures" % [checked, failures])
	quit(1 if failures else 0)
