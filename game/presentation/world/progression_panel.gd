extends PanelContainer
## Complete recovered 2.4 catalog; simulation still validates every action.

signal command_requested(command: Dictionary)
signal power_requested(power: String)
const Style = preload("res://presentation/ui/style.gd")
const Card = preload("res://presentation/ui/source_card.gd")
const TYPE_ICONS := {"TECH":"Science","TRADE":"Industry","FAITH":"Religion","SOCIAL":"Society","WAR":"Military"}
var cards: Dictionary = {}
var inspect_command: Callable
var close_handler: Callable
var snapshot: Dictionary = {}
var selected := ""
var mode := "cards"
var content := VBoxContainer.new()
var last_revision := -1
var confirm_button: Button
var close_button: Button
var tabs: TabContainer
var detail: VBoxContainer
var tab_index := 0
var gallery_items: Dictionary = {}
var textures: Dictionary = {}
var resource_tray: HBoxContainer
var resource_slots: Dictionary = {}
var detail_card: TextureButton
var known_resources: Dictionary = {}
var last_timeline_step := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-450
	offset_right=450
	offset_top=-300
	offset_bottom=300
	add_theme_stylebox_override("panel",Style.box(Style.PANEL))
	add_child(content)
	visible=false


func apply_snapshot(state: Dictionary) -> void:
	var cliff_changed: bool=selected=="Card_GodPower_CliffSculpt" and snapshot.get("opening",{}).get("cliff_status",{})!=state.get("opening",{}).get("cliff_status",{})
	var collector_changed: bool=selected=="Card_Monument_BeliefCollect" and snapshot.get("opening",{}).get("collector_status",{})!=state.get("opening",{}).get("collector_status",{})
	snapshot=state
	var revision: int = state.get("progression",{}).get("revision",-1)
	var timeline_step: int=state.get("opening",{}).get("timeline_step",-1)
	if visible and (revision!=last_revision or timeline_step!=last_timeline_step or cliff_changed or collector_changed): redraw()
	last_timeline_step=timeline_step


func open_card(id: String) -> void:
	selected=id
	tab_index=1 if is_resource(cards.get(id, {})) else 0
	visible=true
	redraw()


func open_book() -> void:
	if visible:
		close_book()
		return
	visible=true
	if selected.is_empty(): selected="Card_Sculpting" if mode=="powers" else "Card_GenerateBelief"
	redraw()


func add_power_upgrade(status: Dictionary,command_type: String) -> void:
	var upgrade: Dictionary=status.get("next",{})
	if upgrade.is_empty(): return
	var cost: String="%d %s"%[int(upgrade["cost"]),upgrade["currency"]]
	var button:=Style.button("%s  ·  %s"%[upgrade["button"],cost],func() -> void: confirm_power_upgrade(upgrade,cost,command_type))
	button.disabled=not status["affordable"]
	detail.add_child(button)


func confirm_power_upgrade(upgrade: Dictionary,cost: String,command_type: String) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title=upgrade["title"]
	dialog.dialog_text="%s\n%s"%[upgrade["description"],cost]
	dialog.ok_button_text=upgrade["button"]
	dialog.theme=theme
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		command_requested.emit({"type":command_type,"id":upgrade["id"]})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func close_book() -> void:
	if close_handler.is_valid(): close_handler.call()
	else: hide()


func is_resource(card: Dictionary) -> bool:
	return card.get("kind", "") == "resources"


func is_power(card: Dictionary) -> bool:
	return card.get("kind", "") == "powers" or card.get("canonical_id", "") in ["Card_Sculpting", "Card_Adv_Leash_1"]


func clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func image_button(id: String,parent: Node,size_: Vector2,callback: Callable) -> TextureButton:
	if not cards.has(id) or not cards[id].get("available",false): return null
	var button := Card.new()
	button.source=cards[id]
	button.custom_minimum_size=size_
	configure_assignment(button,id)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func gameplay_id(entry: Dictionary,preferred: String="") -> String:
	var p: Dictionary = snapshot.get("progression", {})
	var rules: Dictionary = p.get("rules", {}).get("cards", {})
	if preferred.is_empty(): preferred=selected
	if rules.has(preferred) and cards.get(preferred, {}).get("canonical_id") == entry.get("canonical_id"): return preferred
	for id: String in entry.get("bindings", []):
		if rules.has(id) and id in p.get("discovered", []) and not id in p.get("completed", []): return id
	for id: String in entry.get("bindings", []):
		if rules.has(id): return id
	return ""


func configure_assignment(button: TextureButton,id: String) -> void:
	if not snapshot.has("progression") or is_resource(cards[id]): return
	var action := gameplay_id(cards[id],id)
	if action.is_empty(): return
	button.accept_resource=func(resource: String) -> Dictionary:
		return inspect_command.call({"type":"research_card","card":action,"sticker":resource}) if inspect_command.is_valid() else {"ok":false}
	button.assign_resource=func(resource: String) -> void:
		var command := {"type":"research_card","card":action,"sticker":resource}
		if inspect_command.is_valid() and inspect_command.call(command).get("ok",false): command_requested.emit(command)
	var p: Dictionary=snapshot["progression"]
	var status: Dictionary=p.get("card_progress",{}).get(action,{})
	if not status.is_empty() and not status.get("complete",false):
		button.progress=float(status["filled"])/maxi(1,int(status["total"]))
		button.progress_textures=textures
	for resource: String in p.get("assigned_resources",{}).get(action,{}):
		var canonical: String=p["rules"].get("sticker_aliases",{}).get(resource,resource)
		if cards.has(canonical) and button.applied_resources.size()<8: button.applied_resources.append(cards[canonical])


func contributions(id: String) -> Dictionary:
	var p: Dictionary=snapshot.get("progression",{})
	var canonical: String=cards.get(id,{}).get("canonical_id",id)
	return p.get("rules",{}).get("stickers",{}).get(canonical,{}).get("contributions",{})


func type_badges(parent: Node,types: Dictionary,icon_size: int=22,show_values: bool=true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	parent.add_child(row)
	for type: String in types:
		if int(types[type])<=0 or not TYPE_ICONS.has(type): continue
		var badge := TextureRect.new()
		badge.texture=textures.get("GFX_Cat%sSmall.png"%TYPE_ICONS[type])
		badge.custom_minimum_size=Vector2(icon_size,icon_size)
		badge.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.tooltip_text=type+(" × "+str(types[type]) if show_values else "")
		badge.set_meta("research_type",type)
		row.add_child(badge)
		if show_values: row.add_child(Style.label(str(types[type]),14,Style.TEXT))


func refresh_resource_fit() -> void:
	var entry: Dictionary=cards.get(selected,{})
	var action := gameplay_id(entry)
	var typed: bool=not snapshot.get("progression",{}).get("rules",{}).get("research_cards",{}).get(action,{}).is_empty()
	for id: String in resource_slots:
		var image: TextureButton=resource_slots[id]
		var fit: bool=not typed or (inspect_command.is_valid() and inspect_command.call({"type":"research_card","card":action,"sticker":id}).get("ok",false))
		image.self_modulate.a=1.0 if image.resource_count>0 and fit else 0.3
		image.tooltip_text=str(cards[id].get("title",id))+"\n"+str(contributions(id))+ ("\nMatches this card" if typed and fit else ("\nDoes not fit this card" if typed else ""))


func build_resource_tray() -> void:
	resource_slots.clear()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y=142
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	resource_tray=HBoxContainer.new()
	resource_tray.add_theme_constant_override("separation",14)
	scroll.add_child(resource_tray)
	var p: Dictionary=snapshot["progression"]
	for resource: String in p.get("inventory",{}): known_resources[str(p["rules"].get("sticker_aliases",{}).get(resource,resource))]=true
	for id: String in cards:
		var entry: Dictionary=cards[id]
		if id!=entry.get("canonical_id",id) or not entry.get("sticker",false) or not entry.get("available",false): continue
		var count := int(p.get("sticker_counts",{}).get(id,0))
		if count>0: known_resources[id]=true
		if count<=0 and not known_resources.has(id): continue
		var slot := VBoxContainer.new()
		resource_tray.add_child(slot)
		var image := Card.new()
		image.source=entry
		image.resource_id=id
		image.resource_count=count
		image.resource_drag_enabled=snapshot.get("opening",{}).get("phase")!="timeline" or snapshot["opening"].get("timeline_input_lock",3)<=1
		image.self_modulate.a=1.0 if count>0 else 0.3
		image.custom_minimum_size=Vector2(68,76)
		image.pressed.connect(func() -> void: selected=id; tab_index=1; redraw())
		slot.add_child(image)
		type_badges(slot,contributions(id),18)
		var amount := Style.label("× %d"%count,17,Style.TEXT)
		amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(amount)
		image.resource_dragged.connect(func(_resource: String,active: bool) -> void: amount.text="× %d"%maxi(0,count-(1 if active else 0)))
		resource_slots[id]=image
	if resource_slots.is_empty(): resource_tray.add_child(Style.label("No resources",16,Style.TEXT))
	refresh_resource_fit()


func quantity(entry: Dictionary) -> int:
	var p: Dictionary = snapshot.get("progression", {})
	var total := 0
	for id: String in entry.get("bindings", []):
		total += int(p.get("inventory", {}).get(id, 0))
		if not entry.get("sticker",false): total+=int(p.get("reward_history", {}).get(id, 0))
	return total


func redraw() -> void:
	clear(content)
	confirm_button=null
	gallery_items.clear()
	if not snapshot.has("progression"): return
	last_revision=int(snapshot["progression"]["revision"])
	var header := HBoxContainer.new()
	var heading := Style.label("Powers" if mode=="powers" else "Cards",26,Style.TEXT)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	close_button=Style.button("×",close_book)
	close_button.disabled=snapshot.get("opening",{}).get("phase")=="timeline" and snapshot["opening"].get("timeline_input_lock",3)>0
	header.add_child(close_button)
	content.add_child(header)
	var body := HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	content.add_child(body)
	tabs=TabContainer.new()
	tabs.add_theme_stylebox_override("panel",Style.box(Style.PANEL))
	tabs.custom_minimum_size.x=350
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var categories := ["Powers"] if mode=="powers" else ["Advances","Resources"]
	var ids: Array = cards.keys()
	ids.sort_custom(func(a: String,b: String) -> bool: return int(cards[a].get("number",0))<int(cards[b].get("number",0)) if cards[a].get("number",0)!=cards[b].get("number",0) else a<b)
	for category: String in categories:
		var scroll := ScrollContainer.new()
		scroll.name=category
		tabs.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns=3
		grid.add_theme_constant_override("h_separation",7)
		grid.add_theme_constant_override("v_separation",10)
		scroll.add_child(grid)
		for id: String in ids:
			var entry: Dictionary = cards[id]
			if id != entry.get("canonical_id",id) or entry.get("internal",false) or entry.get("archived",false): continue
			if mode=="powers" and not is_power(entry): continue
			if mode!="powers" and (entry.get("kind")=="powers" or (category=="Resources")!=is_resource(entry)): continue
			var slot := VBoxContainer.new()
			slot.custom_minimum_size.x=96
			grid.add_child(slot)
			image_button(id,slot,Vector2(96,144),func() -> void: selected=id; show_detail())
			var title := Style.label(entry["title"],14,Style.TEXT)
			title.custom_minimum_size.x=96
			title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			slot.add_child(title)
			if is_resource(entry): slot.add_child(Style.label(str(quantity(entry)),18,Style.TEXT))
			if is_resource(entry): type_badges(slot,contributions(id),18)
			gallery_items[id]=slot
	tabs.current_tab=0 if mode=="powers" else clampi(tab_index,0,1)
	tabs.tab_changed.connect(func(index: int) -> void: tab_index=index)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(detail_scroll)
	detail=VBoxContainer.new()
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail)
	show_detail()
	build_resource_tray()


func paragraph(text_: String,size_: int = 17) -> void:
	if text_.is_empty(): return
	var label := Style.label(text_,size_,Style.TEXT)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(label)


func show_detail() -> void:
	clear(detail)
	confirm_button=null
	detail_card=null
	if selected.is_empty() or not snapshot.has("progression"): return
	var entry: Dictionary = cards.get(selected, {})
	if entry.is_empty(): paragraph("Unavailable"); return
	var p: Dictionary = snapshot["progression"]
	refresh_resource_fit()
	paragraph(entry["title"],26)
	if is_resource(entry): type_badges(detail,contributions(selected),28)
	else:
		var research_id := gameplay_id(entry)
		var typed: Dictionary=p["rules"].get("research_cards",{}).get(research_id,{})
		if not typed.is_empty(): type_badges(detail,{str(typed["research_type"]):1},28,false)
	if entry.get("available",false):
		var image := Card.new()
		image.source=entry
		image.detail=true
		configure_assignment(image,selected)
		image.custom_minimum_size=Vector2(150,225)
		image.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		image.mouse_filter=Control.MOUSE_FILTER_STOP
		detail.add_child(image)
		detail_card=image
	else: paragraph(entry.get("unavailable_reason","Unavailable"))
	paragraph(str(entry.get("description", "")))
	if str(entry.get("description", "")).is_empty() and not is_resource(entry):
		paragraph("Explanation unavailable in the supplied original game data.")
	var action := gameplay_id(entry)
	var definition: Dictionary = p["rules"]["cards"].get(action, {})
	if is_resource(entry):
		paragraph("Available: %d" % quantity(entry))
		paragraph("Find resources in chests on land, buried under terrain, and as adventure rewards. Chests replenish in your active territory. Drag a resource onto an advance with a matching research type.",15)
		for key: String in entry.get("reward", {}):
			if int(entry["reward"][key])>0: paragraph("+%d %s" % [int(entry["reward"][key]),key])
		for key: String in contributions(selected): paragraph("%s × %d" % [key.capitalize(),contributions(selected)[key]])
		for id: String in p["rules"]["cards"]:
			if p["rules"].get("research_cards",{}).has(id): continue
			for resource: String in p["rules"]["cards"][id]["requirements"]:
				if cards.get(resource, {}).get("canonical_id") == entry["canonical_id"]:
					paragraph("%s × %d" % [cards.get(id,{}).get("title",p["rules"]["cards"][id]["title"]),p["rules"]["cards"][id]["requirements"][resource]],15)
		return
	if not definition.is_empty() and not p["rules"].get("research_cards",{}).has(action):
		var requirements := HBoxContainer.new()
		detail.add_child(requirements)
		for resource: String in definition["requirements"]:
			var slot := VBoxContainer.new()
			requirements.add_child(slot)
			image_button(resource,slot,Vector2(54,66),func() -> void: selected=resource; tab_index=1; redraw())
			var required: int = definition["requirements"][resource]
			var supplied: int = required if action in p["completed"] else mini(required,int(p.get("assigned_resources",{}).get(action,{}).get(resource,0)))
			slot.add_child(Style.label("%d / %d" % [supplied,required],19,Style.TEXT))
			slot.add_child(Style.label("Available: %d"%int(p.get("resource_counts",{}).get(resource,p["inventory"].get(resource,0))),14,Style.TEXT))
	if is_power(entry) or not str(entry.get("power","")).is_empty():
		if entry["canonical_id"]=="Card_Sculpting":
			detail.add_child(Style.button("Sculpt Land",func() -> void: power_requested.emit("GodPower_LandManipulation"); visible=false))
			return
		if action.begins_with("Card_GodPower_") or not str(entry.get("power","")).is_empty():
			var power: String = definition.get("power","")
			if power.is_empty(): power=str(entry.get("power",""))
			if power.is_empty(): power=action.trim_prefix("Card_")
			var cost := int(p["rules"].get("economy",{}).get("settlements",{}).get(power,{}).get("cost",p["rules"]["config"].get("belief_"+power.trim_prefix("GodPower_"),0)))
			var rain: Dictionary=snapshot.get("opening",{}).get("definition",{}).get("rain",{})
			var fountain: Dictionary=snapshot.get("opening",{}).get("definition",{}).get("fountain",{})
			var cliff: Dictionary=snapshot.get("opening",{}).get("definition",{}).get("cliff_sculpt",{})
			var collector: Dictionary=snapshot.get("opening",{}).get("collector_status",{})
			var collector_power: bool=power=="GodPower_PlaceBeliefCollect" and not collector.is_empty()
			if not rain.is_empty() and power==rain["power"]:
				paragraph("%d belief per second" % int(rain["cost_per_second"]))
			elif not fountain.is_empty() and power==fountain["power"]:
				paragraph("%d gems" % int(fountain["gems"]))
			elif not cliff.is_empty() and power==cliff["power"]:
				var status: Dictionary=snapshot["opening"].get("cliff_status",{})
				paragraph("%s  %d" % [cliff["layers_label"],int(status.get("layers",cliff["layers"]))])
			elif collector_power: paragraph("Belief: %d" % int(collector["price"]))
			else: paragraph("Belief: %d" % cost)
			if power=="GodPower_TotemActivate":
				paragraph("Capacity: %d" % int(p["totem_capacity"]))
				var move := Style.button("Move Totem",func() -> void: power_requested.emit("GodPower_Totem"); visible=false)
				move.disabled=not "GodPower_Totem" in p["powers"]
				detail.add_child(move)
			var cast := Style.button(entry["title"],func() -> void: power_requested.emit(power); visible=false)
			cast.disabled=not power in p["powers"]
			if not fountain.is_empty() and power==fountain["power"]:
				cast.disabled=cast.disabled or int(snapshot.get("gems",0))<int(fountain["gems"])
			if collector_power: cast.disabled=not collector["can_place"]
			detail.add_child(cast)
			if power=="GodPower_CliffSculpt": add_power_upgrade(snapshot.get("opening",{}).get("cliff_status",{}),"campaign_cliff_upgrade")
			if collector_power: add_power_upgrade(collector,"campaign_belief_collector_upgrade")
			if not power in p["powers"]:
				var links := {}
				for condition: String in p["rules"].get("source_unlocks",{}).get(power,[]):
					var required := condition.trim_suffix("_COMPLETED")
					if not p["rules"]["cards"].has(required) or links.has(required): continue
					links[required]=true
					var title: String=cards.get(required,{}).get("title",p["rules"]["cards"][required]["title"])
					detail.add_child(Style.button("Unlock through "+title,func() -> void: open_card(required)))
				if links.is_empty(): paragraph("Unavailable")
		else: paragraph("Unavailable")
		return
	if action.is_empty(): paragraph("Unavailable"); return
	if action in p["completed"]: paragraph("Completed"); return
	var research: Dictionary = p["rules"].get("research_cards",{}).get(action,{})
	if not research.is_empty():
		paragraph("%s: %d / %d"%[str(research["research_type"]).capitalize(),int(p.get("research",{}).get(action,0)),int(research["research_needed"])])
		if int(research["research_needed"])>0: paragraph("Find more resources in chests in your active territory or earn them on adventures.",15)
		if int(research["research_needed"])>0:
			paragraph("Drag one of these compatible resources onto the card:",15)
			var compatible := HFlowContainer.new()
			detail.add_child(compatible)
			for resource: String in p["rules"].get("stickers",{}):
				var contribution := int(p["rules"]["stickers"][resource].get("contributions",{}).get(research["research_type"],0))
				if contribution<=0 or not cards.get(resource,{}).get("available",false) or p["rules"]["stickers"][resource].get("internal",false): continue
				var slot := VBoxContainer.new()
				compatible.add_child(slot)
				var image := image_button(resource,slot,Vector2(48,62),func() -> void: selected=resource; tab_index=1; redraw())
				if image!=null:
					image.resource_id=resource
					image.resource_count=int(p.get("sticker_counts",{}).get(resource,0))
				type_badges(slot,contributions(resource),18)
				slot.add_child(Style.label("+%d · ×%d"%[contribution,int(p.get("sticker_counts",{}).get(resource,0))],14,Style.TEXT))
		if int(research["research_needed"])>0: return
	elif not definition["requirements"].is_empty(): return
	confirm_button=Style.button("Complete card",func() -> void: command_requested.emit({"type":"claim_card","card":action}))
	confirm_button.disabled=not inspect_command.is_valid() or not inspect_command.call({"type":"claim_card","card":action}).get("ok",false)
	detail.add_child(confirm_button)
