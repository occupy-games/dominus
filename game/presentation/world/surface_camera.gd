extends Node3D
## Orbit, zoom and pan in the injected base surface's local tangent frame.

signal changed
signal clicked(position: Vector2)

var preferences: Dictionary = {}
var surface: RefCounted
var camera := Camera3D.new()
var bounds := Rect2(-500, -500, 1000, 1000)
var focus := Vector2.ZERO
var pivot_height := 0.0
var yaw := 0.5
var elevation := 0.8
var span := 45.0
var minimum_span := 0.2
var maximum_span := 2000.0
var orbiting := false
var panning := false
var press_position := Vector2.ZERO
var pointer := Vector2.ZERO


func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 20000
	camera.current = true
	add_child(camera)
	update_camera()


func update_camera() -> void:
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.y = clampf(focus.y, bounds.position.y, bounds.end.y)
	var frame: Transform3D = surface.frame_at(focus)
	var target := frame.origin + frame.basis.y * pivot_height
	var offset := Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	camera.size = span
	camera.position = target + frame.basis * offset * maxf(20, span * 1.5)
	camera.look_at(target, frame.basis.y)
	changed.emit()


func focus_on(uv: Vector2, size: float, height: float = 0.0) -> void:
	focus = uv
	pivot_height = height
	span = clampf(size, minimum_span, maximum_span)
	update_camera()


func pan(direction: Vector2, amount: float) -> void:
	# Movement stays parallel to the local base, independently of orbit pitch.
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(sin(yaw), cos(yaw))
	focus += (right * direction.x + forward * direction.y) * amount
	update_camera()


func hit_surface(screen: Vector2) -> Variant:
	var frame: Transform3D = surface.frame_at(focus)
	var plane := Plane(frame.basis.y, frame.origin + frame.basis.y * pivot_height)
	return plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


func zoom_at(screen: Vector2, factor: float) -> void:
	var before: Variant = hit_surface(screen)
	span = clampf(span * factor, minimum_span, maximum_span)
	update_camera()
	var after: Variant = hit_surface(screen)
	if before is Vector3 and after is Vector3:
		focus += surface.coordinates(before) - surface.coordinates(after)
		update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		pointer = event.position
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed and not event.shift_pressed
			panning = event.pressed and event.shift_pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: press_position = event.position
			elif press_position.distance_to(event.position) < 5: clicked.emit(event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, pow(0.82, event.factor * (float(preferences.get("camera.wheel_sensitivity",0.1)) if event.button_index == MOUSE_BUTTON_WHEEL_UP else -float(preferences.get("camera.wheel_sensitivity",0.1)))))
	elif event is InputEventMouseMotion:
		pointer = event.position
		if orbiting and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.006*float(preferences.get("camera.orbit_speed",1))
			elevation = clampf(elevation + event.relative.y * 0.004*float(preferences.get("camera.orbit_speed",1)), 0.12, 1.52)
			update_camera()
		elif panning and event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			var before: Variant = hit_surface(event.position - event.relative)
			var after: Variant = hit_surface(event.position)
			if before is Vector3 and after is Vector3:
				focus += surface.coordinates(before) - surface.coordinates(after)
				update_camera()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, pow(maxf(event.factor, 0.01), -float(preferences.get("camera.pinch_sensitivity",0.1))))
	elif event is InputEventPanGesture:
		if event.shift_pressed:
			yaw -= event.delta.x * 0.004*float(preferences.get("camera.orbit_speed",1))
			elevation = clampf(elevation - event.delta.y * 0.003*float(preferences.get("camera.orbit_speed",1)), 0.12, 1.52)
			update_camera()
		else:
			var middle := get_viewport().get_visible_rect().size * 0.5
			var before: Variant = hit_surface(middle)
			var after: Variant = hit_surface(middle + Vector2(event.delta.x if preferences.get("camera.reverse_horizontal",true) else -event.delta.x,event.delta.y)*float(preferences.get("camera.pan_speed",1)))
			if before is Vector3 and after is Vector3:
				focus += surface.coordinates(after) - surface.coordinates(before)
				update_camera()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1
	if direction != Vector2.ZERO:
		pan(direction.normalized(), delta * maxf(span * 0.65, 1)*float(preferences.get("camera.keyboard_speed",1)) * (3 if Input.is_physical_key_pressed(KEY_SHIFT) else 1))
