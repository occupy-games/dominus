extends Control
## Voyage controls display simulation-owned objective, timer and outcome.

signal start_requested(followers: int)
signal return_requested
signal retry_requested
signal next_requested
signal power_requested(power: String)
const Style = preload("res://presentation/ui/style.gd")
var definition: Dictionary = {}
var textures: Dictionary = {}
var objective: Label
var timer: Label
var result: Label
var followers: HSlider
var count: Label
var launch: Button
var ready_panel: PanelContainer
var outcome: PanelContainer
var next_button: Button
var belief: Label
var cards: Dictionary = {}
var power_assets: Dictionary = {}
var power_row: HBoxContainer
var shown_powers: Array = []
var rewards: HBoxContainer
var hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=16
	top.offset_right=-16
	top.offset_top=12
	top.add_theme_constant_override("separation",12)
	add_child(top)
	var boat := TextureRect.new()
	boat.texture=textures.get("GFX_EventsShip.png")
	boat.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	boat.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boat.custom_minimum_size=Vector2(44,44)
	top.add_child(boat)
	objective=Style.label("",20)
	objective.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	top.add_child(objective)
	var belief_group := HBoxContainer.new()
	belief_group.visible=not definition.get("free_sculpt",false)
	belief_group.alignment=BoxContainer.ALIGNMENT_CENTER
	var icon := TextureRect.new()
	icon.texture=textures.get("GFX_IconBelief.png")
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size=Vector2(24,24)
	belief_group.add_child(icon)
	var pill := preload("res://presentation/ui/source_pill.gd").new()
	pill.rim_texture=textures.get("IWProgbar_Grey.png")
	pill.cap_texture=textures.get("GFX_IWProgbarRound_Pink.png")
	pill.value=1
	pill.custom_minimum_size=Vector2(100,24)
	pill.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	belief_group.add_child(pill)
	belief=Style.label("",18)
	belief.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	belief.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	belief.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	pill.add_child(belief)
	top.add_child(belief_group)
	timer=Style.label("",24)
	top.add_child(timer)
	top.add_child(Style.button("← Voyages",func() -> void: return_requested.emit()))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(center)
	ready_panel=PanelContainer.new()
	ready_panel.custom_minimum_size.x=360
	center.add_child(ready_panel)
	var ready_column := VBoxContainer.new()
	ready_column.add_theme_constant_override("separation",12)
	ready_panel.add_child(ready_column)
	ready_column.add_child(Style.label(str(definition.get("name","Voyage")),28))
	var help := Style.label("Reach the temple with %d followers.\nDrag terrain layers to clear their route."%int(definition["required"]),18)
	ready_column.add_child(help)
	count=Style.label("",20)
	ready_column.add_child(count)
	followers=HSlider.new()
	followers.min_value=int(definition["minimum"])
	followers.max_value=int(definition["maximum"])
	followers.step=1
	followers.value=followers.min_value
	followers.value_changed.connect(func(value: float) -> void: count.text="%d followers aboard"%int(value))
	count.text="%d followers aboard"%int(followers.value)
	ready_column.add_child(followers)
	launch=Style.button("Set sail",func() -> void: start_requested.emit(int(followers.value)))
	launch.icon=load("res://assets/dominus.png")
	launch.expand_icon=true
	launch.add_theme_constant_override("icon_max_width",36)
	ready_column.add_child(launch)
	outcome=PanelContainer.new()
	outcome.custom_minimum_size.x=360
	center.add_child(outcome)
	var finished := VBoxContainer.new()
	finished.add_theme_constant_override("separation",12)
	outcome.add_child(finished)
	result=Style.label("",24)
	finished.add_child(result)
	rewards=HBoxContainer.new()
	finished.add_child(rewards)
	finished.add_child(Style.button("Try again",func() -> void: retry_requested.emit()))
	next_button=Style.button("Next island",func() -> void: next_requested.emit())
	finished.add_child(next_button)
	finished.add_child(Style.button("Return by boat",func() -> void: return_requested.emit()))
	outcome.hide()
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position=Vector2(16,-112)
	add_child(bottom)
	hint=Style.label("",18)
	hint.custom_minimum_size.x=400
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(hint)
	power_row=HBoxContainer.new()
	bottom.add_child(power_row)
	var sculpt := TextureButton.new()
	sculpt.texture_normal=textures.get("sculpt_circle")
	sculpt.ignore_texture_size=true
	sculpt.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	sculpt.custom_minimum_size=Vector2(56,56)
	sculpt.tooltip_text="Sculpt Land"
	var hand := TextureRect.new()
	hand.texture=textures.get("sculpt_hand")
	hand.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	hand.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hand.position=Vector2(11,9)
	hand.size=Vector2(34,37)
	hand.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sculpt.add_child(hand)
	sculpt.pressed.connect(func() -> void: power_requested.emit(""))
	power_row.add_child(sculpt)


func apply_snapshot(state: Dictionary) -> void:
	var voyage: Dictionary = state["voyage"]
	belief.text=str(int(state["belief"]))
	objective.text="%d / %d at the temple · %d aboard"%[int(voyage["rescued"]),int(definition["required"]),int(voyage["aboard"])]
	var remaining := maxi(0,ceili(float(definition["seconds"])-float(voyage["elapsed"])*0.1))
	timer.text="%d:%02d"%[remaining/60,remaining%60]
	ready_panel.visible=voyage["phase"]=="ready"
	outcome.visible=voyage["phase"] in ["won","lost"]
	next_button.visible=voyage["phase"]=="won" and not str(definition.get("next_id","")).is_empty()
	result.text=("One Voyage Complete!\n%d / 3 stars · %d score"%[int(voyage["stars"]),int(voyage["score"])]) if voyage["phase"]=="won" else "Time has run out.\n%d / %d reached the temple."%[int(voyage["rescued"]),int(definition["required"])]
	var powers: Array = voyage.get("powers",[])
	if powers!=shown_powers:
		shown_powers=powers.duplicate()
		for child: Node in power_row.get_children().slice(1): child.queue_free()
		for power: String in powers:
			if not power_assets.has(power):
				var text_button := Style.button(power.trim_prefix("GodPower_"),func() -> void: power_requested.emit(power))
				power_row.add_child(text_button)
				continue
			var button := TextureButton.new()
			button.texture_normal=power_assets[power]["texture"]
			button.ignore_texture_size=true
			button.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			button.custom_minimum_size=Vector2(52,78)
			button.tooltip_text=power_assets[power]["title"]+" · %d belief"%int(definition.get("power_data",{}).get(power,{}).get("cost",0))
			button.pressed.connect(func() -> void: power_requested.emit(power))
			power_row.add_child(button)


func show_rewards(awards: Array) -> void:
	for child: Node in rewards.get_children(): child.queue_free()
	var totals := {}
	for award: Dictionary in awards: totals[award["id"]]=int(totals.get(award["id"],0))+int(award["count"])
	for id: String in totals:
		var column := VBoxContainer.new()
		rewards.add_child(column)
		if cards.has(id):
			var card := preload("res://presentation/ui/source_card.gd").new()
			card.source=cards[id]
			card.custom_minimum_size=Vector2(64,90)
			column.add_child(card)
		column.add_child(Style.label("× %d"%int(totals[id]),18))
	if not awards.is_empty(): hint.text="Stickers will be available in Homeworld."
