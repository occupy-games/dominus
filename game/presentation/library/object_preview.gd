extends VBoxContainer
## Interactive assembly inspection only; all transforms here are presentation.

const Style = preload("res://presentation/ui/style.gd")
var model: Dictionary
var part_meshes: Dictionary = {}
var viewport: SubViewport
var pivot := Node3D.new()
var camera := Camera3D.new()
var yaw := 0.55
var pitch := -0.15
var distance := 3.8
var exploded := false
var rotating := false
var dragging := false
var part_buttons: Array[CheckButton] = []
var show_parts := true


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var controls := HBoxContainer.new()
	controls.add_child(Style.button("Reset view", reset_view))
	var explode := CheckButton.new()
	explode.text = "Explode"
	explode.toggled.connect(func(value: bool) -> void:
		exploded = value
		position_parts())
	if show_parts:
		controls.add_child(explode)
	else:
		explode.free()
	var rotate := CheckButton.new()
	rotate.text = "Rotate"
	rotate.toggled.connect(func(value: bool) -> void: rotating = value)
	controls.add_child(rotate)
	var controls_font := preload("res://presentation/ui/style.gd").source_font()
	controls.add_theme_font_override("font", controls_font)
	add_child(controls)
	var container := SubViewportContainer.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size.y = 140
	container.stretch = true
	container.gui_input.connect(view_input)
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(600, 380)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	world.add_child(pivot)
	world.add_child(camera)
	camera.current = true
	camera.fov = 35
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Style.INK
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d6e5ed")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.6
	world.add_child(light)
	build_meshes()
	var parts_column := GridContainer.new()
	if show_parts:
		var parts_scroll := ScrollContainer.new()
		parts_scroll.custom_minimum_size.y = 100
		add_child(parts_scroll)
		parts_column.columns = 2
		parts_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parts_scroll.add_child(parts_column)
	for part: Dictionary in model["parts"]:
		var toggle := CheckButton.new()
		toggle.text = "%s · %d tris" % [part["name"], part["triangles"].size()]
		toggle.add_theme_font_size_override("font_size", 14)
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.tooltip_text = "%s\nMaterial: %s\nTexture: %s" % [part["source"], part["material_source"], part["texture_source"]]
		toggle.button_pressed = true
		toggle.toggled.connect(func(value: bool) -> void: part_meshes[part["name"]].visible = value)
		parts_column.add_child(toggle)
		part_buttons.append(toggle)
	if not show_parts: parts_column.free()
	update_camera()


func build_meshes() -> void:
	var bounds := AABB()
	var first := true
	for part: Dictionary in model["parts"]:
		for vertex: Array in part["vertices"]:
			var point := Vector3(vertex[0], vertex[1], vertex[2])
			if first:
				bounds = AABB(point, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	var center := bounds.get_center()
	var scale_factor := 3.0 / maxf(bounds.size.length(), 0.001)
	for part: Dictionary in model["parts"]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle: Array in part["triangles"]:
			for corner: Array in triangle:
				var vertex: Array = part["vertices"][int(corner[0])]
				var normal: Array = part["normals"][int(corner[1])]
				var uv: Array = part["uvs"][int(corner[2])]
				surface.set_normal(Vector3(normal[0], normal[1], normal[2]).normalized())
				surface.set_uv(Vector2(uv[0], uv[1]))
				surface.add_vertex((Vector3(vertex[0], vertex[1], vertex[2]) - center) * scale_factor)
		var material := StandardMaterial3D.new()
		material.albedo_texture = part.get("texture_resource")
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.roughness = 0.9
		var mesh := MeshInstance3D.new()
		mesh.name = part["name"]
		mesh.mesh = surface.commit()
		mesh.material_override = material
		pivot.add_child(mesh)
		part_meshes[part["name"]] = mesh


func position_parts() -> void:
	var index := 0
	for mesh: MeshInstance3D in part_meshes.values():
		mesh.position = Vector3((index % 2) * 1.3 - 0.65, index * 0.45, 0) if exploded else Vector3.ZERO
		index += 1


func reset_view() -> void:
	yaw = 0.55
	pitch = -0.15
	distance = 3.8
	update_camera()


func update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(Vector3.ZERO)


func view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 2.5, 12)
			update_camera()
	if event is InputEventMouseMotion and dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.008, -1.25, 1.25)
		update_camera()


func _process(delta: float) -> void:
	if rotating:
		yaw += delta * 0.35
		update_camera()
