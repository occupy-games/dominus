extends Control
## original game selection buttons and info window. Receives detached numeric queries.

signal action_requested(action: String)
const Style = preload("res://presentation/ui/style.gd")
var textures: Dictionary = {}
var labels: Dictionary = {}
var stats: Dictionary = {}
var dock := HBoxContainer.new()
var popup := PanelContainer.new()
var canvas := Control.new()
var title: Label
var subtitle: Label
var picture := TextureRect.new()
var rows := VBoxContainer.new()
var description: Label
var occupancy := Label.new()
var belief := Label.new()
var collect_button: TextureButton
var upgrade_button: TextureButton
var repair_button: TextureButton
var voyage_button: TextureButton
var ark_button: TextureButton
var ark_caption: Label
var finish_button: TextureButton
var finish_price := Label.new()
var finish_caption: Label
var row_values: Dictionary = {}
var current_art := ""
var row_layout := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	theme=Style.make_theme()
	dock.add_theme_constant_override("separation",12)
	add_child(dock)
	collect_button=action_button("GFX_IWIcon_Belief.png","Belief",belief,func() -> void: action_requested.emit("collect"))
	action_button("GFX_IWIcon_Breeder.png","Occupants",occupancy,func() -> void: popup.visible=not popup.visible)
	action_button("GFX_IWIcon_InfoNoShadow.png","Info",Label.new(),func() -> void: popup.visible=not popup.visible)
	upgrade_button=action_button("GFX_IWIcon_Boost.png","Upgrade",Label.new(),func() -> void: action_requested.emit("upgrade"))
	repair_button=action_button("GFX_Pawn_Worker.png",str(labels.get("LOC_BUTTON_SETTLEMENT_ASSIGN_BUILDERS","Builders")),Label.new(),func() -> void: action_requested.emit("repair"))
	var go: String=labels.get("LOC_BUTTON_DOCK_GO","")
	voyage_button=action_button("",go,Label.new(),func() -> void: action_requested.emit("voyage"))
	var caption:=label_at(voyage_button,go,Vector2.ZERO,Vector2(64,60),22)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	ark_button=action_button("","",Label.new(),func() -> void: action_requested.emit("ark"))
	ark_caption=label_at(ark_button,"",Vector2.ZERO,Vector2(64,60),16)
	ark_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	ark_caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	finish_button=action_button("GFX_IconGemsSmall.png","",finish_price,func() -> void: action_requested.emit("finish"))
	finish_caption=finish_button.get_parent().get_child(2)
	add_child(canvas)
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.size=Vector2(760,500)
	canvas.add_child(popup)
	popup.size=canvas.size
	var background := Style.box(Style.PANEL)
	popup.add_theme_stylebox_override("panel",background)
	var body := Control.new()
	body.custom_minimum_size=Vector2(760,500)
	popup.add_child(body)
	title=label_at(body,"",Vector2(70,12),Vector2(620,40),30)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	subtitle=label_at(body,"",Vector2(70,52),Vector2(620,28),19)
	subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var close := TextureButton.new()
	close.texture_normal=textures.get("GFX_CloseButton.png")
	close.ignore_texture_size=true
	close.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.position=Vector2(700,14)
	close.size=Vector2(42,42)
	close.tooltip_text="Close"
	close.pressed.connect(func() -> void: popup.hide())
	body.add_child(close)
	for y in [87,335,396]:
		var line := TextureRect.new()
		# The source atlas stores this separator vertically. Rotate the whole
		# texture into a horizontal rule, preserving its original round dots.
		line.texture=textures.get("GFX_DottedLine.png")
		line.position=Vector2(735,y)
		line.size=Vector2(11,1420)
		line.scale=Vector2.ONE*0.5
		line.rotation=PI*0.5
		line.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		line.stretch_mode=TextureRect.STRETCH_TILE
		line.modulate=Color(0.45,0.45,0.55,0.7)
		line.mouse_filter=Control.MOUSE_FILTER_IGNORE
		body.add_child(line)
	picture.position=Vector2(25,99)
	picture.size=Vector2(285,225)
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	body.add_child(picture)
	rows.position=Vector2(326,103)
	rows.size=Vector2(402,224)
	rows.add_theme_constant_override("separation",9)
	body.add_child(rows)
	description=label_at(body,"",Vector2(40,410),Vector2(680,76),17)
	description.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	resized.connect(layout)
	layout()
	hide_selection()


func label_at(parent: Node,value: String,position_: Vector2,extent: Vector2,font_size: int) -> Label:
	var label := Style.label(value,font_size,Color("313131"))
	label.position=position_
	label.size=extent
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func action_button(icon: String,caption: String,value: Label,callback: Callable) -> TextureButton:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x=86
	column.alignment=BoxContainer.ALIGNMENT_CENTER
	dock.add_child(column)
	var button := TextureButton.new()
	button.texture_normal=textures.get("info_circle")
	button.self_modulate.a=0.65
	button.custom_minimum_size=Vector2(64,60)
	button.ignore_texture_size=true
	button.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	button.tooltip_text=caption
	button.pressed.connect(callback)
	column.add_child(button)
	var image := TextureRect.new()
	image.texture=textures.get(icon)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.position=Vector2(12,5)
	image.size=Vector2(40,40)
	image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	button.add_child(image)
	value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color",Color("313131"))
	column.add_child(value)
	var label := Style.label(caption,16,Color("313131"))
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return button


func layout() -> void:
	var factor := minf(1.0,minf((size.x-24)/760.0,(size.y-140)/500.0))
	factor=maxf(0.1,factor)
	canvas.scale=Vector2.ONE*factor
	canvas.position=Vector2((size.x-760*factor)*0.5,maxf(10,(size.y-120-500*factor)*0.5))
	dock.reset_size()
	dock.position=Vector2((size.x-dock.size.x)*0.5,size.y-115)


func hide_selection() -> void:
	stats={}
	dock.hide()
	popup.hide()


func time_text(seconds: float) -> String:
	if seconds<0: return "—"
	var count := ceili(seconds)
	return "%d:%02d"%[count/60,count%60]


func stat(key: String,value: String,icon: String="") -> void:
	if row_values.has(key):
		row_values[key].text=value
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	if not icon.is_empty():
		var image := TextureRect.new()
		image.texture=textures.get(icon)
		image.custom_minimum_size=Vector2(23,23)
		image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
	var name_ := Style.label(str(labels.get(key,key)),18,Color("313131"))
	name_.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(name_)
	var value_ := Style.label(value,19,Color("313131"))
	value_.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_)
	rows.add_child(row)
	row_values[key]=value_


func present(data: Dictionary,art: Dictionary,can_collect: bool,can_upgrade: bool,can_repair: bool=false,can_voyage: bool=false,ark_action: String="",finish: Dictionary={}) -> void:
	if data.is_empty(): hide_selection(); return
	stats=data.duplicate(true)
	dock.show()
	collect_button.get_parent().visible=not data.get("kind","") in ["shrine","ark"]
	occupancy.get_parent().visible=data.get("kind","")!="shrine" or data.get("site_type")=="Wayland_Ark" and data["capacity"]>0
	upgrade_button.get_parent().visible=can_upgrade
	repair_button.get_parent().visible=data.get("entity")=="temple" and not data.get("started",false) and not data.get("complete",false)
	repair_button.disabled=not can_repair
	voyage_button.get_parent().visible=can_voyage
	ark_button.get_parent().visible=not ark_action.is_empty()
	ark_button.tooltip_text=ark_action
	ark_caption.text=ark_action
	finish_button.get_parent().visible=finish.has("gems")
	finish_button.disabled=not finish.get("ok",false)
	finish_button.tooltip_text=finish.get("label","")
	finish_caption.text=finish_button.tooltip_text
	finish_price.text=str(finish.get("gems",""))
	collect_button.disabled=not can_collect
	occupancy.text="%d / %d"%[data["occupants"],data["capacity"]]
	var collect_sprite := "GFX_IWIcon_Belief.png"
	if data.has("available_harvest"): collect_sprite="GFX_IWIcon_Wheat.png" if data["kind"]=="farm" else "GFX_IWIcon_Mining.png"
	collect_button.texture_normal=textures.get(collect_sprite)
	collect_button.tooltip_text="Wheat" if data.get("kind")=="farm" else ("Ore" if data.get("kind")=="mine" else "Belief")
	belief.text=str(data.get("available_harvest",data["belief"]))
	title.text=str(art.get("title",data.get("name","Abode")))
	if title.text.is_empty(): title.text=str(data["role"]).capitalize()+" Settlement" if data.get("entity")=="settlement" else ("Shrine" if data.get("kind","")=="shrine" else "Abode")
	subtitle.text=str(labels.get("LOC_INFO_SUB_BUILDERS","Builders")) if data.get("entity")=="home" and data.get("kind","")=="" else str(data.get("role",data.get("kind",""))).capitalize()
	var path := str(art.get("texture_path",""))
	if current_art!=path:
		current_art=path
		picture.texture=art.get("texture")
	var next_layout := "%s:%s:%s:%s:%s:%s:%s"%[data.get("entity","home"),data.get("kind",""),data.get("complete",true),data.get("started",false),int(data.get("food_cost",0))>0,int(data.get("ore_cost",0))>0,data.has("pit")]
	if row_layout!=next_layout:
		row_layout=next_layout
		for child: Node in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		row_values.clear()
	if data.get("entity")=="settlement":
		stat("LOC_ROWNAME_HOME_ASTARI",occupancy.text,"GFX_Pawn_Standard.png")
		stat("LOC_ROWNAME_HOME_WORKERS",str(data["workers"]),"GFX_Pawn_Worker.png")
		stat("LOC_ROWNAME_HOME_MAXBELIEF","%d / %d"%[data["belief"],data["belief_capacity"]],"GFX_IconBelief.png")
		stat("Wheat",str(data["wheat"]),"GFX_IconWheatRate.png")
		stat("Ore",str(data["ore"]),"GFX_IconMining.png")
		description.text=str(labels.get("LOC_INFO_%s_SETTLEMENT_STATS_DESCRIP"%["FARM" if data["role"]=="farmer" else "MINE"],"")) if data["role"]!="builder" else str(labels.get("LOC_INFO_SETTLEMENT_STATS_DESCRIP",""))
	elif data.get("kind","") in ["farm","mine"]:
		var prefix := "FARM" if data["kind"]=="farm" else "MINE"
		stat("LOC_ROWNAME_%s_WORKERS"%prefix,"%d / %d"%[data["workers"],data["capacity"]],"GFX_Pawn_Farmer.png" if prefix=="FARM" else "GFX_Pawn_Miner.png")
		stat("LOC_ROWNAME_%s_HARVESTSIZE"%prefix,str(data["harvest_size"]))
		stat("LOC_ROWNAME_%s_RESOURCEPERHOUR"%prefix,"%.0f"%(float(data["harvest_per_second"])*3600))
		stat("LOC_ROWNAME_%s_TIMEUNTILFINISHED"%prefix,time_text(float(data["harvest_seconds"])))
		description.text=str(labels.get("LOC_INFO_%s_STATS_DESCRIP"%prefix,""))
	elif data.has("pit"):
		var pit: Dictionary=data["pit"]
		stat("LOC_ROWNAME_PITOFDOOM_SACRIFICED",str(pit["followers"]),"GFX_Pawn_Standard.png")
		stat("LOC_ROWNAME_PITOFDOOM_GEMSGAINED",str(pit["gems"]),"GFX_IconGemsSmall.png")
		stat("LOC_ROWNAME_PITOFDOOM_UNHAPPINESSCAUSED","%d%%"%roundi(float(pit["unhappiness"])*100))
		description.text=str(labels.get(data.get("description_key",""),""))
	elif data.has("radius"):
		stat("LOC_INFO_STATDATA_Radius",str(int(data["radius"])))
		description.text=str(labels.get(data.get("description_key",""),""))
	elif data.get("kind","")=="shrine":
		stat("LOC_ROWNAME_SHRINE_BUILDING",str(labels.get("LOC_INFO_TIME_REPAIRED","Repaired")) if data.get("complete",false) else time_text(float(data["repair_seconds"])))
		stat("Construction","%d%%"%roundi(float(data["progress"])*100))
		stat("LOC_ROWNAME_HOME_WORKERS","%d / %d"%[data["builders_working"],data["build_capacity"]],"GFX_Pawn_Worker.png")
		if data.get("entity")=="temple" and not data.get("started",false):
			if int(data.get("food_cost",0))>0: stat("LOC_ROWNAME_HOME_WHEAT_CONSUMPTION","%d / %d"%[data["wheat"],data["food_cost"]],"GFX_IconWheatRate.png")
			if int(data.get("ore_cost",0))>0: stat("LOC_ROWNAME_HOME_ORE_CONSUMPTION","%d / %d"%[data["ore"],data["ore_cost"]],"GFX_IconMining.png")
		description.text=str(labels.get(data.get("description_key",""),labels.get("LOC_INFO_SHRINE_STATS_DESCRIP","")))
	elif data.get("kind")=="ark":
		stat("LOC_ROWNAME_HOME_ASTARI",occupancy.text,"GFX_Pawn_Standard.png")
		description.text=""
	else:
		stat("LOC_ROWNAME_HOME_ASTARI",occupancy.text,"GFX_Pawn_Standard.png")
		if not data["complete"]:
			stat("Construction","%d%%"%roundi(float(data["progress"])*100))
			stat("LOC_ROWNAME_HOME_WORKERS","%d / %d"%[data["builders_working"],data["build_capacity"]],"GFX_Pawn_Worker.png")
		else:
			stat("LOC_ROWNAME_HOME_TIME_TILL_FULL",str(labels.get("LOC_INFO_TIME_FULL","Full")) if data["full"] else time_text(float(data["next_follower_seconds"])))
			stat("LOC_ROWNAME_HOME_BELIEFPERHOUR","%.0f"%float(data["belief_per_hour"]),"GFX_IconBeliefRate.png")
		stat("LOC_ROWNAME_HOME_MAXBELIEF","%d / %d"%[data["belief"],data["belief_capacity"]],"GFX_IconBeliefCapacity.png")
		description.text=str(labels.get("LOC_INFO_HOUSE_OCCUPANTS_DESCRIP",""))
	layout()
