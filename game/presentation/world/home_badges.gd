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
		var texture: Texture2D = textures.get(badge["source_sprite"])
		var bounds := badge_bounds(badge,texture,width)
		if bounds.has_area() and visible_rect.intersects(bounds): draw_texture_rect(texture,bounds,false,Color(1,1,1,badge.get("opacity",1.0)))


func badge_bounds(badge: Dictionary,texture: Texture2D,width: float) -> Rect2:
	if not badge.get("visible",false) or texture==null or width<4 or camera.is_position_behind(badge["position"]): return Rect2()
	var point := camera.unproject_position(badge["position"])
	var extent := Vector2(width,width*texture.get_height()/texture.get_width())
	return Rect2(point-extent*0.5,extent)


func hit(screen: Vector2,id: int) -> bool:
	if camera==null or not records.has(id): return false
	var badge: Dictionary=records[id]
	var width := minf(24,0.8*get_viewport_rect().size.y/maxf(0.1,camera.size))
	return badge_bounds(badge,textures.get(badge["source_sprite"]),width).has_point(screen)
