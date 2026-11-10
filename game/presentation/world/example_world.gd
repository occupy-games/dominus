extends Control
## Spacious source-model exhibition. Only visible neighborhoods create render nodes.
## Authoritative exhibit positions arrive as detached layout data from application.

signal back_requested
signal library_requested(id: String)

const Style = preload("res://presentation/ui/style.gd")
const Actors = preload("res://presentation/world/actors.gd")
const PlaneSurface = preload("res://presentation/world/plane_surface.gd")
const SurfaceCamera = preload("res://presentation/world/surface_camera.gd")
const Preview = preload("res://presentation/library/source_model_preview.gd")
const Ground = preload("res://presentation/world/exhibit_ground.gd")
const Building = preload("res://presentation/world/assembled_building.gd")

var layout: Dictionary
var resolve_model: Callable
var resolve_details: Callable
var resolve_building: Callable
var world := Node3D.new()
var navigation := SurfaceCamera.new()
var nodes: Dictionary = {}
var by_id: Dictionary = {}
var model_tree := Tree.new()
var search := LineEdit.new()
var details := VBoxContainer.new()
var detail_panel := PanelContainer.new()
var progress: Label
var selected_id := ""
var desired: Array = []
var queue: Array = []
var refresh_needed := true
var refresh_delay := 0.0
var loaded_count := 0
var group_items: Dictionary = {}
var tree_items: Dictionary = {}
var visible_failures: Dictionary = {}
var preview: Control
var left_panel: PanelContainer
var category_labels: Array[Label3D] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	for item: Dictionary in layout["items"]: by_id[item["id"]] = item
	build_world()
	build_hud()
	build_tree()
	if not layout["categories"].is_empty():
		var region: Dictionary = layout["categories"][0]
		navigation.focus_on(region["bounds"].get_center(), minf(100, region["bounds"].size.length()))
	queue_neighborhood()
	for item: Dictionary in layout["items"]:
		if item["source"] == "sheep.group.bin":
			select_model(item["id"])
			break


func build_world() -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = layout["bounds"].size + Vector2(150, 150)
	floor.mesh = plane
	var center: Vector2 = layout["bounds"].get_center()
	floor.position = Vector3(center.x, -0.04, center.y)
	var material := Ground.material(false)
	floor.material_override = material
	world.add_child(floor)
	for category: Dictionary in layout["categories"]:
		var label := Label3D.new()
		label.text = category["name"]
		label.font = Style.source_font()
		label.font_size = 48
		label.pixel_size = 0.1
		var region: Rect2 = category["bounds"]
		label.position = Vector3(region.get_center().x, 1, region.position.y - 8)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Style.TEXT
		label.outline_modulate = Color.WHITE
		world.add_child(label)
		category_labels.append(label)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.WHITE
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.25
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 0.45
	light.shadow_enabled = true
	world.add_child(light)
	navigation.surface = PlaneSurface.new()
	navigation.bounds = layout["bounds"]
	navigation.maximum_span = maxf(layout["bounds"].size.length() * 1.3, 100)
	world.add_child(navigation)
	navigation.changed.connect(func() -> void: refresh_needed = true)
	navigation.clicked.connect(pick_item)


func build_hud() -> void:
	left_panel = PanelContainer.new()
	left_panel.position = Vector2(16, 16)
	left_panel.custom_minimum_size = Vector2(300, 650)
	left_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(left_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	left_panel.add_child(column)
	column.add_child(Style.button("Main menu", func() -> void: back_requested.emit()))
	column.add_child(Style.label("original game example world", 23))
	var count := Style.label("%d usable models · %d categories\nPlane: %.0f × %.0f world units" % [layout["items"].size(), layout["categories"].size(), layout["bounds"].size.x, layout["bounds"].size.y], 13)
	column.add_child(count)
	search.placeholder_text = "Find a model or source group…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_value: String) -> void: build_tree())
	column.add_child(search)
	model_tree.hide_root = true
	model_tree.custom_minimum_size.y = 330
	model_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	model_tree.item_selected.connect(on_tree_selected)
	column.add_child(model_tree)
	column.add_child(Style.button("Overview of all categories", overview))
	column.add_child(Style.button("Inspect selected model (F)", func() -> void:
		if not selected_id.is_empty(): select_model(selected_id)))
	progress = Style.label("", 12)
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(progress)
	column.add_child(Style.label("Wheel: zoom · RMB drag: orbit\nMMB / Shift+RMB: pan\nWASD / arrows: move · Shift: faster\nF: frame selected · H: hide panels", 12))
	var unresolved: int = layout["excluded"].size()
	if unresolved > 0:
		column.add_child(Style.label("%d models await material recovery.\nUnsupported records remain in the library." % unresolved, 12))
	detail_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	detail_panel.position = Vector2(-390, 16)
	detail_panel.custom_minimum_size = Vector2(374, 570)
	add_child(detail_panel)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.custom_minimum_size.x = 348
	detail_panel.add_child(detail_scroll)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_margin := MarginContainer.new()
	detail_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_margin.add_theme_constant_override("margin_top", 12)
	detail_scroll.add_child(detail_margin)
	detail_margin.add_child(details)
	detail_panel.visible = false
	resized.connect(resize_panels)
	resize_panels()


func resize_panels() -> void:
	if not is_instance_valid(left_panel): return
	left_panel.size.y = maxf(450, size.y - 32)
	detail_panel.size = Vector2(374, maxf(450, size.y - 32))
	model_tree.custom_minimum_size.y = maxf(180, size.y - 470)


func build_tree() -> void:
	model_tree.clear()
	tree_items.clear()
	group_items.clear()
	var root := model_tree.create_item()
	var categories := {}
	var sources := {}
	var families := {}
	var query := search.text.strip_edges().to_lower()
	for item: Dictionary in layout["items"]:
		if not query.is_empty() and not query in (item["name"] + " " + item["source"] + " " + item["category"]).to_lower(): continue
		var category: String = item["category"]
		if not categories.has(category):
			var branch := model_tree.create_item(root)
			branch.set_text(0, category)
			branch.set_metadata(0, {"category": category})
			branch.collapsed = query.is_empty()
			categories[category] = branch
		var source: String = item["source"]
		if not sources.has(source):
			var branch := model_tree.create_item(categories[category])
			branch.set_text(0, source.replace(".group.bin", ""))
			branch.set_metadata(0, {"group": source})
			branch.collapsed = query.is_empty()
			sources[source] = branch
			group_items[source] = branch
		var family_key: String = source + ":" + item["family"]
		if not families.has(family_key):
			var branch := model_tree.create_item(sources[source])
			branch.set_text(0, item["family"])
			branch.set_metadata(0, {"id": item["id"]})
			branch.collapsed = query.is_empty()
			families[family_key] = branch
		var leaf := model_tree.create_item(families[family_key])
		leaf.set_text(0, item["name"])
		leaf.set_tooltip_text(0, item["id"])
		leaf.set_metadata(0, {"id": item["id"]})
		tree_items[item["id"]] = leaf


func on_tree_selected() -> void:
	var selected := model_tree.get_selected()
	if selected == null: return
	model_tree.release_focus()
	var data: Dictionary = selected.get_metadata(0)
	if data.has("id"):
		select_model(data["id"])
	elif data.has("category"):
		for region: Dictionary in layout["categories"]:
			if region["name"] == data["category"]:
				navigation.focus_on(region["bounds"].get_center(), maxf(15, region["bounds"].size.length()))
	elif data.has("group"):
		var bounds := Rect2()
		var first := true
		for item: Dictionary in layout["items"]:
			if item["source"] != data["group"]: continue
			var rect: Rect2 = item["footprint"].grow(3)
			bounds = rect if first else bounds.merge(rect)
			first = false
		navigation.focus_on(bounds.get_center(), maxf(15, bounds.size.length()))


func select_model(id: String) -> void:
	if not by_id.has(id): return
	selected_id = id
	var item: Dictionary = by_id[id]
	navigation.focus_on(item["uv"], maxf(2.0, item["size"].length() * 2.5), item["size"].y * 0.5)
	if not nodes.has(id): load_item(id)
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	var title := Style.label(item["name"], 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(title)
	var source := Style.label(item["source"] + "\n" + item["category"] + " · " + str(item.get("environment", "land")).capitalize(), 12)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(source)
	var buttons := HBoxContainer.new()
	buttons.add_child(Style.button("Close", func() -> void: detail_panel.visible = false))
	buttons.add_child(Style.button("Asset library", func() -> void: library_requested.emit(id)))
	details.add_child(buttons)
	var data: Dictionary = resolve_details.call(id) if resolve_details.is_valid() else resolve_model.call(id)
	if not data.is_empty():
		preview = Preview.new()
		preview.source_data = data
		preview.custom_minimum_size = Vector2(340, 220)
		details.add_child(preview)
		if data["descriptor"].has("assembly_id"):
			var assembly_id: String = data["descriptor"]["assembly_id"]
			details.add_child(Style.button("Inspect verified assembled object", func() -> void: library_requested.emit("object:" + assembly_id)))
	var heading := Style.label("Component parts / source siblings", 14)
	details.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 120)
	details.add_child(scroll)
	var parts := VBoxContainer.new()
	scroll.add_child(parts)
	var related := 0
	for sibling: Dictionary in layout["items"]:
		if sibling["source"] != item["source"] or sibling["family"] != item["family"]: continue
		var sibling_id: String = sibling["id"]
		parts.add_child(Style.button(sibling["name"], func() -> void: select_model(sibling_id)))
		related += 1
	if related <= 1:
		parts.add_child(Style.label("No verified additional parts.\nOther source components have their own plots.", 12))
	else:
		parts.add_child(Style.button("Frame all these components", func() -> void: frame_family(item)))
	detail_panel.visible = true
	if tree_items.has(id):
		model_tree.set_block_signals(true)
		tree_items[id].select(0)
		var parent: TreeItem = tree_items[id].get_parent()
		while parent != null:
			parent.collapsed = false
			parent = parent.get_parent()
		model_tree.set_block_signals(false)
		model_tree.scroll_to_item(tree_items[id])


func frame_family(selected: Dictionary) -> void:
	var bounds := Rect2()
	var first := true
	for item: Dictionary in layout["items"]:
		if item["source"] != selected["source"] or item["family"] != selected["family"]: continue
		var rect: Rect2 = item["footprint"].grow(2)
		bounds = rect if first else bounds.merge(rect)
		first = false
	navigation.focus_on(bounds.get_center(), maxf(8, bounds.size.length()))


func overview() -> void:
	navigation.focus_on(layout["bounds"].get_center(), layout["bounds"].size.length())
	detail_panel.visible = false


func queue_neighborhood() -> void:
	refresh_needed = false
	refresh_delay = 0.12
	desired.clear()
	queue.clear()
	# Conservative view envelope includes tall models, independent of render nodes.
	var aspect := get_viewport_rect().size.x / maxf(get_viewport_rect().size.y, 1)
	var radius := navigation.span * maxf(aspect, 1.0) / maxf(sin(navigation.elevation), 0.12) * 0.8 + 15
	var wanted := {}
	for item: Dictionary in layout["items"]:
		var half_diagonal: float = Vector2(item["size"].x, item["size"].z).length() * 0.5
		if item["uv"].distance_to(navigation.focus) <= radius + half_diagonal or item["id"] == selected_id:
			desired.append(item["id"])
			wanted[item["id"]] = true
			if not nodes.has(item["id"]): queue.append(item["id"])
	queue.sort_custom(func(a: String, b: String) -> bool:
		return by_id[a]["uv"].distance_squared_to(navigation.focus) < by_id[b]["uv"].distance_squared_to(navigation.focus))
	for id: String in nodes.keys():
		if not wanted.has(id):
			if nodes[id].has_meta("label"): nodes[id].get_meta("label").queue_free()
			if nodes[id].has_meta("ground"): nodes[id].get_meta("ground").queue_free()
			nodes[id].queue_free()
			nodes.erase(id)


func load_item(id: String) -> void:
	if nodes.has(id) or visible_failures.has(id): return
	var data: Dictionary = resolve_model.call(id)
	if data.is_empty():
		visible_failures[id] = true
		return
	var item: Dictionary = by_id[id]
	var instance: Node3D
	var info: Dictionary = data["descriptor"].get("building_assembly", {})
	if info.get("base_id", "") == id and resolve_building.is_valid():
		var assembled := Building.new()
		assembled.data = resolve_building.call(id)
		instance = assembled
	else: instance = Actors.mesh(data)
	instance.scale = Vector3.ONE * 0.003
	instance.position = Vector3(item["uv"].x, 0, item["uv"].y) + item["offset"]
	instance.set_meta("source", item["source"])
	world.add_child(instance)
	if item.get("environment", "land") != "land":
		var size: Vector3 = item["size"]
		var water_height := size.y * 0.7 if item["environment"] == "underwater" else -0.015
		var patch := Ground.patch(item["environment"], Vector2(size.x, size.z).max(Vector2(3, 3)) + Vector2(4, 4), water_height)
		patch.position = Vector3(item["uv"].x, 0, item["uv"].y)
		world.add_child(patch)
		instance.set_meta("ground", patch)
	var label := Label3D.new()
	label.text = item["name"]
	label.font = Style.source_font()
	label.font_size = 24
	label.pixel_size = 0.01
	label.position = Vector3(item["uv"].x, item["size"].y + 0.4, item["uv"].y)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Style.TEXT
	label.outline_modulate = Color.WHITE
	label.visibility_range_end = 65
	world.add_child(label)
	instance.set_meta("label", label)
	nodes[id] = instance
	loaded_count += 1


func pick_item(screen: Vector2) -> void:
	var origin := navigation.camera.project_ray_origin(screen)
	var direction := navigation.camera.project_ray_normal(screen)
	var nearest := INF
	var id := ""
	for item: Dictionary in layout["items"]:
		var size: Vector3 = item["size"]
		var base := Vector3(item["uv"].x - size.x * 0.5, 0, item["uv"].y - size.z * 0.5)
		var bounds := AABB(base, size.max(Vector3.ONE * 0.15))
		var hit: Variant = bounds.intersects_ray(origin, direction)
		if hit is Vector3 and hit.distance_squared_to(origin) < nearest:
			nearest = hit.distance_squared_to(origin)
			id = item["id"]
	if not id.is_empty(): select_model(id)


func _process(delta: float) -> void:
	refresh_delay -= delta
	if refresh_needed and refresh_delay <= 0: queue_neighborhood()
	# Bound disk/mesh work per frame; all exhibits remain in the world manifest.
	var start := Time.get_ticks_usec()
	var count := 0
	while not queue.is_empty() and count < 8:
		load_item(queue.pop_front())
		count += 1
		if Time.get_ticks_usec() - start > 6000: break
	progress.text = "%d models in this neighborhood\n%d rendered · %d loading · zoom %.1f" % [desired.size(), nodes.size(), queue.size(), navigation.span]
	for node: Node in nodes.values():
		if node.has_meta("label"):
			node.get_meta("label").visible = navigation.span > 8 and navigation.span < 120
			node.get_meta("label").scale = Vector3.ONE * navigation.span / 22.0
	for label: Label3D in category_labels:
		label.visible = navigation.span > 70
		label.scale = Vector3.ONE * navigation.span / 400.0


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_F and not selected_id.is_empty(): select_model(selected_id)
	elif event.physical_keycode == KEY_HOME: overview()
	elif event.physical_keycode == KEY_H:
		left_panel.visible = not left_panel.visible
		if not left_panel.visible: detail_panel.visible = false
	elif event.physical_keycode == KEY_ESCAPE:
		if detail_panel.visible: detail_panel.visible = false
		else: back_requested.emit()
