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
	world_view.observer_changed.connect(func(observation: Dictionary) -> void: intent.emit(observation))
	build_hud()
	if campaign_mode:
		campaign_prompt=preload("res://presentation/world/campaign_prompt.gd").new()
		campaign_prompt.textures=hud_textures
		campaign_prompt.view=world_view
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
	hud.sculpt_requested.connect(func() -> void: powers_panel.open_book(); progression_panel.visible=false)
	hud.card_requested.connect(func(id: String) -> void: progression_panel.open_card(id))
	hud.collection_requested.connect(func() -> void: progression_panel.open_book(); powers_panel.hide())
	hud.power_requested.connect(func(power: String) -> void:
		powers_panel.open_card("Card_"+power)
		progression_panel.hide())
	add_child(hud)
	original_hud = hud
	progression_panel = preload("res://presentation/world/progression_panel.gd").new()
	progression_panel.cards = campaign_cards
	progression_panel.textures=hud_textures
	progression_panel.inspect_command = inspect_action
	progression_panel.command_requested.connect(func(command: Dictionary) -> void: intent.emit(command))
	progression_panel.power_requested.connect(select_power)
	add_child(progression_panel)
	powers_panel = preload("res://presentation/world/progression_panel.gd").new()
	powers_panel.mode="powers"
	powers_panel.cards=campaign_cards
	powers_panel.textures=hud_textures
	powers_panel.inspect_command=inspect_action
	powers_panel.command_requested.connect(func(command: Dictionary) -> void: intent.emit(command))
	powers_panel.power_requested.connect(select_power)
	add_child(powers_panel)
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
	add_child(building_panel)
	build_settings_menu()
	choose_tool("sculpt")


func choose_tool(value: String) -> void:
	cancel_drag()
	if value == "collect":
		intent.emit({"type": "collect"})
		return
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
	snapshot = data
	world_view.apply_snapshot(data)
	if has_building_selection(): update_home_info()
	if data.has("voyage"):
		voyage_hud.apply_snapshot(data)
		for event: Dictionary in events:
			audio.play_event(event.get("event",event["type"]) if event["type"]=="source_sound" else event["type"])
			if event["type"]=="voyage_alert": voyage_hud.hint.text=event["message"]
		return
	if campaign_mode:
		campaign_prompt.apply_snapshot(data)
		original_hud.apply_snapshot(data)
		progression_panel.apply_snapshot(data)
		powers_panel.apply_snapshot(data)
		for event: Dictionary in events:
			audio.play_event(event.get("event",event["type"]) if event["type"]=="source_sound" else event["type"])
			if event["type"]=="campaign_camera": world_view.apply_campaign_camera(event)
			if event["type"] in ["chest_opened","card_discovered"] and not str(event.get("card","")).is_empty(): progression_panel.open_card(event["card"])
			elif event["type"]=="claim_card" and progression_panel.selected==event["card"]: progression_panel.visible=false
			elif event["type"]=="use_power" and tool==event.get("power","") and tool.begins_with("GodPower_PlaceSettlement_"): choose_tool("sculpt")
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
		building_panel.present(info,art,selected_building_kind!="temple" and inspect_action.is_valid() and inspect_action.call(collect).get("ok",false),selected_building_kind=="home" and inspect_action.is_valid() and inspect_action.call({"type":"upgrade_home","id":selected_home}).get("ok",false),selected_building_kind=="temple" and not is_paused and inspect_action.is_valid() and inspect_action.call({"type":"repair_shrine","id":selected_home}).get("ok",false))
		return
	for home: Dictionary in snapshot["homes"]:
		if home["id"] == selected_home:
			var build_ticks: int = snapshot.get("build_ticks",60)
			home_info.text = "Construction: %d%%\nBelief waiting: %d\n%s" % [mini(100, int(home["progress"] / float(build_ticks) * 100)), home["stored"], "A worker needs a clear route." if home["stalled"] else ("A place for your people." if home["progress"] >= build_ticks else "Your follower is building.")]
			home_panel.visible = true
			goal_panel.visible = false


func building_action(action: String) -> void:
	if is_paused or not has_building_selection(): return
	if action=="repair" and selected_building_kind=="temple":
		intent.emit({"type":"repair_shrine","id":selected_home})
		return
	if action=="upgrade" and selected_building_kind=="home": intent.emit({"type":"upgrade_home","id":selected_home})
	elif action=="collect": intent.emit({"type":"collect_settlement","id":selected_home} if selected_building_kind=="settlement" else {"type":"collect","home_id":selected_home})


func on_action(cell: Vector2i, point: Vector2) -> void:
	end_belief_sweep()
	if campaign_mode and (progression_panel.visible or powers_panel.visible): return
	if campaign_mode and building_panel!=null and building_panel.popup.visible: return
	if campaign_mode and (is_paused or not tool.begins_with("GodPower_")):
		var site := world_view.temple_at(point)
		if not site.is_empty():
			selected_home=site
			selected_building_kind="temple"
			cancel_drag()
			update_home_info()
			building_panel.popup.show()
			return
	if is_paused:
		selected_home=world_view.home_at(point.x,point.y)
		selected_building_kind="home"
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
			if tool=="GodPower_FingerOfGod":
				var target := world_view.home_at(point.x,point.y)
				for home: Dictionary in snapshot.get("homes",[]):
					if int(home["id"])==target and home.get("kind","")!="shrine":
						command["home_id"]=target
						command["x"]=clampi(roundi(point.x),int(home["x"]),int(home["x"])+int(home.get("span",2))-1)
						command["z"]=clampi(roundi(point.y),int(home["z"]),int(home["z"])+int(home.get("span",2))-1)
						break
			intent.emit(command)
			return
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
			intent.emit(object_command)
			return
	selected_home = world_view.home_at(point.x, point.y)
	selected_building_kind="home"
	if selected_home != -1:
		cancel_drag()
		update_home_info()
		if request_belief_collection("home",int(selected_home)) and campaign_mode:
			belief_sweep=true
			belief_sweep_start=point
		return
	home_panel.visible = false
	if building_panel!=null: building_panel.hide_selection()
	if tool == "sculpt":
		var level := layer_choice.selected
		drag = locate_edge.call(point.x, point.y, level)
		if not drag.get("ok", false):
			toast(drag.get("reason", "Choose a terrain edge."))
			return
		world_view.layer_drag = true
		world_view.drag_height = int(drag["layer"]) * WorldView.Terrain.STEP
		drag_start = world_view.pick(world_view.pointer_screen, world_view.drag_height)
		preview_delta = Vector2i(999, 999)
		on_drag(drag_start)
	elif tool == "model":
		intent.emit(placement_command(cell))
	else:
		intent.emit({"type": tool, "x": cell.x, "z": cell.y})


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
		world_view.terrain.rebuild(snapshot,true)


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
	audio.set_sculpting(false)
	if world_view.layer_drag:
		world_view.cancel_preview()
	drag.clear()
	drag_command.clear()


func on_hover(cell: Vector2i, point: Vector2) -> void:
	if snapshot.is_empty():
		return
	if tool == "sculpt":
		var level := layer_choice.selected
		var edge: Dictionary = locate_edge.call(point.x, point.y, level)
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


func select_power(power: String) -> void:
	if building_panel!=null: building_panel.popup.hide()
	if power=="GodPower_LandManipulation": choose_tool("sculpt")
	elif power=="GodPower_TotemActivate": intent.emit({"type":"use_power","power":power})
	else:
		cancel_drag()
		tool=power


func double_action(cell: Vector2i) -> void:
	if not is_paused and (not campaign_mode or not progression_panel.visible and not powers_panel.visible):
		if tool=="sculpt":
			cancel_drag()
			intent.emit({"type":"dig","x":cell.x,"z":cell.y})
		elif tool.begins_with("GodPower_"): on_action(cell,Vector2(cell))


func paint_power(cell: Vector2i) -> void:
	if not is_paused and tool in ["GodPower_Beautify","GodPower_FingerOfGod","GodPower_RainOfPurity"] and (not campaign_mode or not progression_panel.visible and not powers_panel.visible):
		intent.emit({"type":"voyage_power" if snapshot.has("voyage") else "use_power","power":tool,"x":cell.x,"z":cell.y})


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
	if belief_sweep and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): end_belief_sweep()
	message_time -= delta
	if message_time <= 0:
		message_label.text = ""
	if building_panel!=null:
		building_panel.visible=not progression_panel.visible and not powers_panel.visible and not pause_panel.visible
	# Releasing above a HUD control still finishes the active terrain gesture.
	if world_view.layer_drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		finish_drag()


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
			elif campaign_mode and progression_panel.visible: progression_panel.visible=false
			elif building_panel!=null and building_panel.popup.visible: building_panel.popup.hide()
			elif building_panel!=null and building_panel.dock.visible:
				selected_home=-1
				building_panel.hide_selection()
			elif world_view.layer_drag: cancel_drag()
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
