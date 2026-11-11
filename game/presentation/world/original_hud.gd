extends Control
## Reconstructs the original HUD's counters, cards and buttons from source sprites.

signal settings_requested
signal collect_requested
signal sculpt_requested
signal card_requested(id: String)
signal collection_requested
signal power_requested(power: String)

const Style = preload("res://presentation/ui/style.gd")
const Pill = preload("res://presentation/ui/source_pill.gd")
const Card = preload("res://presentation/ui/source_card.gd")
var textures: Dictionary = {}
var cards: Dictionary = {}
var population := Label.new()
var target := Label.new()
var belief := Label.new()
var gems := Label.new()
var bar := Pill.new()
var belief_bar := Pill.new()
var gems_bar := Pill.new()
var resource_rows: Dictionary = {}
var gems_button: TextureButton
var gems_icon: TextureRect
var happiness_gauge: Control
var follower_icon: TextureRect
var belief_icon: TextureButton
var collection_button: TextureButton
var settings_button: TextureButton
var sculpt_button: TextureButton
var sculpt_hand: TextureRect
var card_nodes: Dictionary = {}
var card_row := HBoxContainer.new()
var powers: Dictionary = {}
var power_nodes: Dictionary = {}


func picture(name: String, position_: Vector2, size_: Vector2, parent: Node = self) -> TextureRect:
	var node := TextureRect.new()
	node.texture = textures.get(name)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = position_
	node.size = size_
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func sprite_button(name: String, position_: Vector2, size_: Vector2, callback: Callable, parent: Node = self) -> TextureButton:
	var node := TextureButton.new()
	node.texture_normal = textures.get(name)
	node.ignore_texture_size = true
	node.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	node.position = position_
	node.size = size_
	node.pressed.connect(callback)
	parent.add_child(node)
	return node


func counter(label: Label, position_: Vector2, size_: Vector2, parent: Node = self) -> void:
	label.position = position_
	label.size = size_
	label.add_theme_font_override("font",Style.source_font())
	label.add_theme_font_size_override("font_size",16)
	label.add_theme_color_override("font_color",Color.BLACK)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.theme_changed.connect(func() -> void: fit_counter(label))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	collection_button = sprite_button("GFX_CEPopFront.png",Vector2(24,12),Vector2(56,56),func() -> void: collection_requested.emit())
	card_row.position = Vector2(88,12)
	card_row.add_theme_constant_override("separation",5)
	add_child(card_row)
	for id: String in ["Card_MaxRank_2","Card_RepairTemple","Card_Spirituality","Card_GodPower_TotemActivate","Card_DoubleClick","Card_AbodeType_2","Card_RockBelief_1","Card_Adv_BeliefCollection","Card_Settlement_Farming","Card_GrainToBuild","Card_Adv_RainOfPurity_1","Card_Stickers_Bronze","Card_AbodeType1_Rank2","Card_CliffSculptingLevel1","Card_Adv_Fountain","Card_AbodeType2_Rank3","Card_Settlement_Follower","Card_AbodeType2_Rank4","Card_Adv_FingerOfGod_1","Card_Capacity_1","Card_Adv_Swamp_1","Card_UnderWaterSculpt","Card_Adv_MeteorStrike_1","Card_Stickers_Iron","Card_Settlement_Mine","Card_RepairTemple_2","Card_WheatBuff_1","Card_AbodeType3_Rank5","Card_AbodeType3_Rank6","Card_Speed_1"]:
		if not cards.has(id): continue
		var node := Card.new()
		node.source = cards[id]
		node.custom_minimum_size = Vector2(40,60)
		node.pressed.connect(func() -> void: card_requested.emit(id))
		card_row.add_child(node)
		card_nodes[id] = node
	follower_icon = picture("GFX_Pawn_Standard.png",Vector2(24,83.1),Vector2(24,19.8))
	add_resource_row("followers",bar,population,target,81,"GFX_IWProgbarRound_Cyan.png")
	for entry: Array in [["wheat","GFX_IconWheatRate.png",113,"GFX_IWProgbarRound_Yellow.png"],["ore","GFX_IconMining.png",145,"GFX_IWProgbarRound_Grey.png"]]:
		picture(entry[1],Vector2(24,entry[2]),Vector2(24,24))
		add_resource_row(entry[0],Pill.new(),Label.new(),Label.new(),entry[2],entry[3])
	var right := Control.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-80,12)
	add_child(right)
	settings_button = sprite_button("GFX_CESettings_Front.png",Vector2.ZERO,Vector2(56,56),func() -> void: settings_requested.emit(),right)
	var bottom := Control.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(24,-104)
	add_child(bottom)
	belief_icon = sprite_button("GFX_IconBelief.png",Vector2(-18.5,0),Vector2(24,24),func() -> void: collect_requested.emit(),bottom)
	belief_bar.rim_texture = textures.get("IWProgbar_Grey.png")
	belief_bar.cap_texture = textures.get("GFX_IWProgbarRound_Pink.png")
	belief_bar.position = Vector2(11.5,0)
	belief_bar.size = Vector2(63,24)
	belief_bar.value = 1
	bottom.add_child(belief_bar)
	counter(belief,Vector2(19.5,0),Vector2(47,24),bottom)
	belief.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	sculpt_button = sprite_button("sculpt_circle",Vector2(0,32),Vector2(56,56),func() -> void: sculpt_requested.emit(),bottom)
	sculpt_hand = picture("sculpt_hand",Vector2(11,9),Vector2(34,37.3),sculpt_button)
	var bottom_right := Control.new()
	bottom_right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.position=Vector2(-80,-104)
	add_child(bottom_right)
	gems_icon=picture("GFX_IconGemsSmall.png",Vector2(-18.5,0),Vector2(24,24),bottom_right)
	gems_bar.rim_texture=textures.get("IWProgbar_Grey.png")
	gems_bar.cap_texture=textures.get("GFX_IWProgbarRound_Yellow.png")
	gems_bar.position=Vector2(11.5,0)
	gems_bar.size=Vector2(63,24)
	gems_bar.value=1
	bottom_right.add_child(gems_bar)
	counter(gems,Vector2(19.5,0),Vector2(47,24),bottom_right)
	gems.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	gems_button=sprite_button("GFX_CEGems_Front.png",Vector2(0,32),Vector2(56,56),func() -> void: pass,bottom_right)
	# Real-money store content is unavailable until its original flow is supported.
	gems_button.disabled=true
	gems_button.tooltip_text="Gem store unavailable"
	for button: TextureButton in [collection_button,settings_button,sculpt_button,gems_button]: button.self_modulate.a=0.65
	happiness_gauge=preload("res://presentation/ui/happiness_gauge.gd").new()
	happiness_gauge.textures=textures
	happiness_gauge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	happiness_gauge.position=Vector2(-38,-320)
	happiness_gauge.size=Vector2(8,165)
	add_child(happiness_gauge)
	var power_row := HBoxContainer.new()
	power_row.position=Vector2(72,36)
	bottom.add_child(power_row)
	for power: String in powers:
		var node := TextureButton.new()
		node.texture_normal=powers[power]["texture"]
		node.ignore_texture_size=true
		node.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		node.custom_minimum_size=Vector2(64,64)
		node.tooltip_text=powers[power]["title"]
		node.pressed.connect(func() -> void: power_requested.emit(power))
		power_row.add_child(node)
		power_nodes[power]=node


func apply_snapshot(data: Dictionary) -> void:
	var count: int = data["followers"].size()
	var next := 10 if count < 10 else (15 if count < 15 else (30 if count < 30 else 50))
	if data.has("progression"): next=int(data["progression"].get("next_population",next))
	var metrics: Dictionary = data.get("currency_metrics",{})
	for resource: String in resource_rows:
		var row: Dictionary = resource_rows[resource]
		var metric: Dictionary = metrics.get(resource,{"amount":count if resource=="followers" else int(data.get(resource,0)),"next":next if resource=="followers" else 0,"progress":0})
		row["amount"].text=compact_number(int(metric["amount"]))
		row["amount"].tooltip_text=str(metric["amount"])
		row["target"].text=compact_number(int(metric["next"])) if int(metric["next"])>0 else ""
		row["bar"].max_value=1
		row["bar"].value=float(metric["progress"])
		fit_counter(row["amount"])
		fit_counter(row["target"])
	belief.text=compact_number(int(data["belief"]))
	belief.tooltip_text=str(data["belief"])
	var show_belief: bool=not data.get("opening",{}).get("belief_hud_hidden",false)
	belief.visible=show_belief
	belief_icon.visible=show_belief
	belief_bar.visible=show_belief
	gems.text=compact_number(int(data.get("gems",0)))
	gems.tooltip_text=str(data.get("gems",0))
	for label: Label in [belief,gems]: fit_counter(label)
	happiness_gauge.visible=data.has("tribe_happiness")
	if happiness_gauge.visible: happiness_gauge.apply_values(data["tribe_happiness"])
	for id: String in card_nodes:
		var threshold: int = {"Card_MaxRank_2":10,"Card_RepairTemple":16,"Card_Spirituality":24,"Card_GodPower_TotemActivate":50,"Card_DoubleClick":15,"Card_AbodeType_2":30,"Card_Settlement_Farming":165}.get(id,2147483647)
		card_nodes[id].visible = (id in data["progression"]["discovered"] and not id in data["progression"]["completed"]) if data.has("progression") else count >= threshold
		card_nodes[id].disabled = false
	for power: String in power_nodes:
		power_nodes[power].visible=data.has("progression") and power in data["progression"]["powers"]
		var active: bool = power=="GodPower_TotemActivate" and data.has("progression") and data["progression"]["totem"].get("active",false)
		if power=="GodPower_FingerOfGod": active=data.get("opening",{}).get("finger_status",{}).get("active",false)
		power_nodes[power].texture_normal=powers[power]["alternate"] if active else powers[power]["texture"]
		power_nodes[power].tooltip_text=powers[power]["alt_title"] if active else powers[power]["title"]


func show_settings_only() -> void:
	for child: Control in get_children(): child.visible=child==settings_button.get_parent()


func fit_counter(label: Label) -> void:
	var font := Style.source_font()
	var font_size := 16
	while font_size > 9 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	if label.get_theme_font_size("font_size") != font_size:
		label.add_theme_font_size_override("font_size", font_size)


func add_resource_row(id: String, progress: Control, amount: Label, maximum: Label, y: float, cap: String) -> void:
	progress.rim_texture=textures.get("IWProgbar_Grey.png")
	progress.cap_texture=textures.get(cap)
	progress.position=Vector2(54,y)
	progress.size=Vector2(126,24)
	add_child(progress)
	counter(amount,Vector2(62,y),Vector2(110,24))
	counter(maximum,Vector2(186,y),Vector2(64,24))
	resource_rows[id]={"bar":progress,"amount":amount,"target":maximum}


func compact_number(amount: int) -> String:
	for entry: Array in [[1000000000000,"T"],[1000000000,"B"],[1000000,"M"],[1000,"K"]]:
		if amount>=entry[0]: return ("%.1f"%(float(amount)/entry[0])).trim_suffix(".0")+entry[1]
	return str(amount)
