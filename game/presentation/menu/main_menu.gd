extends Control

signal library_requested
signal quit_requested
signal new_world_requested
signal continue_requested
signal example_requested
signal campaign_requested
signal adventures_requested
signal start_requested

const Style = preload("res://presentation/ui/style.gd")
var library_button: Button
var new_world_button: Button
var continue_button: Button
var example_button: Button
var campaign_button: Button
var adventures_button: Button
var start_button: TextureButton
var resume_enabled := false
var status_message := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var header := HBoxContainer.new()
	var edition := Style.label("DOMINUS     /     A GOD GAME", 13, Style.MUTED)
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(edition)
	header.add_child(Style.label("EARLY DEVELOPMENT", 12, Style.GOLD))
	column.add_child(header)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	column.add_child(body)
	var center := CenterContainer.new()
	center.custom_minimum_size.x = 400
	body.add_child(center)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.custom_minimum_size.x = 390
	center.add_child(actions)
	actions.add_child(Style.label("SHAPE THE LAND. INSPIRE A WORLD.", 12, Style.GOLD))
	var title := Style.label("Dominus", 76)
	title.add_theme_font_override("font", Style.serif())
	actions.add_child(title)
	actions.add_child(Style.label("Every world begins with a possibility.\nExplore the pieces that will bring this one to life.", 16, Style.MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	actions.add_child(spacer)
	campaign_button = Style.button("Campaigns · Homeworld and other maps", func() -> void: campaign_requested.emit())
	actions.add_child(campaign_button)
	adventures_button = Style.button("Adventures · Voyages by boat", func() -> void: adventures_requested.emit())
	actions.add_child(adventures_button)
	new_world_button = Style.button("Development sandbox", func() -> void: new_world_requested.emit())
	new_world_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	actions.add_child(new_world_button)
	continue_button = Style.button("Continue world", func() -> void: continue_requested.emit())
	continue_button.disabled = not resume_enabled
	continue_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	actions.add_child(continue_button)
	example_button = Style.button("Example world · model collection", func() -> void: example_requested.emit())
	actions.add_child(example_button)
	library_button = Style.button("Asset library", func() -> void: library_requested.emit())
	library_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	library_button.add_theme_color_override("font_color", Style.GOLD)
	actions.add_child(library_button)
	var quit_button := Style.button("Quit", func() -> void: quit_requested.emit())
	quit_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	actions.add_child(quit_button)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(brand)
	start_button=TextureButton.new()
	start_button.texture_normal=load("res://assets/dominus.png")
	start_button.ignore_texture_size=true
	start_button.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	start_button.custom_minimum_size=Vector2(280,280)
	start_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	start_button.size_flags_vertical=Control.SIZE_EXPAND_FILL
	start_button.tooltip_text="Continue world" if resume_enabled else "Start Homeworld"
	start_button.pressed.connect(func() -> void:
		if resume_enabled: continue_requested.emit()
		else: start_requested.emit())
	brand.add_child(start_button)
	var play_label := Style.label("Continue" if resume_enabled else "Start",24)
	play_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(play_label)
	var footer := HBoxContainer.new()
	var note := Style.label("THE WORLD IS TAKING SHAPE", 12, Style.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	footer.add_child(Style.label("LOCAL ASSET COLLECTION     /     01", 12, Style.MUTED))
	column.add_child(footer)
	if not status_message.is_empty():
		column.add_child(Style.label(status_message, 14, Style.GOLD))
	campaign_button.grab_focus()
