extends Control
## HUD and gestures. Commands and validation queries are injected by application.

signal intent(command: Dictionary)
signal menu_requested
signal save_path_requested(path: String)
signal load_path_requested(path: String)
signal setting_changed(key: String,value: Variant)
signal reset_settings_requested(prefix: String)
signal reload_constants_requested
signal open_table_requested(table: String)
signal open_constants_requested
signal save_requested
signal pause_requested
signal speed_requested
signal models_requested
signal voyage_return_requested
signal voyage_retry_requested
signal voyage_next_requested

const WorldView = preload("res://presentation/world/world_view.gd")
const Style = preload("res://presentation/ui/style.gd")
const WorldAudio = preload("res://presentation/world/world_audio.gd")
var inspect_action: Callable
var inspect_building: Callable
var resolve_building_info: Callable
var building_info_labels: Dictionary = {}
var building_panel: Control
var selected_building_kind := "home"
var locate_edge: Callable
var landscape_texture: Texture2D
var follower_assets: Dictionary = {}
var audio_assets: Dictionary = {}
var sheep_assets: Dictionary = {}
var scenery_assets: Dictionary = {}
var terrain_palette: Array[Color] = []
var resolve_model: Callable
var placement_model: Dictionary = {}
var placement_turns := 0
var audio := WorldAudio.new()
var world_view := WorldView.new()
var snapshot: Dictionary = {}
var tool := "sculpt"
var tool_buttons: Dictionary = {}
var belief_label: Label
var population_label: Label
var goal_label: Label
var message_label: Label
var hover_label: Label
var goal_panel: PanelContainer
var pause_panel: PanelContainer
var home_panel: PanelContainer
var home_info: Label
var pause_button: Button
var speed_button: Button
var layer_choice: OptionButton
var width_choice: OptionButton
var selected_home: Variant = -1
var belief_sweep := false
var rain_held := false
var finger_held := false
var meteor_swipe_started := -1
var meteor_swipe_origin := Vector2.ZERO
var belief_sweep_start := Vector2.ZERO
var belief_sweep_seen: Dictionary = {}
var drag: Dictionary = {}
var drag_command: Dictionary = {}
var drag_start := Vector2.ZERO
var preview_delta := Vector2i(999, 999)
var is_paused := false
var completed_before := 0
var message_time := 0.0
var campaign_mode := false
var campaign_cards: Dictionary = {}
var card_buttons: Dictionary = {}
var hud_textures: Dictionary = {}
var original_hud: Control
var progression_panel: Control
var powers_panel: Control
var resolve_building: Callable
var resolve_unit: Callable
var power_assets: Dictionary = {}
var settings_definitions: Dictionary = {}
var settings_values: Dictionary = {}
var save_directory := ""
var save_path := ""
var file_dialog: FileDialog
var settings_status := ""
var voyage_definition: Dictionary = {}
var voyage_hud: Control
var campaign_prompt: Control
var shrine_rewards: Dictionary = {}
var leash_candidate := -1
var leash_home := -1
var leash_followers: Array[int] = []
var leash_hold := 0.0
var leash_active := false
var leash_line: Line2D
var leash_prompt_id := -1
var leash_click: Dictionary = {}
const FARM_POWER := "GodPower_PlaceSettlement_2"
const BUILDER_POWER := "GodPower_PlaceSettlement_1"
const MINING_POWER := "GodPower_PlaceSettlement_3"
var farm_controls: HBoxContainer
var farm_preview_button: Button
var farm_confirm_button: Button
var farm_ring: Line2D
var farm_point := Vector2i(-1,-1)
var farm_dragging := false
var farm_preview_key: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio.assets = audio_assets
	add_child(audio)
	world_view.detail_texture = landscape_texture
	world_view.follower_assets = follower_assets
	world_view.sheep_assets = sheep_assets
	world_view.scenery_assets = scenery_assets
	world_view.terrain.colors = terrain_palette
	world_view.resolve_model = resolve_model
	world_view.resolve_building = resolve_building
	world_view.resolve_unit = resolve_unit
	world_view.status_textures = hud_textures
	add_child(world_view)
	world_view.pointer_action.connect(on_action)
	world_view.pointer_moved.connect(on_hover)
	world_view.drag_moved.connect(on_drag)
	world_view.drag_released.connect(finish_drag)
	world_view.double_action.connect(double_action)
	world_view.pointer_dragged.connect(on_pointer_dragged)
	world_view.pointer_released.connect(end_belief_sweep)
	world_view.pointer_released.connect(release_lesson_leash)
	world_view.pointer_released.connect(func() -> void: release_meteor(world_view.pointer_screen))
	world_view.pointer_released.connect(func() -> void: farm_dragging=false)
	world_view.observer_changed.connect(func(observation: Dictionary) -> void: intent.emit(observation))
	build_hud()
	if campaign_mode:
		campaign_prompt=preload("res://presentation/world/campaign_prompt.gd").new()
		campaign_prompt.textures=hud_textures
		campaign_prompt.view=world_view
		campaign_prompt.ui_target=tutorial_target
		campaign_prompt.acknowledged.connect(func(id: int) -> void: intent.emit({"type":"campaign_ack","id":id}))
		add_child(campaign_prompt)
	if not voyage_definition.is_empty():
		original_hud.hide()
		voyage_hud=preload("res://presentation/world/voyage_hud.gd").new()
		voyage_hud.definition=voyage_definition
		voyage_hud.textures=hud_textures
		voyage_hud.cards=campaign_cards
		voyage_hud.power_assets=power_assets
		voyage_hud.power_requested.connect(func(power: String) -> void:
			cancel_drag()
			tool="sculpt" if power.is_empty() else power)
		voyage_hud.start_requested.connect(func(count: int) -> void: intent.emit({"type":"start_voyage","followers":count}))
		voyage_hud.return_requested.connect(func() -> void: voyage_return_requested.emit())
		voyage_hud.retry_requested.connect(func() -> void: voyage_retry_requested.emit())
		voyage_hud.next_requested.connect(func() -> void: voyage_next_requested.emit())
		add_child(voyage_hud)


func panel(position: Vector2, minimum: Vector2, parent: Node = self) -> PanelContainer:
	var node := PanelContainer.new()
	node.position = position
	node.custom_minimum_size = minimum
	node.add_theme_stylebox_override("panel", Style.box(Color(0.91, 0.92, 0.99, 0.95), 18, Color("f7f4e9")))
	parent.add_child(node)
	return node


func text(value: String, font_size: int = 16) -> Label:
	var node := Style.label(value, font_size, Color("354452"))
	return node


func round_button(symbol: String, color: Color, callback: Callable) -> Button:
	var button := Button.new()
	button.text = symbol
	button.custom_minimum_size = Vector2(64, 64)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 27)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state_name, Style.box(color.lightened(0.12) if state_name == "hover" else color, 40, Color("fffaf0")))
	button.pressed.connect(callback)
	return button


func build_hud() -> void:
	if campaign_mode:
		build_campaign_hud()
		return
	var top_left := HBoxContainer.new()
	top_left.position = Vector2(24, 24)
	top_left.add_theme_constant_override("separation", 12)
	add_child(top_left)
	var guide := round_button("☷", Color("48a9cb"), func() -> void: goal_panel.visible = not goal_panel.visible)
	guide.tooltip_text = "Show sanctuary goals and controls"
	top_left.add_child(guide)
	var counters := panel(Vector2.ZERO, Vector2(245, 76), top_left)
	var values := VBoxContainer.new()
	counters.add_child(values)
	population_label = text("3 followers · 2 sheep", 17)
	values.add_child(population_label)
	belief_label = text("◉ 80 belief", 19)
	belief_label.add_theme_color_override("font_color", Color("ac4b7a"))
	values.add_child(belief_label)
	if campaign_mode:
		var cards := HBoxContainer.new()
		cards.position = Vector2(380,20)
		cards.add_theme_constant_override("separation",6)
		add_child(cards)
		for id: String in ["Card_MaxRank_2","Card_DoubleClick","Card_AbodeType_2"]:
			if not campaign_cards.has(id): continue
			var card := Style.button("", func() -> void: intent.emit({"type":"claim_card","card":id}))
			card.custom_minimum_size = Vector2(76,96)
			card.expand_icon = true
			card.icon = campaign_cards[id]["texture"]
			card.tooltip_text = campaign_cards[id]["title"] + " · " + campaign_cards[id]["description"]
			cards.add_child(card)
			card_buttons[id] = card
	var top_right := HBoxContainer.new()
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.position = Vector2(-230, 24)
	top_right.add_theme_constant_override("separation", 10)
	add_child(top_right)
	pause_button = round_button("Ⅱ", Color("8d9db9"), func() -> void: pause_requested.emit())
	pause_button.tooltip_text = "Pause / resume (Space)"
	top_right.add_child(pause_button)
	speed_button = round_button("1×", Color("7da99d"), func() -> void: speed_requested.emit())
	speed_button.tooltip_text = "Switch between normal and triple speed"
	top_right.add_child(speed_button)
	top_right.add_child(round_button("⚙", Color("9ba6b9"), toggle_menu))
	goal_panel = panel(Vector2(24, 125), Vector2(255, 210))
	var goals := VBoxContainer.new()
	goals.add_theme_constant_override("separation", 10)
	goal_panel.add_child(goals)
	goals.add_child(text("A quiet beginning", 21))
	goal_label = text("", 15)
	goals.add_child(goal_label)
	var instructions := text("Grab either side of a terrace edge.\nDrag outward to extend land,\ninward to retract the layer.\nRelease to commit; Esc cancels.\n\nRMB orbit · WASD pan\nWheel / pinch / + − zoom\nSpace pauses", 13)
	goals.add_child(instructions)
	var dock := HBoxContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dock.position = Vector2(-240, -114)
	dock.add_theme_constant_override("separation", 18)
	add_child(dock)
	var definitions := [["sculpt", "↔", "1 · Sculpt", Color("c44e89")], ["home", "⌂", "2 · Home · 12", Color("4ba5c5")], ["sheep", "♧", "3 · Sheep · 8", Color("8aa653")], ["collect", "◉", "4 · Collect", Color("c99c46")]]
	if campaign_mode:
		definitions = [["sculpt","↔","1 · Sculpt",Color("c44e89")],["home","⌂","2 · Home",Color("4ba5c5")],["collect","◉","4 · Collect",Color("c99c46")]]
	for definition: Array in definitions:
		var column := VBoxContainer.new()
		dock.add_child(column)
		var key: String = definition[0]
		var button := round_button(definition[1], definition[3], func() -> void: choose_tool(key))
		button.tooltip_text = "Drag a terrain edge" if key == "sculpt" else str(definition[2])
		column.add_child(button)
		tool_buttons[key] = button
		var label := text(definition[2], 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	var options := HBoxContainer.new()
	options.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	options.position = Vector2(24, -105)
	add_child(options)
	layer_choice = OptionButton.new()
	layer_choice.add_item("Layer: auto")
	for level in range(1, 8):
		layer_choice.add_item("Layer %d" % level)
	options.add_child(layer_choice)
	width_choice = OptionButton.new()
	width_choice.add_item("Narrow")
	width_choice.add_item("Medium")
	width_choice.add_item("Wide")
	width_choice.selected = 1
	options.add_child(width_choice)
	var zoom_controls := HBoxContainer.new()
	zoom_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	zoom_controls.position = Vector2(-198, -100)
	zoom_controls.add_child(text("Zoom", 15))
	var zoom_out := Style.button("−", func() -> void: world_view.zoom_by(1.0 / 0.82))
	zoom_out.tooltip_text = "Zoom out · − / wheel / pinch"
	zoom_controls.add_child(zoom_out)
	var zoom_in := Style.button("+", func() -> void: world_view.zoom_by(0.82))
	zoom_in.tooltip_text = "Zoom in · + / wheel / pinch"
	zoom_controls.add_child(zoom_in)
	add_child(zoom_controls)
	hover_label = text("Drag an exposed edge to shape your island.", 15)
	hover_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hover_label.position = Vector2(-280, -153)
	hover_label.custom_minimum_size.x = 560
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hover_label)
	message_label = text("", 17)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-280, 30)
	message_label.custom_minimum_size.x = 560
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message_label)
	home_panel = panel(Vector2(24, 125), Vector2(255, 145))
	home_panel.visible = false
	var home_column := VBoxContainer.new()
	home_panel.add_child(home_column)
	home_column.add_child(text("Dwelling", 23))
	home_info = text("", 15)
	home_column.add_child(home_info)
	home_column.add_child(Style.button("Collect belief", func() -> void: intent.emit({"type": "collect"})))
	build_settings_menu()
	choose_tool("sculpt")


func build_campaign_hud() -> void:
	var hud := preload("res://presentation/world/original_hud.gd").new()
	hud.textures = hud_textures
	hud.cards = campaign_cards
	hud.powers = power_assets
	hud.settings_requested.connect(toggle_menu)
	hud.collect_requested.connect(func() -> void: intent.emit({"type":"collect"}))
	hud.sculpt_requested.connect(func() -> void:
		if timeline_tutorial(snapshot): return
		powers_panel.open_book(); progression_panel.visible=false)
	hud.card_requested.connect(func(id: String) -> void:
		if id=="Card_Settlement_Farming" and snapshot.get("opening",{}).get("farming_step")==0:
			intent.emit({"type":"campaign_farm_card"})
		elif id=="Card_GrainToBuild" and snapshot.get("opening",{}).get("superfast_step")==0:
			intent.emit({"type":"claim_card","card":id})
		elif id in ["Card_Adv_Fountain","Card_Adv_GodSeed_1"] and inspect_action.call({"type":"claim_card","card":id}).get("ok",false):
			intent.emit({"type":"claim_card","card":id})
		elif not request_timeline() and not request_level_card(): progression_panel.open_card(id))
	hud.collection_requested.connect(func() -> void:
		if not request_timeline() and not request_level_card(): progression_panel.open_book()
		powers_panel.hide())
	hud.power_requested.connect(func(power: String) -> void:
		if timeline_tutorial(snapshot): return
		powers_panel.open_card("Card_"+power)
		progression_panel.hide())
	add_child(hud)
	original_hud = hud
	progression_panel = preload("res://presentation/world/progression_panel.gd").new()
	progression_panel.cards = campaign_cards
	progression_panel.textures=hud_textures
	progression_panel.inspect_command = inspect_action
	progression_panel.close_handler=close_cards
	progression_panel.command_requested.connect(func(command: Dictionary) -> void: intent.emit(command))
	progression_panel.power_requested.connect(select_power)
	add_child(progression_panel)
	progression_panel.visibility_changed.connect(func() -> void:
		var opening: Dictionary=snapshot.get("opening",{})
		if not progression_panel.visible and (opening.get("promised_step")==8 or opening.get("shrine_step")==1 or opening.get("belief_step")==1 or opening.get("pit_card_open",false) or opening.get("dock_card_open",false) or opening.get("fountain_card_open",false) or opening.get("god_seed_step")==1 or opening.get("farming_step")==1 or opening.get("superfast_step")==1 or opening.get("leash_step")==1 and not opening.get("leash_mission_pending",false)):
			intent.emit({"type":"campaign_dismiss_level_card"})
		if not progression_panel.visible and (opening.get("capacity_step")==2 or opening.get("capacity_step")==1 and progression_panel.selected=="Card_Capacity_1"):
			intent.emit({"type":"campaign_capacity_card_closed"}))
	powers_panel = preload("res://presentation/world/progression_panel.gd").new()
	powers_panel.mode="powers"
	powers_panel.cards=campaign_cards
	powers_panel.textures=hud_textures
	powers_panel.inspect_command=inspect_action
	powers_panel.command_requested.connect(func(command: Dictionary) -> void: intent.emit(command))
	powers_panel.power_requested.connect(select_power)
	add_child(powers_panel)
	powers_panel.visibility_changed.connect(func() -> void:
		if not snapshot.get("opening",{}).get("finger_status",{}).is_empty():
			intent.emit({"type":"campaign_finger_menu","show":powers_panel.visible}))
	# Controller fields used by keyboard/picking; these are not campaign HUD.
	var internal := Control.new()
	internal.visible = false
	add_child(internal)
	layer_choice = OptionButton.new()
	layer_choice.add_item("Auto")
	for level in range(1,64): layer_choice.add_item(str(level))
	internal.add_child(layer_choice)
	width_choice = OptionButton.new()
	for value in ["1","3","5"]: width_choice.add_item(value)
	width_choice.selected = 1
	internal.add_child(width_choice)
	population_label = Label.new()
	belief_label = Label.new()
	goal_label = Label.new()
	hover_label = Label.new()
	message_label = Label.new()
	home_info = Label.new()
	pause_button = Button.new()
	speed_button = Button.new()
	goal_panel = PanelContainer.new()
	home_panel = PanelContainer.new()
	for node: Control in [population_label,belief_label,goal_label,hover_label,message_label,home_info,pause_button,speed_button,goal_panel,home_panel]: internal.add_child(node)
	building_panel=preload("res://presentation/world/building_panel.gd").new()
	building_panel.textures=hud_textures
	building_panel.labels=building_info_labels
	building_panel.action_requested.connect(building_action)
	build_farm_controls()
	add_child(building_panel)
	build_settings_menu()
	choose_tool("sculpt")


func choose_tool(value: String) -> void:
	cancel_drag()
	meteor_swipe_started=-1
	if value == "collect":
		intent.emit({"type": "collect"})
		return
	if value!=tool: cancel_god_seed_hint()
	if value!=tool: cancel_finger()
	tool = value
	selected_home = -1
	selected_building_kind="home"
	home_panel.visible = false
	if building_panel!=null: building_panel.hide_selection()
	for key: String in tool_buttons:
		tool_buttons[key].modulate = Color.WHITE if key == tool else Color(0.8, 0.85, 0.9)
	toast("Drag a layer edge to shape the land." if tool == "sculpt" else ("Choose a flat 2 × 2 plot near a free follower." if tool == "home" else "Choose dry land for a sheep. First complete a home."))


func arm_model_placement(descriptor: Dictionary) -> void:
	cancel_drag()
	placement_model = descriptor.duplicate(true)
	placement_turns = 0
	tool = "model"
	toast("Place %s · click in the world · R rotates · 1 returns to sculpting." % descriptor["name"])


func placement_command(cell: Vector2i) -> Dictionary:
	return {"type": "place_model", "model_id": placement_model.get("id", ""), "x": cell.x, "z": cell.y, "turns": placement_turns}


func apply_snapshot(data: Dictionary, events: Array = []) -> void:
	var timeline_was_open: bool=snapshot.get("opening",{}).get("timeline_open",false)
	snapshot = data
	world_view.apply_snapshot(data)
	world_view.finger_preview=tool=="GodPower_FingerOfGod" and data.get("opening",{}).get("finger_status",{}).get("active",false)
	audio.set_rain_active(rain_held and not is_paused and data.get("opening",{}).has("rain_cast"))
	if has_building_selection(): update_home_info()
	if data.has("voyage"):
		voyage_hud.apply_snapshot(data)
		for event: Dictionary in events:
			play_simulation_sound(event)
			if event["type"]=="voyage_alert": voyage_hud.hint.text=event["message"]
		return
	if data.has("leash_lesson"):
		original_hud.show_settings_only()
		update_lesson_prompt(true)
		for event: Dictionary in events:
			if event["type"]=="campaign_camera": world_view.apply_campaign_camera(event)
		return
	if campaign_mode:
		refresh_shrine_rewards()
		campaign_prompt.apply_snapshot(data)
		original_hud.apply_snapshot(data)
		progression_panel.apply_snapshot(data)
		powers_panel.apply_snapshot(data)
		if timeline_tutorial(data):
			if data["opening"].get("timeline_open",false):
				if not progression_panel.visible: progression_panel.open_card(data["opening"]["level_card"])
			else: progression_panel.hide()
		elif timeline_was_open: progression_panel.hide()
		for event: Dictionary in events:
			play_simulation_sound(event)
			if event["type"]=="beautify_terrain" and tool=="GodPower_Beautify" and not is_paused: audio.beautify_contact()
			if event["type"]=="campaign_camera": world_view.apply_campaign_camera(event)
			if event["type"]=="campaign_pit_beam": world_view.play_pit_beam(event["site"])
			if event["type"]=="campaign_finger_down": world_view.finger_view.strike(event)
			if event["type"]=="campaign_meteor_impact": world_view.meteor_view.impact(event)
			if event["type"]=="campaign_finger_ended" and tool=="GodPower_FingerOfGod":
				finger_held=false
				tool="sculpt"
				choose_tool("sculpt")
			if event["type"] in ["chest_opened","card_discovered","campaign_show_card"] and not str(event.get("card","")).is_empty(): progression_panel.open_card(event["card"])
			elif event["type"]=="campaign_timeline_opened": progression_panel.open_card(event["card"])
			elif event["type"]=="campaign_timeline_closed": progression_panel.hide()
			elif event["type"]=="claim_card" and progression_panel.selected==event["card"] and not timeline_tutorial(data): progression_panel.visible=false
			elif event["type"]=="use_power" and tool==event.get("power","") and tool.begins_with("GodPower_PlaceSettlement_"): choose_tool("sculpt")
			elif event["type"]=="use_power" and tool=="GodPower_PlaceGiftFountain" and tool==event.get("power",""): choose_tool("sculpt")
			elif event["type"]=="use_power" and tool in ["GodPower_PlaceBeliefCollect","GodPower_PlaceCapacity","GodPower_PlaceSpeed","GodPower_Swamp"] and tool==event.get("power",""): choose_tool("sculpt")
			elif event["type"] in ["campaign_farm_confirm","campaign_builder_confirm","campaign_mining_confirm"]: choose_tool("sculpt")
		return
	population_label.text = "%d followers · %d sheep · %d%% happy" % [data["followers"].size(), data["sheep"].size(), data["happiness"]]
	belief_label.text = "◉ %d belief" % data["belief"]
	goal_label.text = "%s Shape a terrain layer\n%d / 3 homes complete\n%d / 5 sheep in the flock\n%d / 20 belief collected" % ["✓" if data["sculpted"] > 0 else "○", mini(data["completed_homes"], 3), mini(data["sheep"].size(), 5), mini(data["collected"], 20)]
	if data.has("campaign"):
		goal_label.text = "Original Homeworld · opening\n\nShape terraces to make room.\nFollowers settle free, flat plots.\nCollect belief from their homes.\n\n%d / 10 followers · Tents\n%d / 15 · Sculpting Upgrade\n%d / 30 · Construction" % [mini(10,data["followers"].size()),mini(15,data["followers"].size()),mini(30,data["followers"].size())]
		for id: String in card_buttons:
			card_buttons[id].disabled = not inspect_action.call({"type":"claim_card","card":id})["ok"]
			card_buttons[id].modulate = Color.WHITE if id in data["campaign"]["cards"] or not card_buttons[id].disabled else Color(0.65,0.65,0.65)
	if data["completed_homes"] > completed_before:
		toast("A home is ready. Collect its belief; sheep are now unlocked.")
	completed_before = data["completed_homes"]
	for event: Dictionary in events:
		toast(event["message"])
		audio.play_event(event["type"])
	if data["won"]:
		goal_label.text = "✓ Opening chapter complete\nYour settlement has discovered Construction.\nContinue shaping Homeworld." if campaign_mode else "✓ Sanctuary established!\nYour people and flock thrive.\nKeep shaping your world."
	if has_building_selection():
		update_home_info()


func has_building_selection() -> bool:
	return selected_home is String or (selected_home is int and selected_home>=0)


func update_home_info() -> void:
	if campaign_mode:
		if not inspect_building.is_valid() or building_panel==null: return
		var info: Dictionary=inspect_building.call(selected_home,selected_building_kind)
		if info.is_empty():
			selected_home=-1
			selected_building_kind="home"
			building_panel.hide_selection()
			return
		var art: Dictionary=resolve_building_info.call(info) if resolve_building_info.is_valid() else {}
		var collect := {"type":"collect_settlement","id":selected_home} if selected_building_kind=="settlement" else {"type":"collect","home_id":selected_home}
		var can_voyage: bool=selected_building_kind=="temple" and snapshot.get("opening",{}).get("events_step",-1)>=0 and selected_home==snapshot["opening"]["definition"].get("dock_site_id") and info["complete"]
		var ark_action: String=""
		if not is_paused and inspect_action.is_valid():
			if info.get("site_type")=="Wayland_Ark" and inspect_action.call({"type":"campaign_ark_sail","id":selected_home}).get("ok",false):
				ark_action=snapshot["opening"]["definition"]["ark"]["sail_labels"]["button"]
			elif info.get("kind")=="ark" and inspect_action.call({"type":"weyworld_release_ark","id":selected_home}).get("ok",false):
				ark_action=building_info_labels.get("LOC_BUTTON_SETTLEMENT_ASSIGN_BUILDERS","Builders")
		building_panel.present(info,art,selected_building_kind!="temple" and inspect_action.is_valid() and inspect_action.call(collect).get("ok",false),selected_building_kind=="home" and inspect_action.is_valid() and inspect_action.call({"type":"upgrade_home","id":selected_home}).get("ok",false),selected_building_kind=="temple" and not is_paused and inspect_action.is_valid() and inspect_action.call({"type":"repair_shrine","id":selected_home}).get("ok",false),can_voyage,ark_action)
		return
	for home: Dictionary in snapshot["homes"]:
		if home["id"] == selected_home:
			var build_ticks: int = snapshot.get("build_ticks",60)
			home_info.text = "Construction: %d%%\nBelief waiting: %d\n%s" % [mini(100, int(home["progress"] / float(build_ticks) * 100)), home["stored"], "A worker needs a clear route." if home["stalled"] else ("A place for your people." if home["progress"] >= build_ticks else "Your follower is building.")]
			home_panel.visible = true
			goal_panel.visible = false


func building_action(action: String) -> void:
	if is_paused or not has_building_selection(): return
	if action=="ark":
		if selected_building_kind=="temple": confirm_ark_departure()
		else: intent.emit({"type":"weyworld_release_ark","id":selected_home})
		return
	if action=="voyage" and selected_building_kind=="temple":
		intent.emit({"type":"campaign_dock_go","id":selected_home})
		return
	if action=="repair" and selected_building_kind=="temple":
		intent.emit({"type":"repair_shrine","id":selected_home})
		return
	if action=="upgrade" and selected_building_kind=="home": intent.emit({"type":"upgrade_home","id":selected_home})
	elif action=="collect": intent.emit({"type":"collect_settlement","id":selected_home} if selected_building_kind=="settlement" else {"type":"collect","home_id":selected_home})


func confirm_ark_departure() -> void:
	var labels: Dictionary=snapshot["opening"]["definition"]["ark"]["sail_labels"]
	var id: Variant=selected_home
	var spaces:=int(building_panel.stats["capacity"])-int(building_panel.stats["occupants"])
	var dialog:=ConfirmationDialog.new()
	dialog.title=labels["title"]
	dialog.dialog_text=labels["full"] if spaces==0 else "%s %d %s"%[labels["spaces_before"],spaces,labels["spaces_after"]]
	dialog.ok_button_text=labels["button"]
	dialog.theme=theme
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		intent.emit({"type":"campaign_ark_sail","id":id})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func request_level_card() -> bool:
	var opening: Dictionary=snapshot.get("opening",{})
	if opening.get("promised_step")!=7 and opening.get("shrine_step")!=0 and opening.get("belief_step")!=0 and opening.get("leash_step")!=0: return false
	if opening.get("leash_step")==0 and not inspect_action.call({"type":"campaign_show_level_card"}).get("ok",false): return false
	intent.emit({"type":"campaign_show_level_card"})
	return true


func request_timeline() -> bool:
	if not timeline_tutorial(snapshot): return false
	if snapshot["opening"].get("timeline_open",false):
		close_cards()
		return true
	var command := {"type":"campaign_timeline_open"}
	if inspect_action.is_valid() and inspect_action.call(command).get("ok",false): intent.emit(command)
	return true


func close_cards() -> void:
	if not timeline_tutorial(snapshot):
		progression_panel.hide()
		return
	var command := {"type":"campaign_timeline_close"}
	if inspect_action.is_valid() and inspect_action.call(command).get("ok",false): intent.emit(command)


func timeline_tutorial(data: Dictionary) -> bool:
	var opening: Dictionary=data.get("opening",{})
	return opening.get("phase")=="timeline" and int(opening.get("timeline_step",-1)) in [0,1,2,3]


func tutorial_target(entry: Dictionary) -> Rect2:
	match entry.get("gui",""):
		"MultiBarBtn": return original_hud.collection_button.get_global_rect()
		"MultiBarBar": return original_hud.bar.get_global_rect()
		"BeliefResrc":
			if entry.get("group")=="SuperFast": return original_hud.resource_rows["wheat"]["bar"].get_global_rect()
			return original_hud.belief_bar.get_global_rect()
		"BeliefBtn": return original_hud.sculpt_button.get_global_rect()
		"PowerSelectCard":
			if powers_panel.visible and powers_panel.selected==entry.get("gui_info") and is_instance_valid(powers_panel.detail_card):
				return powers_panel.detail_card.get_global_rect()
			var icon: Control=original_hud.power_nodes.get("GodPower_FingerOfGod")
			if is_instance_valid(icon): return icon.get_global_rect()
		"BeliefActivePower":
			var icon: Control=original_hud.power_nodes.get("GodPower_FingerOfGod")
			if is_instance_valid(icon): return icon.get_global_rect()
		"HappinessFace": return original_hud.happiness_gauge.get_global_rect()
		"MultiBarResrc":
			if int(entry.get("gui_info",-1))==1: return original_hud.resource_rows["wheat"]["bar"].get_global_rect()
		"SettlementRing":
			if is_instance_valid(farm_ring) and farm_ring.visible and not farm_ring.points.is_empty():
				return Rect2(farm_ring.points[0],Vector2.ONE)
		"InfoButtonsBtn":
			if entry.get("group")=="Farming" and farm_controls.visible:
				return (farm_confirm_button if farm_confirm_button.visible else farm_preview_button).get_global_rect()
		"InfoButtonsType":
			if entry.get("gui_info")=="DockGo" and building_panel.dock.visible and building_panel.voyage_button.is_visible_in_tree():
				return building_panel.voyage_button.get_global_rect()
		"TimelineExit":
			if progression_panel.visible and is_instance_valid(progression_panel.close_button): return progression_panel.close_button.get_global_rect()
		"TimelineSticker":
			var sticker: String=str(entry.get("gui_info",""))
			if progression_panel.visible and progression_panel.resource_slots.has(sticker): return progression_panel.resource_slots[sticker].get_global_rect()
	return Rect2()


func refresh_shrine_rewards() -> void:
	var pending:={}
	var claims: Array=snapshot.get("opening",{}).get("shrine_claims",[])
	for site: Dictionary in snapshot.get("progression",{}).get("shrines",[]):
		var id: String=site["id"]
		if not id in claims: continue
		var command:={"type":"campaign_activate_shrine","id":id}
		var source: Dictionary=campaign_cards.get(site["card"],{})
		if not source.get("available",false): continue
		pending[id]=true
		if not shrine_rewards.has(id):
			var card:=preload("res://presentation/ui/source_card.gd").new()
			card.source=source
			card.size=Vector2(52,78)
			card.z_index=15
			card.pressed.connect(func() -> void:
				if not is_paused: intent.emit(command.duplicate()))
			add_child(card)
			shrine_rewards[id]={"button":card,"site":site}
	for id: String in shrine_rewards.keys():
		if pending.has(id): continue
		shrine_rewards[id]["button"].hide()
		shrine_rewards[id]["button"].queue_free()
		shrine_rewards.erase(id)
	position_shrine_rewards()


func position_shrine_rewards() -> void:
	for reward: Dictionary in shrine_rewards.values():
		var card: TextureButton=reward["button"]
		var anchor: Vector3=world_view.temple_position(reward["site"])+Vector3(0,1.5,0)
		var point: Vector2=world_view.camera.unproject_position(anchor)
		card.position=point-Vector2(card.size.x*0.5,card.size.y)
		card.visible=not is_paused and not progression_panel.visible and not powers_panel.visible and not world_view.camera.is_position_behind(anchor) and get_viewport_rect().encloses(card.get_global_rect())


func on_action(cell: Vector2i, point: Vector2, shrine_cover: Dictionary={}) -> void:
	end_belief_sweep()
	if campaign_mode and (progression_panel.visible or powers_panel.visible): return
	if tool=="GodPower_MeteorStrike" and not snapshot.get("opening",{}).get("meteor_status",{}).is_empty():
		if not is_paused:
			meteor_swipe_started=Time.get_ticks_msec()
			meteor_swipe_origin=world_view.pointer_screen
		return
	if tool=="GodPower_FingerOfGod" and not snapshot.get("opening",{}).get("finger_status",{}).is_empty():
		if is_paused or finger_held: return
		var target := world_view.finger_point(point)
		if target.x<0: return
		finger_held=true
		intent.emit({"type":"use_power","power":tool,"x":target.x,"z":target.y})
		return
	if snapshot.has("leash_lesson"):
		if not is_paused: begin_lesson_leash(point)
		return
	if not is_paused and snapshot.has("opening") and tool=="GodPower_CliffSculpt":
		begin_terrain_drag(point)
		return
	if not is_paused and farm_active():
		if settlement_preview().is_empty():
			farm_point=cell
			farm_dragging=true
			if tool==FARM_POWER: intent.emit({"type":"campaign_farm_begin"})
			update_farm_controls()
		return
	if not is_paused and tool=="sculpt" and (shrine_cover.is_empty() or snapshot.get("weyworld",{}).get("leash_homes",[]).has(shrine_cover.get("home_id",-1))) and begin_campaign_leash(cell,point,shrine_cover):
		return
	act_on_world(cell,point,shrine_cover)


func act_on_world(cell: Vector2i,point: Vector2,shrine_cover: Dictionary) -> void:
	if not is_paused and tool=="sculpt" and shrine_cover.has("settlement_worker"):
		intent.emit({"type":"deploy_worker","id":shrine_cover["settlement_worker"]})
		return
	if not is_paused and tool=="sculpt" and shrine_cover.has("settlement_collect"):
		if request_belief_collection("settlement",int(shrine_cover["settlement_collect"])):
			belief_sweep=true
			belief_sweep_start=point
		return
	if not is_paused and tool=="sculpt" and shrine_cover.has("belief_home"):
		if request_belief_collection("home",int(shrine_cover["belief_home"])):
			belief_sweep=true
			belief_sweep_start=point
		return
	if not is_paused and shrine_cover.has("sprog_home"):
		intent.emit({"type":"sprog","home_id":shrine_cover["sprog_home"]})
		return
	var picked_home := -1
	if not tool.begins_with("GodPower_") or tool=="GodPower_FingerOfGod":
		picked_home=int(shrine_cover.get("home_id",-1))
		if picked_home!=-1: point=shrine_cover["point"]
	var clearing_tree := not is_paused and tool=="sculpt" and shrine_cover.has("tree_cell")
	if campaign_mode and building_panel!=null and building_panel.popup.visible:
		if picked_home==-1 and not clearing_tree: return
		building_panel.popup.hide()
	if clearing_tree:
		cancel_drag()
		intent.emit({"type":"tap_tree","cell":shrine_cover["tree_cell"]})
		return
	if campaign_mode and picked_home==-1 and (is_paused or not tool.begins_with("GodPower_")):
		var site := world_view.temple_at(point)
		if not site.is_empty():
			selected_home=site
			selected_building_kind="temple"
			cancel_drag()
			update_home_info()
			if building_panel.voyage_button.is_visible_in_tree():
				if not is_paused and snapshot["opening"].get("events_step")==0: intent.emit({"type":"campaign_select_dock","id":site})
			else: building_panel.popup.show()
			return
	if is_paused:
		selected_home=picked_home if picked_home!=-1 else world_view.home_at(point.x,point.y)
		selected_building_kind="home"
		if picked_home==-1:
			for settlement: Dictionary in snapshot.get("progression",{}).get("settlements",[]):
				if Vector2(settlement["x"],settlement["z"]).distance_to(point)<=1.5:
					selected_home=int(settlement["id"])
					selected_building_kind="settlement"
					break
		if selected_home!=-1: update_home_info()
		toast("Resume your world before shaping it.")
		return
	if snapshot.has("voyage"):
		if tool.begins_with("GodPower_"):
			intent.emit({"type":"voyage_power","power":tool,"x":point.x,"z":point.y})
			return
		for temple: Dictionary in snapshot["voyage"]["temples"]:
			if not temple["complete"] and Vector2(temple["x"],temple["z"]).distance_to(point)<1.2:
				intent.emit({"type":"voyage_temple","uid":temple["uid"]})
				return
		for chest: Dictionary in snapshot["voyage"]["chests"]:
			if not chest["opened"] and Vector2(chest["x"],chest["z"]).distance_to(point)<1.0:
				intent.emit({"type":"voyage_chest","id":chest["id"]})
				return
	if campaign_mode and snapshot.has("progression"):
		if tool.begins_with("GodPower_"):
			var command := {"type":"use_power","power":tool,"x":point.x,"z":point.y}
			if tool=="GodPower_RainOfPurity" and snapshot.has("opening"):
				rain_held=true
			if tool=="GodPower_FingerOfGod":
				var target := picked_home if picked_home!=-1 else world_view.home_at(point.x,point.y)
				for home: Dictionary in snapshot.get("homes",[]):
					if int(home["id"])==target and home.get("kind","")!="shrine":
						command["home_id"]=target
						command["x"]=clampi(roundi(point.x),int(home["x"]),int(home["x"])+int(home.get("span",2))-1)
						command["z"]=clampi(roundi(point.y),int(home["z"]),int(home["z"])+int(home.get("span",2))-1)
						break
			intent.emit(command)
			return
	if campaign_mode and snapshot.has("progression") and picked_home==-1:
		for settlement: Dictionary in snapshot["progression"].get("settlements",[]):
			if Vector2(settlement["x"],settlement["z"]).distance_to(point)>1.5: continue
			selected_home=int(settlement["id"])
			selected_building_kind="settlement"
			cancel_drag()
			update_home_info()
			if request_belief_collection("settlement",int(settlement["id"])):
				belief_sweep=true
				belief_sweep_start=point
			else: intent.emit({"type":"deploy_worker","id":settlement["id"]})
			return
		var object_command := world_view.progression_at(point)
		if not object_command.is_empty():
			if str(object_command["type"]).begins_with("inspect_"):
				selected_home=int(object_command["id"])
				selected_building_kind=str(object_command["type"]).trim_prefix("inspect_")
				update_home_info()
				building_panel.popup.show()
			else: intent.emit(object_command)
			return
	selected_home = picked_home if picked_home!=-1 else world_view.home_at(point.x, point.y)
	selected_building_kind="home"
	if selected_home != -1:
		cancel_drag()
		update_home_info()
		if selected_home in snapshot.get("opening",{}).get("sprog_homes",[]):
			intent.emit({"type":"sprog","home_id":selected_home})
			return
		if request_belief_collection("home",int(selected_home)) and campaign_mode:
			belief_sweep=true
			belief_sweep_start=point
		return
	home_panel.visible = false
	if building_panel!=null: building_panel.hide_selection()
	if tool == "sculpt":
		begin_terrain_drag(point)
	elif tool == "model":
		intent.emit(placement_command(cell))
	else:
		intent.emit({"type": tool, "x": cell.x, "z": cell.y})


func terrain_edge(point: Vector2) -> Dictionary:
	if tool=="GodPower_CliffSculpt": return locate_edge.call(point.x,point.y,0,true)
	return locate_edge.call(point.x,point.y,layer_choice.selected)


func begin_terrain_drag(point: Vector2) -> void:
	drag=terrain_edge(point)
	if not drag.get("ok",false):
		toast(drag.get("reason","Choose a terrain edge."))
		return
	world_view.layer_drag=true
	world_view.drag_height=int(drag["layer"])*WorldView.Terrain.STEP
	drag_start=world_view.pick(world_view.pointer_screen,world_view.drag_height)
	preview_delta=Vector2i(999,999)
	on_drag(drag_start)


func on_drag(point: Vector2) -> void:
	if drag.is_empty():
		return
	var distance := clampi(roundi((point - drag_start).dot(Vector2(drag["nx"], drag["nz"]))), -12, 12)
	var delta := Vector2i(clampi(roundi(point.x - drag_start.x), -12, 12), clampi(roundi(point.y - drag_start.y), -12, 12))
	if delta == preview_delta:
		return
	preview_delta = delta
	drag_command = drag.duplicate(true)
	drag_command["type"] = "sculpt_drag"
	if tool=="GodPower_CliffSculpt": drag_command["power"]=tool
	drag_command["distance"] = distance
	drag_command["dx"] = delta.x
	drag_command["dz"] = delta.y
	drag_command["radius"] = width_choice.selected
	var result: Dictionary = inspect_action.call(drag_command)
	hover_label.text = result["reason"]
	world_view.set_marker(Vector2i(drag["x"], drag["z"]), result["ok"], width_choice.selected * 2 + 1)
	if result["ok"]:
		world_view.preview_edits(result["edits"])
		audio.set_sculpting(true)
	else:
		audio.set_sculpting(false)
		world_view.clear_preview()


func finish_drag() -> void:
	audio.set_sculpting(false, true)
	if not drag_command.is_empty():
		var result: Dictionary = inspect_action.call(drag_command)
		if result["ok"]:
			intent.emit(drag_command.duplicate(true))
		else:
			toast(result["reason"])
			world_view.cancel_preview()
	drag.clear()
	drag_command.clear()
	world_view.layer_drag = false


func cancel_drag() -> void:
	end_belief_sweep()
	end_rain()
	farm_dragging=false
	audio.set_sculpting(false)
	audio.finish_beautify()
	if world_view.layer_drag:
		world_view.cancel_preview()
	drag.clear()
	drag_command.clear()


func on_hover(cell: Vector2i, point: Vector2) -> void:
	if snapshot.is_empty() or snapshot.has("leash_lesson"):
		return
	if tool in ["sculpt","GodPower_CliffSculpt"]:
		var level := layer_choice.selected
		var edge:=terrain_edge(point)
		world_view.set_marker(Vector2i(edge.get("x", cell.x), edge.get("z", cell.y)), edge.get("ok", false))
		hover_label.text = "Layer %d · drag inward to shrink, outward to extend" % edge.get("layer", level) if edge.get("ok", false) else edge.get("reason", "Choose a land edge.")
	else:
		var command := placement_command(cell) if tool == "model" else ({"type":"use_power","power":tool,"x":cell.x,"z":cell.y} if tool.begins_with("GodPower_") else {"type": tool, "x": cell.x, "z": cell.y})
		var result: Dictionary = inspect_action.call(command)
		world_view.set_marker(cell, result["ok"], 2 if tool == "home" else 1)
		hover_label.text = result["reason"]


func toggle_menu() -> void:
	cancel_drag()
	if building_panel!=null: building_panel.popup.hide()
	pause_panel.visible = not pause_panel.visible
	if pause_panel.visible != is_paused:
		pause_requested.emit()


func update_playback(paused: bool, speed: float) -> void:
	if paused:
		cancel_drag()
	is_paused = paused
	pause_button.text = "▶" if paused else "Ⅱ"
	speed_button.text = "%d×" % int(speed)
	world_view.set_process(not paused)
	world_view.animation_speed = speed
	for actor: Node3D in world_view.actor_nodes.values()+world_view.progression_nodes.values():
		actor.set_process(not paused)
		if actor.get("cue_audio") != null and paused: actor.cue_audio.stop_effects()


func set_effects_enabled(value: bool) -> void:
	audio.set_effects_enabled(value)
	world_view.effects_enabled = value
	for actor: Node3D in world_view.actor_nodes.values()+world_view.progression_nodes.values():
		if actor.get("cue_audio") != null: actor.cue_audio.set_effects_enabled(value)


func toast(value: String) -> void:
	if campaign_mode: return
	message_label.text = value
	message_time = 5.0


func play_simulation_sound(event: Dictionary) -> void:
	if event.has("meteor_id"):
		audio.play_meteor_event(event["event"],event["meteor_id"])
	else:
		audio.play_event(event.get("event",event["type"]) if event["type"]=="source_sound" else event["type"])


func select_power(power: String) -> void:
	if building_panel!=null: building_panel.popup.hide()
	meteor_swipe_started=-1
	if power=="GodPower_LandManipulation": choose_tool("sculpt")
	elif power=="GodPower_TotemActivate": intent.emit({"type":"use_power","power":power})
	else:
		cancel_drag()
		if power!=tool: cancel_god_seed_hint()
		if power!=tool: cancel_finger()
		if power=="GodPower_FingerOfGod" and not snapshot.get("opening",{}).get("finger_status",{}).is_empty():
			var finger: Dictionary=snapshot["opening"]["finger_status"]
			if not finger["affordable"] or is_paused: return
			if not finger["active"]: intent.emit({"type":"campaign_finger_arm"})
		tool=power
		var farming: int=snapshot.get("opening",{}).get("farming_step",-1)
		if power==FARM_POWER and farming==0:
			intent.emit({"type":"campaign_farm_card"})
		elif power==FARM_POWER and (farming==2 or farming>=4):
			farm_point=Vector2i(world_view.pick(get_viewport_rect().size*0.5).round())
			intent.emit({"type":"campaign_farm_select"})
		elif power in [BUILDER_POWER,MINING_POWER] and snapshot.has("opening"):
			farm_point=Vector2i(world_view.pick(get_viewport_rect().size*0.5).round())
		elif power=="GodPower_GodSeed" and snapshot.get("opening",{}).get("god_seed_step")==2:
			intent.emit({"type":"campaign_god_seed_select"})
		elif power=="GodPower_PlaceCapacity" and snapshot.get("opening",{}).get("capacity_step")==3:
			intent.emit({"type":"campaign_capacity_select"})


func cancel_god_seed_hint() -> void:
	if tool=="GodPower_GodSeed" and snapshot.get("opening",{}).get("god_seed_step")==2:
		intent.emit({"type":"campaign_god_seed_cancel"})


func cancel_finger() -> void:
	if tool!="GodPower_FingerOfGod" or snapshot.get("opening",{}).get("finger_status",{}).is_empty(): return
	finger_held=false
	world_view.finger_preview=false
	world_view.finger_view.hide()
	intent.emit({"type":"campaign_finger_cancel"})


func release_finger() -> void:
	if not finger_held: return
	finger_held=false
	intent.emit({"type":"campaign_finger_release"})


func release_meteor(pointer: Vector2) -> void:
	if meteor_swipe_started<0: return
	var seconds:=float(Time.get_ticks_msec()-meteor_swipe_started)/1000.0
	meteor_swipe_started=-1
	if is_paused or tool!="GodPower_MeteorStrike" or not get_viewport_rect().has_point(pointer): return
	if progression_panel.visible or powers_panel.visible or pause_panel.visible: return
	var point:=world_view.pick(pointer)
	if point.x<0.0: return
	var direction: Vector3=world_view.camera.global_basis.x
	var heading:=Vector2(direction.x,direction.z).normalized()
	var drag:=pointer-meteor_swipe_origin
	var viewport:=get_viewport_rect().size
	intent.emit({"type":"use_power","power":tool,"x":point.x,"z":point.y,"seconds":seconds,
		"viewport":[viewport.x,viewport.y],"drag":[drag.x,drag.y],"heading":[heading.x,heading.y]})


func build_farm_controls() -> void:
	farm_controls=HBoxContainer.new()
	farm_controls.alignment=BoxContainer.ALIGNMENT_CENTER
	farm_preview_button=Style.button(building_info_labels.get("LOC_BUTTON_SETTLEMENT_MERGE","Preview"),func() -> void:
		intent.emit({"type":settlement_command("preview"),"x":farm_point.x,"z":farm_point.y}))
	farm_confirm_button=Style.button(building_info_labels.get("LOC_BUTTON_SETTLEMENT_MERGE_CONFIRM","Squish it!"),func() -> void:
		intent.emit({"type":settlement_command("confirm")}))
	var cancel:=Style.button(building_info_labels.get("LOC_BUTTON_SETTLEMENT_MERGE_CANCEL","Cancel"),func() -> void:
		intent.emit({"type":settlement_command("cancel")})
		if settlement_preview().is_empty(): choose_tool("sculpt"))
	farm_controls.add_child(farm_preview_button)
	farm_controls.add_child(farm_confirm_button)
	farm_controls.add_child(cancel)
	farm_controls.hide()
	add_child(farm_controls)
	farm_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	farm_controls.offset_left=-160
	farm_controls.offset_right=160
	farm_controls.offset_top=-82
	farm_controls.offset_bottom=-42
	farm_ring=Line2D.new()
	farm_ring.width=2.0
	farm_ring.default_color=Color(1,1,1,0.7)
	farm_ring.hide()
	add_child(farm_ring)


func farm_active() -> bool:
	var opening: Dictionary=snapshot.get("opening",{})
	if tool in [BUILDER_POWER,MINING_POWER]:
		var role := "mining" if tool==MINING_POWER else "builder"
		return opening.get("definition",{}).has(role+"_core") and tool in snapshot["progression"]["powers"]
	return tool==FARM_POWER and (opening.get("farming_step")==3 or opening.get("farming_placing",false))


func settlement_command(action: String) -> String:
	var role: String={BUILDER_POWER:"builder",MINING_POWER:"mining"}.get(tool,"farm")
	return "campaign_"+role+"_"+action


func settlement_preview() -> Dictionary:
	var role: String={BUILDER_POWER:"builder",MINING_POWER:"mining"}.get(tool,"farming")
	return snapshot["opening"].get(role+"_preview",{})


func update_farm_controls() -> void:
	var active:=farm_active() and not is_paused and not progression_panel.visible and not powers_panel.visible
	farm_controls.visible=active
	farm_ring.visible=active and farm_point.x>=0
	if not active:
		farm_preview_key=[]
		world_view.show_farming_preview(Vector2.ZERO,[])
		return
	var draft:=settlement_preview()
	farm_preview_button.visible=draft.is_empty()
	farm_confirm_button.visible=not draft.is_empty()
	if draft.is_empty():
		var key: Array=[tool,farm_point,snapshot["terrain_revision"],snapshot["progression"]["revision"],snapshot["belief"],snapshot["completed_homes"]]
		if key!=farm_preview_key:
			farm_preview_key=key
			var plan: Dictionary=inspect_action.call({"type":settlement_command("preview"),"x":farm_point.x,"z":farm_point.y})
			farm_preview_button.disabled=not plan.get("ok",false)
	var center:=Vector2(draft.get("x",farm_point.x),draft.get("z",farm_point.y))
	var rules: Dictionary=snapshot["progression"]["rules"]
	var settlement: Dictionary=rules["economy"]["settlements"][tool]
	var radius: float=snapshot["opening"]["settlement_status"][tool]["radius"]
	world_view.show_farming_preview(center,[] if draft.is_empty() else [settlement["model_id"],settlement["statue_id"]])
	var points:=PackedVector2Array()
	for index in range(49):
		var point:=center+Vector2.from_angle(TAU*index/48.0)*radius
		points.append(world_view.camera.unproject_position(world_view.world_position(point.x,point.y)+Vector3.UP*0.04))
	farm_ring.points=points


func double_action(cell: Vector2i) -> void:
	if not is_paused and (not campaign_mode or not progression_panel.visible and not powers_panel.visible):
		if tool=="sculpt":
			cancel_drag()
			intent.emit({"type":"dig","x":cell.x,"z":cell.y})
		elif tool.begins_with("GodPower_"):
			var point := world_view.pick(world_view.pointer_screen) if tool=="GodPower_FingerOfGod" else Vector2(cell)
			on_action(cell,point)


func paint_power(cell: Vector2i) -> void:
	if not is_paused and tool in ["GodPower_Beautify","GodPower_FingerOfGod","GodPower_RainOfPurity"] and (not campaign_mode or not progression_panel.visible and not powers_panel.visible):
		if tool=="GodPower_FingerOfGod" and not snapshot.get("opening",{}).get("finger_status",{}).is_empty(): return
		if tool=="GodPower_RainOfPurity" and snapshot.has("opening"):
			if not rain_held: return
			var point:=world_view.pick(world_view.pointer_screen)
			var command:={"type":"use_power","power":tool,"x":point.x,"z":point.y}
			intent.emit(command if inspect_action.is_valid() and inspect_action.call(command).get("ok",false) else {"type":"campaign_rain_stop"})
			return
		intent.emit({"type":"voyage_power" if snapshot.has("voyage") else "use_power","power":tool,"x":cell.x,"z":cell.y})


func end_rain() -> void:
	if not rain_held: return
	rain_held=false
	audio.set_rain_active(false)
	intent.emit({"type":"campaign_rain_stop"})


func end_belief_sweep() -> void:
	belief_sweep=false
	belief_sweep_seen.clear()


func request_belief_collection(kind: String,id: int,gesture: String="click") -> bool:
	var key := "%s:%d"%[kind,id]
	if belief_sweep_seen.has(key) or not inspect_action.is_valid(): return false
	var command := {"type":"collect_settlement","id":id} if kind=="settlement" else {"type":"collect","home_id":id}
	if gesture=="drag": command["gesture"]="drag"
	if not inspect_action.call(command).get("ok",false): return false
	belief_sweep_seen[key]=true
	intent.emit(command)
	return true


static func segment_hits_rect(start: Vector2,end: Vector2,rect: Rect2) -> bool:
	var delta := end-start
	var first := 0.0
	var last := 1.0
	for axis in range(2):
		if delta[axis]==0:
			if start[axis]<rect.position[axis] or start[axis]>=rect.end[axis]: return false
			continue
		var near := (rect.position[axis]-start[axis])/delta[axis]
		var far := (rect.end[axis]-start[axis])/delta[axis]
		first=maxf(first,minf(near,far))
		last=minf(last,maxf(near,far))
		if first>last: return false
	return true


func on_pointer_dragged(cell: Vector2i) -> void:
	if farm_dragging and farm_active():
		farm_point=cell
		return
	if not belief_sweep:
		paint_power(cell)
		return
	if is_paused or not campaign_mode or progression_panel.visible or powers_panel.visible or pause_panel.visible or building_panel.popup.visible: return
	var point := Vector2(cell)
	# Test the whole motion segment once per building, so a quick drag does
	# not skip houses between mouse events or rescan every intermediate cell.
	for settlement: Dictionary in snapshot.get("progression",{}).get("settlements",[]):
		var center := Vector2(settlement["x"],settlement["z"])
		if center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center,belief_sweep_start,point))<=2.25:
			request_belief_collection("settlement",int(settlement["id"]),"drag")
	for home: Dictionary in snapshot.get("homes",[]):
		var region := Rect2(Vector2(home["x"],home["z"])-Vector2.ONE*0.5,Vector2.ONE*float(home.get("span",2)))
		if segment_hits_rect(belief_sweep_start,point,region): request_belief_collection("home",int(home["id"]),"drag")
	belief_sweep_start=point


func _process(delta: float) -> void:
	position_shrine_rewards()
	if is_instance_valid(farm_controls): update_farm_controls()
	if leash_home!=-1 or leash_candidate!=-1 or leash_active:
		if is_paused or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): clear_lesson_leash()
		else: advance_lesson_leash(delta)
	if belief_sweep and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): end_belief_sweep()
	if rain_held and (is_paused or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not get_window().has_focus()): end_rain()
	if finger_held and (is_paused or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not get_window().has_focus()): release_finger()
	if meteor_swipe_started>=0 and (is_paused or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not get_window().has_focus()): meteor_swipe_started=-1
	message_time -= delta
	if message_time <= 0:
		message_label.text = ""
	if building_panel!=null:
		building_panel.visible=not progression_panel.visible and not powers_panel.visible and not pause_panel.visible
	# Releasing above a HUD control still finishes the active terrain gesture.
	if world_view.layer_drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		finish_drag()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		audio.finish_beautify()
		end_rain()
		release_finger()


func lesson_follower_at(pointer: Vector2) -> int:
	var result := -1
	var distance := 18.0
	for follower: Dictionary in snapshot.get("followers",[]):
		var id: int=follower["id"]
		var actor: Node3D=world_view.actor_nodes.get(id)
		if not is_instance_valid(actor) or not actor.visible or id in leash_followers: continue
		var projected: Vector2=world_view.camera.unproject_position(actor.position+Vector3.UP*0.35)
		var gap:=pointer.distance_to(projected)
		if gap<distance:
			distance=gap
			result=id
	return result


func begin_lesson_leash(point: Vector2) -> void:
	clear_lesson_leash()
	var lesson: Dictionary=snapshot["leash_lesson"]
	if lesson["selection"]=="home" and lesson_home_at(world_view.pointer_screen,point)==lesson["home_id"]:
		leash_home=lesson["home_id"]
	elif lesson["selection"] in ["follower","group"]:
		leash_candidate=lesson_follower_at(world_view.pointer_screen)


func begin_campaign_leash(cell: Vector2i,point: Vector2,cover: Dictionary) -> bool:
	var opening: Dictionary=snapshot.get("opening",snapshot.get("weyworld",{}))
	if not opening.has("leash_controls") or building_panel.popup.visible: return false
	clear_lesson_leash()
	var pointer: Vector2=world_view.pointer_screen
	leash_candidate=lesson_follower_at(pointer)
	if leash_candidate==-1:
		var home_id: int=cover.get("home_id",world_view.home_at(point.x,point.y))
		if home_id==-1: home_id=lesson_home_at(pointer,point)
		if not home_id in opening["leash_homes"]: return false
		leash_home=home_id
	leash_click={"cell":cell,"point":point,"cover":cover}
	return true


func lesson_home_at(pointer: Vector2,ground: Vector2) -> int:
	var hit: Dictionary=world_view.pick_home_mesh(world_view.camera.project_ray_origin(pointer),world_view.camera.project_ray_normal(pointer))
	for item: Dictionary in snapshot.get("progression",{}).get("settlements",[]):
		if item["members"].size()!=1: continue
		if ground.distance_squared_to(Vector2(item["x"],item["z"]))<=2.25: return int(item["members"][0])
	return int(hit.get("home_id",world_view.home_at(ground.x,ground.y)))


func advance_lesson_leash(delta: float) -> void:
	var lesson: Dictionary=snapshot.get("leash_lesson",{})
	var opening: Dictionary=snapshot.get("opening",snapshot.get("weyworld",{}))
	var rules: Dictionary=lesson.get("definition",opening.get("leash_controls",{}))
	if rules.is_empty(): clear_lesson_leash(); return
	var pointer: Vector2=world_view.pointer_screen
	var candidate:=lesson_follower_at(pointer)
	if not leash_active:
		if leash_candidate!=-1 and leash_candidate!=candidate:
			clear_lesson_leash()
			return
		if leash_home!=-1:
			var point: Vector2=world_view.pick(pointer)
			if lesson_home_at(pointer,point)!=leash_home:
				clear_lesson_leash()
				return
	if lesson.get("selection","group")=="group" and leash_active and leash_candidate!=candidate:
		leash_candidate=candidate
		leash_hold=0.0
	if leash_home!=-1 or leash_candidate!=-1:
		leash_hold+=delta
		if leash_hold>=float(rules["hold_seconds"]):
			leash_active=true
			if leash_candidate!=-1 and leash_candidate not in leash_followers: leash_followers.append(leash_candidate)
			leash_candidate=-1
	if not leash_active: return
	if not is_instance_valid(leash_line):
		leash_line=Line2D.new()
		leash_line.z_index=20
		var color: Array=rules["leash_color"]
		leash_line.default_color=Color(color[0],color[1],color[2],color[3])
		add_child(leash_line)
	leash_line.width=float(rules["leash_size"])*get_viewport_rect().size.y/world_view.zoom
	var points:=PackedVector2Array()
	for id: int in leash_followers:
		var actor: Node3D=world_view.actor_nodes.get(id)
		if is_instance_valid(actor): points.append(world_view.camera.unproject_position(actor.position+Vector3.UP*0.35))
	if leash_home!=-1:
		var home: Node3D=world_view.home_nodes.get(leash_home)
		if is_instance_valid(home): points.append(world_view.camera.unproject_position(home.position+Vector3.UP*0.5))
	points.append(pointer)
	leash_line.points=points
	update_lesson_prompt()


func update_lesson_prompt(force: bool=false) -> void:
	var lesson: Dictionary=snapshot.get("leash_lesson",{})
	if lesson.is_empty(): return
	var prompt: Dictionary=lesson["prompt"]
	if leash_active and lesson.has("drag_prompt"):
		prompt=lesson["drag_prompt"]
		if lesson.has("group_prompt") and leash_followers.size()<lesson["group_size"]:
			prompt=lesson["group_prompt"]
	var id: int=prompt.get("id",-1)
	if force or leash_prompt_id!=id:
		leash_prompt_id=id
		campaign_prompt.apply_snapshot(snapshot,prompt)


func release_lesson_leash() -> void:
	if leash_active and not is_paused:
		var point: Vector2=world_view.pick(world_view.pointer_screen)
		intent.emit({"type":"leash","followers":leash_followers.duplicate(),"home_id":leash_home,"x":point.x,"z":point.y})
	elif not leash_click.is_empty() and not is_paused:
		act_on_world(leash_click["cell"],leash_click["point"],leash_click["cover"])
	clear_lesson_leash()


func clear_lesson_leash() -> void:
	leash_candidate=-1
	leash_home=-1
	leash_hold=0.0
	leash_active=false
	leash_followers.clear()
	leash_click={}
	if is_instance_valid(leash_line): leash_line.clear_points()
	update_lesson_prompt()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1: choose_tool("sculpt")
		KEY_2:
			if not campaign_mode: choose_tool("home")
		KEY_3:
			if not campaign_mode: choose_tool("sheep")
		KEY_4: intent.emit({"type": "collect"})
		KEY_5:
			if not campaign_mode: models_requested.emit()
		KEY_R: placement_turns = (placement_turns + 1) % 4
		KEY_SPACE: pause_requested.emit()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: world_view.zoom_by(0.82)
		KEY_MINUS, KEY_KP_SUBTRACT: world_view.zoom_by(1.0 / 0.82)
		KEY_ESCAPE:
			if campaign_mode and powers_panel.visible: powers_panel.visible=false
			elif campaign_mode and progression_panel.visible: close_cards()
			elif building_panel!=null and building_panel.popup.visible: building_panel.popup.hide()
			elif building_panel!=null and building_panel.dock.visible:
				selected_home=-1
				building_panel.hide_selection()
			elif world_view.layer_drag: cancel_drag()
			elif tool in ["GodPower_GodSeed","GodPower_MeteorStrike"]: choose_tool("sculpt")
			else: toggle_menu()


func build_settings_menu() -> void:
	var menu := preload("res://presentation/world/settings_panel.gd").new()
	menu.definitions=settings_definitions
	menu.values=settings_values
	menu.setting_changed.connect(func(key: String,value: Variant) -> void: setting_changed.emit(key,value))
	menu.reset_requested.connect(func(prefix: String) -> void: reset_settings_requested.emit(prefix))
	menu.save_requested.connect(func() -> void: choose_save_file(true))
	menu.load_requested.connect(func() -> void: choose_save_file(false))
	menu.reload_constants_requested.connect(func() -> void: reload_constants_requested.emit())
	menu.open_table_requested.connect(func(table: String) -> void: open_table_requested.emit(table))
	menu.open_constants_requested.connect(func() -> void: open_constants_requested.emit())
	menu.menu_requested.connect(func() -> void: menu_requested.emit())
	menu.close_requested.connect(toggle_menu)
	add_child(menu)
	pause_panel=menu
	menu.hide()
	menu.set_status(settings_status)


func choose_save_file(saving: bool) -> void:
	if is_instance_valid(file_dialog): file_dialog.queue_free()
	file_dialog=FileDialog.new()
	file_dialog.access=FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title="Save game" if saving else "Load game"
	file_dialog.filters=PackedStringArray(["*.sqlite3 ; Dominus saved game"])
	file_dialog.current_dir=save_directory
	if saving: file_dialog.current_file=save_path.get_file() if not save_path.is_empty() else str(snapshot.get("campaign", {}).get("map", "World"))+".sqlite3"
	file_dialog.file_selected.connect(func(path_: String) -> void:
		if saving: save_path_requested.emit(path_)
		else: load_path_requested.emit(path_))
	add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.8)


func apply_preferences(values: Dictionary) -> void:
	settings_values=values.duplicate(true)
	world_view.light.shadow_enabled=values.get("display.shadows",false)
	world_view.preferences=settings_values
	world_view.lighting_revision=-999
	world_view.influence_view.preference_tint=Vector3(values.get("visuals.outside_r",0.67),values.get("visuals.outside_g",0.79),values.get("visuals.outside_b",0.81))
	if not world_view.state.is_empty():
		world_view.apply_source_lighting()
		world_view.influence_view.apply_snapshot(world_view.state,world_view)
	audio.set_music_enabled(values.get("audio.music_enabled",true))
	audio.music.volume_db=values.get("audio.music_db",-19)
	set_effects_enabled(values.get("audio.effects_enabled",true))
	world_view.effects_db=values.get("audio.effects_db",-15)
	audio.set_effects_volume(world_view.effects_db)
	audio.sculpt.volume_db=world_view.effects_db-2
	for actor: Node3D in world_view.actor_nodes.values()+world_view.progression_nodes.values():
		if actor.get("cue_audio")!=null: actor.cue_audio.set_effects_volume(world_view.effects_db)
	if pause_panel!=null: pause_panel.refresh(settings_definitions,settings_values)


func menu_status(message: String) -> void:
	settings_status=message
	if pause_panel!=null: pause_panel.set_status(message)
