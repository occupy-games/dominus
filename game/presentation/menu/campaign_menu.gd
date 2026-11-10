extends Control
## Campaign selection receives detached source-map descriptors from application.

signal back_requested
signal start_requested(map_id: String)

const Style = preload("res://presentation/ui/style.gd")
var maps: Array = []
var tree: Tree
var title: Label
var details: Label
var start_button: Button
var selected := ""
var items: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(Style.label("Campaigns", 36))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)
	tree = Tree.new()
	tree.custom_minimum_size.x = 320
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.add_theme_color_override("font_selected_color", Style.TEXT)
	body.add_child(tree)
	var root := tree.create_item()
	var groups := {}
	for map: Dictionary in maps:
		var family: String = map["family"]
		if not groups.has(family):
			var group := tree.create_item(root)
			group.set_text(0, family)
			group.set_selectable(0, false)
			group.collapsed = family == "Event maps"
			groups[family] = group
		var item := tree.create_item(groups[family])
		item.set_text(0, str(map["name"]) + ("" if map["available"] else " · unavailable"))
		item.set_metadata(0, map["id"])
		if not map["available"]: item.set_custom_color(0, Style.MUTED)
		items[map["id"]] = item
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 300
	info.add_theme_constant_override("separation", 16)
	panel.add_child(info)
	title = Style.label("", 30)
	info.add_child(title)
	details = Style.label("", 18)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(details)
	start_button = Style.button("Start campaign", func() -> void:
		if not start_button.disabled and not selected.is_empty(): start_requested.emit(selected))
	start_button.icon=load("res://assets/dominus.png")
	start_button.expand_icon=true
	start_button.add_theme_constant_override("icon_max_width",36)
	info.add_child(start_button)
	column.add_child(Style.button("← Main menu", func() -> void: back_requested.emit()))
	tree.item_selected.connect(func() -> void: select_map(str(tree.get_selected().get_metadata(0))))
	tree.item_activated.connect(func() -> void:
		if not start_button.disabled: start_requested.emit(selected))
	select_map("homeworld")
	tree.grab_focus()


func select_map(id: String) -> void:
	for map: Dictionary in maps:
		if map["id"] != id: continue
		selected = id
		if not items[id].is_selected(0): items[id].select(0)
		title.text = str(map["name"])
		start_button.disabled = not map["available"]
		details.text = "Source map · %d × %d\n\n" % [int(map["width"]), int(map["width"])]
		if map["available"]:
			details.text += "Shape the land and grow your followers from this map’s starting position."
			if id != "homeworld": details.text += "\n\nUses the shared opening progression."
		else: details.text += str(map["unavailable_reason"])
		return
