extends Control
## Rounded counters assembled from original left cap, center strip and mirrored cap.

var cap_texture: Texture2D
var rim_texture: Texture2D
var max_value := 1.0:
	set(number): max_value = maxf(1, number); queue_redraw()
var value := 0.0:
	set(number): value = number; queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if cap_texture == null or rim_texture == null: return
	var source := cap_texture.get_size()
	var cap := size.y * source.x / source.y
	draw_style_box(rim_style(), Rect2(Vector2.ZERO, size))
	var filled := size.x * clampf(value / max_value, 0, 1)
	if filled <= 0: return
	# Both ends follow the moving fill, including short progress intervals.
	cap=minf(cap,filled/2)
	draw_texture_rect(cap_texture,Rect2(0,0,cap,size.y),false)
	if filled>cap*2:
		draw_texture_rect_region(cap_texture,Rect2(cap,0,filled-cap*2,size.y),Rect2(source.x-1,0,1,source.y))
	draw_set_transform(Vector2(filled,0),0,Vector2(-1,1))
	draw_texture_rect(cap_texture,Rect2(0,0,cap,size.y),false)
	draw_set_transform(Vector2.ZERO)


func rim_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = rim_texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_texture_margin(side, rim_texture.get_width() * 0.5 - 1)
	return style
