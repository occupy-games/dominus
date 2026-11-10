extends PanelContainer
## Hierarchical preferences, source defaults and explicit save/load/balance actions.
signal setting_changed(key: String,value: Variant)
signal reset_requested(prefix: String)
signal save_requested
signal load_requested
signal reload_constants_requested
signal open_table_requested(table: String)
signal open_constants_requested
signal menu_requested
signal close_requested
const Style = preload("res://presentation/ui/style.gd")
var definitions: Dictionary = {}
var values: Dictionary = {}
var tree := Tree.new()
var editor := VBoxContainer.new()
var status := Label.new()
var selected := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-450
	offset_right=450
	offset_top=-300
	offset_bottom=300
	add_theme_stylebox_override("panel",Style.box(Style.PANEL))
	var column := VBoxContainer.new()
	add_child(column)
	column.add_child(Style.label("Settings",26,Style.TEXT))
	var body := HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(body)
	tree.columns=3
	tree.hide_root=true
	tree.column_titles_visible=true
	tree.set_column_title(0,"Setting")
	tree.set_column_title(1,"Current")
	tree.set_column_title(2,"Default")
	tree.custom_minimum_size.x=540
	tree.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(tree)
	tree.item_selected.connect(select_item)
	editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(editor)
	var files := GridContainer.new()
	files.columns=3
	column.add_child(files)
	files.add_child(Style.button("Save game",func() -> void: save_requested.emit()))
	files.add_child(Style.button("Load game",func() -> void: load_requested.emit()))
	files.add_child(Style.button("Reload all 3 CSV files",func() -> void: reload_constants_requested.emit()))
	for table: String in ["Adobes.csv","Followers.csv","Update.csv"]:
		files.add_child(Style.button(table,func() -> void: open_table_requested.emit(table)))
	column.add_child(status)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color",Style.TEXT)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	footer.add_child(Style.button("Reset all defaults",func() -> void: reset_requested.emit("")))
	footer.add_child(Style.button("Main menu",func() -> void: menu_requested.emit()))
	footer.add_child(Style.button("Close",func() -> void: close_requested.emit()))
	refresh(definitions,values)


func refresh(defs: Dictionary,current: Dictionary) -> void:
	definitions=defs
	values=current
	tree.clear()
	var root := tree.create_item()
	for group: String in definitions:
		var branch := tree.create_item(root)
		branch.set_text(0,definitions[group]["label"])
		branch.set_tooltip_text(0,definitions[group]["label"])
		branch.set_metadata(0,group)
		for key: String in definitions[group]["settings"]:
			var spec: Dictionary = definitions[group]["settings"][key]
			var path := group+"."+key
			var item := tree.create_item(branch)
			item.set_text(0,spec["label"])
			item.set_tooltip_text(0,spec["label"])
			item.set_text(1,display_value(spec,values.get(path,spec["default"])))
			item.set_text(2,display_value(spec,spec["default"]))
			item.set_metadata(0,path)
			if path==selected: item.select(0)
	show_editor()


func display_value(spec: Dictionary,value: Variant) -> String:
	if spec["type"]=="enum": return spec["choices"][int(value)]
	if spec["type"]=="bool": return "On" if value else "Off"
	return str(value)


func select_item() -> void:
	if tree.get_selected()!=null:
		selected=tree.get_selected().get_metadata(0)
		show_editor()


func show_editor() -> void:
	for child: Node in editor.get_children():
		editor.remove_child(child)
		child.queue_free()
	if selected.is_empty(): return
	var parts := selected.split(".")
	if parts.size()==1:
		editor.add_child(Style.label(definitions[parts[0]]["label"],21,Style.TEXT))
		editor.add_child(Style.button("Reset group",func() -> void: reset_requested.emit(selected)))
		return
	var spec: Dictionary = definitions[parts[0]]["settings"][parts[1]]
	var label := Style.label(spec["label"],21,Style.TEXT)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	editor.add_child(label)
	if spec["type"]=="bool":
		var checkbox := CheckButton.new()
		checkbox.button_pressed=values[selected]
		checkbox.text=display_value(spec,values[selected])
		checkbox.toggled.connect(func(value: bool) -> void: setting_changed.emit(selected,value))
		editor.add_child(checkbox)
	elif spec["type"]=="enum":
		var choice := OptionButton.new()
		for text_: String in spec["choices"]: choice.add_item(text_)
		choice.selected=int(values[selected])
		choice.item_selected.connect(func(value: int) -> void: setting_changed.emit(selected,value))
		editor.add_child(choice)
	else:
		var number := SpinBox.new()
		number.min_value=spec["min"]
		number.max_value=spec["max"]
		number.step=spec["step"]
		number.value=values[selected]
		number.value_changed.connect(func(value: float) -> void: setting_changed.emit(selected,value))
		editor.add_child(number)
	editor.add_child(Style.label("Default: "+display_value(spec,spec["default"]),17,Style.TEXT))
	editor.add_child(Style.button("Reset to default",func() -> void: reset_requested.emit(selected)))


func set_status(message: String) -> void:
	status.text=message
