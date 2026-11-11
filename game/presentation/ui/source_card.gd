extends TextureButton
## Original portrait illustration and original small-card border, without stretching art.

var source: Dictionary = {}
var detail := false
signal resource_dragged(resource: String,active: bool)
var resource_id := ""
var resource_count := 0
var resource_drag_enabled := true
var accept_resource: Callable
var assign_resource: Callable
var progress := -1.0
var progress_textures: Dictionary = {}
var applied_resources: Array = []
var progress_bar: Control
var applied_images: Array = []
var dragging := false


func _ready() -> void:
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	set_notify_transform(true)
	visibility_changed.connect(refresh_image)
	resized.connect(refresh_image)
	resized.connect(layout_research)
	mouse_exited.connect(restore_progress)
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: refresh_image())
			ancestor.get_h_scroll_bar().value_changed.connect(func(_value: float) -> void: refresh_image())
		ancestor = ancestor.get_parent()
	tooltip_text = str(source.get("title", "")) + "\n" + str(source.get("description", ""))
	if progress>=0:
		progress_bar=preload("res://presentation/ui/source_pill.gd").new()
		progress_bar.rim_texture=progress_textures.get("IWProgbar_Grey.png")
		progress_bar.cap_texture=progress_textures.get("GFX_IWProgbarRound_Cyan.png")
		progress_bar.value=progress
		add_child(progress_bar)
	for applied: Dictionary in applied_resources:
		var picture := TextureRect.new()
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(picture)
		applied_images.append(picture)
	layout_research()
	if source.get("frame") == null:
		refresh_image.call_deferred()
		return
	var frame := TextureRect.new()
	frame.texture = source["frame"]
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	if progress_bar!=null: move_child(progress_bar,-1)
	refresh_image.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready(): refresh_image()
	if what==NOTIFICATION_DRAG_END:
		restore_progress()
		if dragging:
			dragging=false
			resource_dragged.emit(resource_id,false)


func layout_research() -> void:
	if progress_bar!=null:
		progress_bar.position=Vector2(size.x*0.08,size.y*0.86)
		progress_bar.size=Vector2(size.x*0.84,maxf(5,size.y*0.045))
	for i in range(applied_images.size()):
		applied_images[i].position=Vector2(size.x*(0.12+0.12*(i%4)),size.y*(0.42+0.09*(i/4)))
		applied_images[i].size=Vector2(size.x*0.42,size.y*0.31)


func restore_progress() -> void:
	if progress_bar!=null: progress_bar.value=progress


func _get_drag_data(_position: Vector2) -> Variant:
	if not resource_drag_enabled or resource_id.is_empty() or resource_count<=0: return null
	var preview := TextureRect.new()
	preview.texture=texture_normal
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size=Vector2(72,82)
	preview.position=-preview.size*0.5
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	dragging=true
	resource_dragged.emit(resource_id,true)
	return {"type":"dominus_resource","resource":resource_id}


func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	if not data is Dictionary or data.get("type")!="dominus_resource" or not data.get("resource") is String or not accept_resource.is_valid(): restore_progress(); return false
	var verdict: Variant=accept_resource.call(str(data["resource"]))
	if not verdict is Dictionary or not verdict.get("ok",false): restore_progress(); return false
	if progress_bar!=null: progress_bar.value=float(verdict.get("progress",progress))
	return true


func _drop_data(position_: Vector2,data: Variant) -> void:
	if _can_drop_data(position_,data) and assign_resource.is_valid(): assign_resource.call(str(data["resource"]))
	restore_progress()


func refresh_image() -> void:
	if not is_inside_tree(): return
	var shown := is_visible_in_tree()
	var ancestor := get_parent()
	while shown and ancestor != null:
		if ancestor is ScrollContainer:
			shown = get_global_rect().intersects(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	if not shown:
		texture_normal = null
		for picture: TextureRect in applied_images: picture.texture=null
		return
	var resolve: Callable = source.get("resolve_texture", Callable())
	if texture_normal == null and resolve.is_valid(): texture_normal = resolve.call(source, detail)
	for i in range(applied_images.size()):
		if applied_images[i].texture!=null: continue
		var entry: Dictionary=applied_resources[i]
		var resolve_applied: Callable=entry.get("resolve_texture",Callable())
		if resolve_applied.is_valid(): applied_images[i].texture=resolve_applied.call(entry,false)
