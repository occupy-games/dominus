extends Control
## One canvas pass draws original source badges above projected building roofs.
## This avoids adding a separate 3D draw call for every house at wide zoom.

var camera: Camera3D
var records: Dictionary = {}
var textures: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -1 # World markers stay below cards, settings and other modal UI.


func _draw() -> void:
	if camera == null or not camera.is_inside_tree(): return
	var viewport_size := get_viewport_rect().size
	var width := minf(24, 0.8 * viewport_size.y / maxf(0.1, camera.size))
	if width < 4: return
	var visible_rect := Rect2(Vector2.ZERO, viewport_size).grow(24)
	for badge: Dictionary in records.values():
		if not badge["visible"] or camera.is_position_behind(badge["position"]): continue
		var texture: Texture2D = textures.get(badge["source_sprite"])
		if texture == null: continue
		var point := camera.unproject_position(badge["position"])
		if not visible_rect.has_point(point): continue
		var extent := Vector2(width, width * texture.get_height() / texture.get_width())
		draw_texture_rect(texture, Rect2(point - extent * 0.5, extent), false)
