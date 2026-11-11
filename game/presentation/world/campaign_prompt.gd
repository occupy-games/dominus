extends Control
## Source localization and source tooltip texture; callbacks remain commands.

signal acknowledged(id: int)
var textures: Dictionary = {}
var view: Node3D
var messages: Dictionary = {}
var current: Dictionary = {}
var ui_target: Callable


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=30
	resized.connect(layout_messages)


func apply_snapshot(snapshot: Dictionary,lesson_prompt: Dictionary={}) -> void:
	if not snapshot.has("opening") and not snapshot.has("leash_lesson") and not snapshot.has("weyworld"):
		hide()
		return
	show()
	var opening: Dictionary = snapshot.get("opening",snapshot.get("weyworld",{}))
	if snapshot.has("leash_lesson"):
		var prompt: Dictionary=snapshot["leash_lesson"]["prompt"] if lesson_prompt.is_empty() else lesson_prompt
		opening={"messages":[],"definition":{"messages":{}}}
		if not prompt.is_empty():
			var id: int=prompt["id"]
			var message:={"id":id,"callback":true if prompt["ack"] else null}
			var entry:={"text":prompt["text"],"strType":"Gold"}
			if prompt.has("follower"): message["anchor"]={"kind":"follower","id":prompt["follower"]}
			elif prompt.has("position"): entry["pos3d"]={"1":prompt["position"][0],"2":prompt["position"][1]}
			else: entry["pos2d"]={"1":0.5,"2":0.3}
			opening["definition"]["messages"][str(id)]=entry
			opening["messages"].append(message)
	current={}
	var active_messages: Array = opening["messages"].duplicate(true)
	var tips := {}
	for key: String in opening.get("tips",{}):
		var tip: Dictionary = opening["tips"][key]
		if tip.has("position"):
			var id := -int(key)
			var point: Array=tip["position"]
			tips[id]={"text":opening["definition"].get("tip_text",{}).get(tip["key"],""),"pos3d":{"1":point[0],"2":point[1],"height":float(point[2])-float(snapshot["source_map"]["sea_level"])*0.3}}
			active_messages.append({"id":id,"callback":null})
			continue
		for follower: Dictionary in snapshot["followers"]:
			if int(follower["id"])!=int(tip["follower"]): continue
			var id := -int(key)
			tips[id]={"text":opening["definition"].get("tip_text",{}).get(tip["key"],""),"pos3d":{"1":follower["x"],"2":follower["z"]}}
			active_messages.append({"id":id,"callback":null})
	for active: Dictionary in active_messages:
		var id := int(active["id"])
		var entry: Dictionary = tips[id] if id<0 else opening["definition"]["messages"].get(str(id),{})
		if int(active.get("visible_tick",0))>int(snapshot["tick"]) or entry.get("group","") in opening.get("hidden_tables",[]): continue
		if entry.has("options"): entry=entry["options"][int(active.get("option",0))]
		if entry.is_empty(): continue
		if id in [1005,5003,5004] and active.get("anchor",{}).is_empty(): continue
		if active.has("anchor"):
			var anchor: Dictionary = active["anchor"]
			if anchor["kind"] in ["rock","plot","temple"]:
				entry=entry.duplicate(true)
				entry["pos3d"]={"1":anchor["x"],"2":anchor["z"]}
				if anchor.has("height"): entry["pos3d"]["height"]=anchor["height"]
			elif anchor["kind"]=="follower":
				for follower: Dictionary in snapshot["followers"]:
					if int(follower["id"])==int(anchor["id"]):
						entry=entry.duplicate(true)
						entry["pos3d"]={"1":follower["x"],"2":follower["z"]}
		current[id]=entry
		if not messages.has(id):
			var button := Button.new()
			button.text=entry["text"]
			button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			button.add_theme_font_override("font",preload("res://presentation/ui/style.gd").source_font())
			button.add_theme_font_size_override("font_size",18)
			button.add_theme_color_override("font_color",Color.BLACK)
			var background := StyleBoxTexture.new()
			background.texture=textures.get("Tooltip_01.png")
			for side: int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
				background.set_texture_margin(side,14)
				background.set_content_margin(side,14)
			for state: String in ["normal","hover","pressed","focus"]: button.add_theme_stylebox_override(state,background)
			button.pressed.connect(func() -> void: acknowledged.emit(id))
			add_child(button)
			messages[id]=button
		messages[id].text=entry["text"]
		messages[id].mouse_filter=Control.MOUSE_FILTER_STOP if active.get("callback")!=null or id==4 else Control.MOUSE_FILTER_IGNORE
	for id: int in messages.keys():
		if not current.has(id):
			remove_child(messages[id])
			messages[id].queue_free()
			messages.erase(id)
	layout_messages()


func layout_messages() -> void:
	var offset := 0.0
	for id: int in messages:
		var button: Button = messages[id]
		var entry: Dictionary = current[id]
		var width := minf(440,maxf(180,size.x-40))
		var font := preload("res://presentation/ui/style.gd").source_font()
		var height := maxf(52,font.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_CENTER,width-28,18).y+28)
		button.custom_minimum_size=Vector2(width,height)
		button.size=Vector2(width,height)
		var center := Vector2(size.x*0.5,size.y*0.18+offset)
		if entry.has("pos2d"): center=Vector2(float(entry["pos2d"]["1"])*size.x,float(entry["pos2d"]["2"])*size.y)
		elif entry.has("gui") and ui_target.is_valid():
			var target: Rect2=ui_target.call(entry)
			if target.has_area():
				center=target.get_center()+Vector2(0,(target.size.y+height)*0.5+12)
				if target.get_center().y>size.y*0.5: center.y=target.position.y-height*0.5-12
		elif entry.has("pos3d") and is_instance_valid(view):
			var point: Dictionary = entry["pos3d"]
			var position: Vector3=view.world_position(float(point["1"]),float(point["2"]))
			if point.has("height"): position.y=float(point["height"])
			elif point.has("3"): position.y=float(point["3"])-float(view.state["source_map"]["sea_level"])*0.3
			center=view.camera.unproject_position(position)+Vector2(0,-75)
		button.position=Vector2(clampf(center.x-button.size.x*0.5,10,maxf(10,size.x-button.size.x-10)),clampf(center.y-button.size.y*0.5,10,maxf(10,size.y-button.size.y-10)))
		offset+=button.size.y+8
