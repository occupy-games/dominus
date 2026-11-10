extends Control
## Source voyage browser; application supplies availability and saved results.

signal back_requested
signal start_requested(id: String, difficulty: int)
const Style = preload("res://presentation/ui/style.gd")
var missions: Array = []
var progress: Dictionary = {}
var tree: Tree
var detail: Label
var start_button: Button
var selected := ""
var items := {}
var status_message := ""
var difficulty: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	margin.add_child(column)
	column.add_child(Style.label("Adventures · Voyages",34))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation",20)
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(body)
	tree=Tree.new()
	tree.custom_minimum_size.x=340
	tree.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tree.hide_root=true
	tree.add_theme_color_override("font_selected_color",Style.TEXT)
	body.add_child(tree)
	var root := tree.create_item()
	var groups := {}
	var first := ""
	for mission: Dictionary in missions:
		var family: String = mission["family"]
		if not groups.has(family):
			var group := tree.create_item(root)
			group.set_text(0,"Voyage 1" if family=="event_01" else family.replace("event_","Voyage "))
			group.set_selectable(0,false)
			group.collapsed=family!="event_01"
			groups[family]=group
		var item := tree.create_item(groups[family])
		var result: Dictionary = progress.get(mission["id"],{})
		item.set_text(0,mission["name"]+(" · %d/3"%int(result["stars"]) if result.has("stars") else ("" if mission["available"] else " · unavailable")))
		item.set_metadata(0,mission["id"])
		if not mission["available"]: item.set_custom_color(0,Style.MUTED)
		items[mission["id"]]=item
		if first.is_empty() and mission["available"]: first=mission["id"]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x=300
	info.add_theme_constant_override("separation",14)
	panel.add_child(info)
	var picture := TextureRect.new()
	picture.texture=load("res://assets/extracted/Scaleform/Resources/Info_Panel/Info_Event_01.png")
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size.y=140
	info.add_child(picture)
	difficulty=OptionButton.new()
	for name: String in ["Bronze","Silver","Gold"]: difficulty.add_item(name)
	info.add_child(difficulty)
	difficulty.item_selected.connect(func(_index: int) -> void: select_mission(selected))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	info.add_child(scroll)
	detail=Style.label("",19)
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(detail)
	start_button=Style.button("Set sail",func() -> void:
		if not start_button.disabled: start_requested.emit(selected,difficulty.selected))
	start_button.icon=load("res://assets/dominus.png")
	start_button.expand_icon=true
	start_button.add_theme_constant_override("icon_max_width",36)
	info.add_child(start_button)
	if not status_message.is_empty(): column.add_child(Style.label(status_message,16))
	column.add_child(Style.button("← Main menu",func() -> void: back_requested.emit()))
	tree.item_selected.connect(func() -> void: select_mission(str(tree.get_selected().get_metadata(0))))
	tree.item_activated.connect(func() -> void:
		if not start_button.disabled: start_requested.emit(selected,difficulty.selected))
	select_mission(first)


func select_mission(id: String) -> void:
	for mission: Dictionary in missions:
		if mission["id"]!=id: continue
		if mission.has("difficulties"):
			var selected_mode: Dictionary = mission["difficulties"][difficulty.selected]
			mission=mission.duplicate(false)
			mission.merge(selected_mode,true)
		selected=id
		if not items[id].is_selected(0): items[id].select(0)
		start_button.disabled=not mission["available"]
		detail.text=mission["name"]+"\n\n"
		if mission["available"]:
			detail.text+="%d seconds · Reach the temple with %d followers\n\n"%[int(mission["seconds"]),int(mission["required"])]
			detail.text+=str(mission.get("description",""))
			if mission.get("free_sculpt",false): detail.text+="\n\nFree sculpting."
			detail.text+="\n\nYour Homeworld waits while you are away."
		else: detail.text+=mission["unavailable_reason"]
		return
