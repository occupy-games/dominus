extends Node3D
## Camera, terrain and actor views. Decisions arrive only as detached snapshots.

signal pointer_action(cell: Vector2i, point: Vector2, shrine_cover: Dictionary)
signal pointer_moved(cell: Vector2i, point: Vector2)
signal drag_moved(point: Vector2)
signal drag_released
signal double_action(cell: Vector2i)
signal pointer_dragged(cell: Vector2i)
signal pointer_released
signal observer_changed(observation: Dictionary)

const Terrain = preload("res://presentation/world/terrain_view.gd")
const Actors = preload("res://presentation/world/actors.gd")
const OriginalFollower = preload("res://presentation/world/original_follower.gd")
const Style = preload("res://presentation/ui/style.gd")
const Ground = preload("res://presentation/world/exhibit_ground.gd")
var follower_assets: Dictionary = {}
var resolve_worker: Callable
var worker_assets: Dictionary = {}
var sheep_assets: Dictionary = {}
var enemy_assets: Dictionary = {}
var resolve_archer: Callable
var resolve_astari_civilian: Callable
var astari_civilian_assets: Dictionary={}
var resolve_arrow_reaction: Callable
var arrow_reaction_assets: Dictionary = {}
var scenery_assets: Dictionary = {}
var resolve_model: Callable
var prop_nodes: Dictionary = {}
var prop_meshes: Dictionary = {}
var farming_preview: Node3D
var pit_beam: MeshInstance3D
var pit_beam_curve: Array=[]
var pit_beam_time := 0.0
var finger_view := preload("res://presentation/world/finger_view.gd").new()
var meteor_view := preload("res://presentation/world/meteor_view.gd").new()
var finger_preview := false
var animation_speed := 1.0
var terrain := Terrain.new()
var camera := Camera3D.new()
var marker := Sprite3D.new()
var tutorial_plot := Sprite3D.new()
var growth_plot_nodes := {}
var state: Dictionary = {}
var actor_nodes: Dictionary = {}
var home_nodes: Dictionary = {}
var home_badges: Dictionary = {}
var status_textures: Dictionary = {}
var badge_layer := preload("res://presentation/world/home_badges.gd").new()
var building_batches := preload("res://presentation/world/building_batches.gd").new()
var trees := preload("res://presentation/world/scenery_stream.gd").new()
var focus := Vector3.ZERO
var yaw := 0.55
var elevation := 0.83
var zoom := 30.0
var orbiting := false
var panning := false
var layer_drag := false
var drag_height := 0.0
var revision := -1
var tree_revision := -1
var tree_home_count := -1
var vegetation_revision := -1
var animation_time := 0.0
var detail_texture: Texture2D
var last_pointer := Vector2i(-1, -1)
var pointer_screen := Vector2.ZERO
var terrain_region := Rect2i()
var ocean := MeshInstance3D.new()
var bathymetry := PackedByteArray()
var depth_pixels := PackedByteArray()
var depth_texture: ImageTexture
var depth_revision := -1
var depth_preview := false
var terrain_preview := false
var effects_enabled := true
var effects_db := -15.0
var preferences: Dictionary = {}
var tree_index: Dictionary = {}
var tree_templates: Dictionary = {}
var camera_dirty := false
var environment := WorldEnvironment.new()
var light := DirectionalLight3D.new()
var lighting_revision := -1
var resolve_building: Callable
var resolve_unit: Callable
var progression_nodes: Dictionary = {}
var chest_glints := preload("res://presentation/world/chest_glints.gd").new()
var unit_assets: Dictionary = {}
var rock_index: Dictionary = {}
var rock_templates: Dictionary = {}
var rocks := preload("res://presentation/world/scenery_stream.gd").new()
var rock_motion_revision := -1
var rock_revision := -1
var rock_region := Rect2i()
var influence_view := preload("res://presentation/world/influence_view.gd").new()
var observer_projection: Array = []
var observer_settling := 0.0
var observer_pending_end := false
var tutorial_camera_locked := false
var tutorial_zoom_locked := false


func _ready() -> void:
	badge_layer.camera = camera
	badge_layer.records = home_badges
	badge_layer.textures = status_textures
	add_child(badge_layer)
	get_tree().node_added.connect(register_geometry)
	trees.configure(scenery_assets.get("trees",{}),false)
	rocks.configure(scenery_assets.get("rocks",{}),true)
	add_child(influence_view)
	add_child(building_batches)
	add_child(terrain)
	terrain.detail_texture = detail_texture
	add_child(trees)
	add_child(rocks)
	add_child(chest_glints)
	add_child(finger_view)
	finger_view.hide()
	add_child(meteor_view)
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ocean.mesh = plane
	ocean.position.y = 0.06
	ocean.material_override = Ground.material(true).duplicate()
	add_child(ocean)
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("80b6be")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("fff2dc")
	settings.ambient_light_energy = 0.25
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_color = Color("fff0d1")
	light.light_energy = 0.65
	light.shadow_enabled = false
	add_child(light)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.current = true
	add_child(camera)
	marker.texture = load("res://assets/extracted/sprites/plotTexture.png")
	marker.pixel_size = 1.0 / marker.texture.get_width()
	marker.rotation.x = -PI / 2
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	add_child(marker)
	tutorial_plot.texture = marker.texture
	tutorial_plot.pixel_size = marker.pixel_size
	tutorial_plot.rotation.x = marker.rotation.x
	tutorial_plot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tutorial_plot.modulate.a = 0.45
	tutorial_plot.hide()
	add_child(tutorial_plot)
	update_camera()


func apply_snapshot(snapshot: Dictionary) -> void:
	var first := state.is_empty()
	var trees_changed := first or not is_same(state.get("trees"),snapshot.get("trees"))
	state = snapshot
	var plot: Dictionary=state.get("opening",{}).get("selected_plot",state.get("leash_lesson",{}).get("plot",{}))
	tutorial_plot.visible=not plot.is_empty()
	if tutorial_plot.visible:
		tutorial_plot.position=world_position(plot["x"],plot["z"])+Vector3(0,0.035,0)
		tutorial_plot.scale=Vector3(plot["size"],plot["size"],1)
	update_growth_plots(state.get("opening",{}).get("growth_plots",[]))
	tutorial_camera_locked=state.has("leash_lesson") or state.get("opening",{}).get("camera_locked",false)
	tutorial_zoom_locked=state.has("leash_lesson") or state.get("opening",{}).get("zoom_locked",false)
	if tutorial_camera_locked:
		orbiting=false
		panning=false
	if trees_changed:
		tree_index.clear()
		for tree: Dictionary in state["trees"]: tree_index[int(tree.get("cell",int(tree["z"])*int(state["width"])+int(tree["x"])))]=tree
	terrain.apply_land_effects(state)
	terrain.apply_blight(state)
	terrain.apply_voyage(state)
	meteor_view.apply_snapshot(state)
	apply_source_lighting()
	if first and state.has("camera_start"):
		if state.get("weyworld",{}).has("camera_degrees"): yaw=deg_to_rad(float(state["weyworld"]["camera_degrees"]))
		var center := (int(state["width"])-1)*0.5
		focus = Vector3(state["camera_start"]["x"]-center,0,state["camera_start"]["z"]-center)
		zoom = 30
		(ocean.mesh as PlaneMesh).size = Vector2.ONE*(state["width"]*10)
		camera.far = 20000
		update_camera(false)
	var region_changed := refresh_region()
	if region_changed: tree_revision = -1
	var terrain_changed := revision != int(state["terrain_revision"])
	if terrain_changed or region_changed:
		revision = int(state["terrain_revision"])
		terrain.rebuild(state)
		terrain_preview=false
	var next_depth_revision:=int(state.get("opening",{}).get("bathymetry_revision",0))
	if not bathymetry.is_empty() and (terrain_changed or depth_revision!=next_depth_revision):
		depth_revision=next_depth_revision
		update_water_field()
	if not layer_drag: clear_preview()
	if trees_changed or state.has("tree_response") or tree_revision != revision or tree_home_count != state["homes"].size() or vegetation_revision!=int(state.get("vegetation_revision",0)):
		tree_revision = revision
		tree_home_count = state["homes"].size()
		vegetation_revision=int(state.get("vegetation_revision",0))
		update_trees()
	var live_actors: Dictionary={}
	var raid_rules: Dictionary=state.get("opening",{}).get("definition",{}).get("astari_raids",{})
	var village_rules: Dictionary=state.get("opening",{}).get("definition",{}).get("astari_village",{})
	var village: Dictionary=state.get("astari_village",{})
	var groups: Dictionary={"followers":state["followers"],"sheep":state.get("sheep",[]),"enemies":state.get("enemies",[]),
		"casualties":state.get("casualties",[]),"astari":village.get("performers",[])}
	for key: String in groups:
		for agent: Dictionary in groups[key]:
			var id: int = agent["id"]
			live_actors[id]=true
			var profession: String = agent.get("profession","") if key in ["followers","casualties"] else ""
			var arrow_reaction:=agent.has("arrow_animation")
			var civilian: bool=key!="enemies" and agent.get("race")=="Astari" and not village_rules.is_empty()
			if actor_nodes.has(id) and (actor_nodes[id].get_meta("profession","")!=profession or actor_nodes[id].get_meta("arrow_reaction",false)!=arrow_reaction):
				actor_nodes[id].queue_free()
				actor_nodes.erase(id)
			if not actor_nodes.has(id):
				var actor: Node3D
				var source_assets: Dictionary = sheep_assets if key=="sheep" else follower_assets
				if not profession.is_empty() and resolve_worker.is_valid():
					if not worker_assets.has(profession): worker_assets[profession]=resolve_worker.call(profession)
					source_assets=worker_assets[profession]
				if key=="enemies":
					var kind: String=agent.get("kind","champion")
					if kind=="astari_archer" and not enemy_assets.has(kind) and resolve_archer.is_valid():
						enemy_assets[kind]=resolve_archer.call(raid_rules)
					source_assets=enemy_assets.get(kind,{})
				elif civilian and resolve_astari_civilian.is_valid():
					if not astari_civilian_assets.has(profession):
						astari_civilian_assets[profession]=resolve_astari_civilian.call(source_assets,village_rules)
					source_assets=astari_civilian_assets[profession]
				if arrow_reaction and resolve_arrow_reaction.is_valid():
					var cache_key: Array=[profession,civilian]
					if not arrow_reaction_assets.has(cache_key):
						arrow_reaction_assets[cache_key]=resolve_arrow_reaction.call(source_assets,raid_rules)
					var recovered: Dictionary=arrow_reaction_assets[cache_key]
					if not recovered.is_empty(): source_assets=recovered
				if not source_assets.is_empty():
					var human := OriginalFollower.new()
					human.assets = source_assets
					human.variant = (1 if agent["female"] else 0) if agent.has("female") else id
					human.visual_scale = 0.005 if key == "sheep" else 0.003
					actor = human
				else:
					actor = Node3D.new() # Unsupported content stays unrendered.
				actor.position = world_position(agent["x"], agent["z"])
				actor.rotation_degrees.y=float(agent.get("rotation",0.0))
				add_child(actor)
				actor_nodes[id] = actor
				actor.set_meta("profession",profession)
				actor.set_meta("arrow_reaction",arrow_reaction)
			actor_nodes[id].set_meta("data", agent)
			actor_nodes[id].visible=agent["state"]!="indoors"
			if actor_nodes[id] is OriginalFollower:
				actor_nodes[id].scale=Vector3.ONE*actor_nodes[id].visual_scale*float(agent.get("scale",1))
				var role: String=agent.get("arrow_animation",agent["state"])
				var elapsed: float=agent.get("arrow_elapsed",agent.get("sacrifice_elapsed",-1))
				if agent.has("swamp_entered"):
					role="swamp_struggle"
					elapsed=float(int(state["tick"])-int(agent["swamp_entered"]))*0.1
				elif agent.has("swamp_animation"):
					role=agent["swamp_animation"]
					elapsed=agent["swamp_elapsed"]
				var stage: int=agent.get("shot_stage",0)
				var starting_clip: bool=elapsed>=0 and actor_nodes[id].animation_state!=role
				actor_nodes[id].animation_state = role
				actor_nodes[id].looped=elapsed<0 and stage in [-1,0,3]
				if starting_clip:
					actor_nodes[id].apply_animation(0.0)
					actor_nodes[id].clip_time=elapsed
					actor_nodes[id].apply_animation(0.0)
				actor_nodes[id].playback_speed = animation_speed*float(raid_rules["stats"]["AnimSpeedMult"] if stage>0 else 1.0)
				actor_nodes[id].set_process(is_processing())
				if actor_nodes[id].cue_audio != null:
					actor_nodes[id].cue_audio.set_effects_enabled(effects_enabled)
					actor_nodes[id].cue_audio.set_effects_volume(effects_db)
	var visible_homes: Array=state["homes"]+village.get("homes",[])
	var live_homes: Dictionary={}
	for home: Dictionary in visible_homes:
		if home.get("settlement_core",false): continue
		var id: int = home["id"]
		live_homes[id]=true
		if home_nodes.has(id) and home_nodes[id].get_meta("model_id","")!=home.get("model_id",""):
			home_nodes[id].queue_free()
			home_nodes.erase(id)
		if not home_nodes.has(id):
			var building: Node3D
			var assembled: Dictionary = resolve_building.call(home["model_id"]) if home.has("model_id") and resolve_building.is_valid() else {}
			if not assembled.is_empty():
				if home.get("kind","")=="farm": assembled["crop_shader"]=true
				building=preload("res://presentation/world/assembled_building.gd").new()
				building.data=assembled
				building.scale=Vector3.ONE*0.003
			elif home.get("kind","") in ["shrine","ark"] or home.get("village_structure",false): building=Node3D.new()
			else: building=Actors.home(scenery_assets.get("tents", {}), Style.source_font())
			building.set_meta("model_id",home.get("model_id",""))
			add_child(building)
			home_nodes[id] = building
		var node: Node3D = home_nodes[id]
		var offset := (float(home.get("span",2))-1)*0.5
		node.position = world_position(home.get("anchor_x",home["x"]+offset),home.get("anchor_z",home["z"]+offset))
		if home.get("kind","")=="shrine":
			for site: Dictionary in state.get("progression",{}).get("shrines",[]):
				if site["id"]==home.get("shrine_id",""):
					node.position=temple_position(site)
					break
		node.rotation_degrees.y=float(home.get("rotation",0))
		if not node.has_method("set_stage") and not node.has_node("Indicator"): continue
		var build_ticks: int = home.get("build_ticks",state.get("build_ticks", 60))
		var complete: bool = home["progress"] >= build_ticks
		if home.get("allegiance",0)==0: update_home_badge(home, node, complete)
		if node.has_method("set_stage"):
			node.visible=not complete
			var parts := floori(node.maximum_part()*float(home["progress"])/build_ticks)
			node.set_stage(maxi(1,parts) if home.get("kind","")=="shrine" else parts,complete)
			continue
		if node.has_node("Building/Complete"):
			node.get_node("Building/Complete").visible = complete
		if node.has_node("Building/Scaffolds"):
			node.get_node("Building/Scaffolds").visible = not complete
		var label: Label3D = node.get_node("Indicator")
		label.visible = not state.has("campaign")
		label.text = ("+%d" % home["stored"]) if complete and home["stored"] > 0 else ("" if complete else ("Path blocked" if home["stalled"] else "%d%%" % int(home["progress"] / float(build_ticks) * 100)))
	var building_state:=state.duplicate(false)
	building_state["homes"]=visible_homes
	building_batches.update(building_state,home_nodes)
	for id: int in home_nodes.keys():
		if not live_homes.has(id):
			home_nodes[id].queue_free()
			home_nodes.erase(id)
			home_badges.erase(id)
	for id: int in actor_nodes.keys():
		if not live_actors.has(id): actor_nodes[id].queue_free(); actor_nodes.erase(id)
	if state.has("progression"):
		update_progression()
		var next_motion := int(state.get("rock_motion",{}).get("revision",0))
		if rock_region!=terrain_region or rock_revision!=int(state["progression"]["rock_revision"]) or rock_motion_revision!=next_motion:
			rock_region=terrain_region
			rock_revision=int(state["progression"]["rock_revision"])
			rock_motion_revision=next_motion
			update_rocks()
	for prop: Dictionary in state.get("props", []):
		var id: int = prop["id"]
		if not prop_nodes.has(id) and resolve_model.is_valid():
			var model_id: String = prop["model_id"]
			var assembled: Dictionary = resolve_building.call(model_id) if resolve_building.is_valid() else {}
			var node: Node3D
			if prop.has("clip") and resolve_unit.is_valid():
				var assets: Dictionary = resolve_unit.call(model_id)
				if assets.is_empty(): continue
				assets["source"]=model_id
				node=Node3D.new()
				var animated := OriginalFollower.new()
				animated.assets=assets
				animated.animation_state=prop["clip"]
				animated.visual_scale=1.0
				animated.rotation.y=PI # Cancel follower-facing adjustment for props.
				node.add_child(animated)
			elif not assembled.is_empty():
				node=preload("res://presentation/world/assembled_building.gd").new()
				node.data=assembled
			else:
				if not prop_meshes.has(model_id):
					var data: Dictionary = resolve_model.call(model_id)
					if data.is_empty(): continue
					prop_meshes[model_id] = Actors.mesh(data)
				node=prop_meshes[model_id].duplicate()
			node.scale = Vector3.ONE * 0.003
			add_child(node)
			prop_nodes[id] = node
		if prop_nodes.has(id):
			var x:=float(prop["x"])
			if prop.get("kind")=="fountain": x+=0.5
			prop_nodes[id].position = world_position(x, prop["z"])
			if prop.get("water",false): prop_nodes[id].position.y=0.0
			prop_nodes[id].rotation.y = deg_to_rad(float(prop["degrees"])) if prop.has("degrees") else int(prop["turns"]) * PI / 2
	var existing_props := {}
	for prop: Dictionary in state.get("props",[]): existing_props[int(prop["id"])]=true
	for id: int in prop_nodes.keys():
		if existing_props.has(id): continue
		prop_nodes[id].queue_free()
		prop_nodes.erase(id)
		home_badges.erase(id)
	for settlement: Dictionary in state.get("progression",{}).get("settlements",[]):
		var id := int(settlement["id"])
		if not prop_nodes.has(id): continue
		var sprite: String = {"builder":"GFX_Pawn_Worker.png","farmer":"GFX_Pawn_Farmer.png","miner":"GFX_Pawn_Miner.png"}[settlement["role"]]
		if int(settlement["wheat"])>0: sprite="GFX_IWIcon_Wheat.png"
		elif int(settlement["ore"])>0: sprite="GFX_IWIcon_Mining.png"
		var ready := true
		if settlement["role"]=="builder" and state.has("opening"):
			ready=false
			for home: Dictionary in state["homes"]:
				if not home["id"] in settlement["members"]: continue
				if home["stored"]>=home.get("min_belief",1): sprite="GFX_IWIcon_Belief.png"
				ready=sprite=="GFX_IWIcon_Belief.png" or home["id"] in state["opening"].get("sprog_homes",[])
				break
		var in_range: bool = not state["progression"].get("influence_enabled",false)
		for area: Dictionary in state["progression"].get("influence",[]):
			if Vector2(settlement["x"],settlement["z"]).distance_squared_to(Vector2(area["x"],area["z"]))<=pow(float(area["radius"]),2): in_range=true; break
		home_badges[id]={"position":prop_nodes[id].position+Vector3(0,2,0),"source_sprite":sprite,"visible":in_range and ready,"settlement":true}
	influence_view.apply_snapshot(state,self)
	if state.has("voyage"): update_voyage()
	badge_layer.queue_redraw()


func update_voyage() -> void:
	var voyage: Dictionary = state["voyage"]
	for temple: Dictionary in voyage.get("temples",[]):
		if temple["type"]=="Expedition_Goal": continue
		var key := "voyage_temple:"+str(int(temple["uid"]))
		if not progression_nodes.has(key) and resolve_building.is_valid():
			var group: String = temple.get("model",{"Shrine_LandExp":"shrineexpansion","Shrine_GodPower":"shrinegodpower","Monument_Speed":"shrine","Hubworld_TradingPost":"obelisk"}.get(temple["type"],""))
			if group.is_empty(): continue
			var data: Dictionary = resolve_building.call(group+".group.bin:dff1563f")
			if data.is_empty(): continue
			var node := preload("res://presentation/world/assembled_building.gd").new()
			node.data=data
			node.scale=Vector3.ONE*0.003
			node.rotation_degrees.y=float(temple.get("rotation",0))
			add_child(node)
			progression_nodes[key]=node
			if temple.get("symbol","")=="speed" and resolve_model.is_valid():
				var symbol: Dictionary = resolve_model.call("symbols.group.bin:105f2796")
				if not symbol.is_empty(): node.add_child(Actors.mesh(symbol))
		if progression_nodes.has(key):
			var node: Node3D = progression_nodes[key]
			node.position=world_position(temple["x"],temple["z"])
			node.visible=not temple.get("deconstructed",false)
			var fraction := float(temple.get("progress",0))/maxf(0.1,float(temple.get("build_seconds",0)))
			node.set_stage(maxi(1,ceili(node.maximum_part()*fraction)),temple["complete"])
	for chest: Dictionary in voyage.get("chests",[]):
		var key := "voyage_chest:"+str(int(chest["id"]))
		if chest["opened"]:
			if progression_nodes.has(key): progression_nodes[key].queue_free(); progression_nodes.erase(key)
			continue
		if not progression_nodes.has(key) and resolve_unit.is_valid():
			var id: String = "chest.group.bin:"+{"treasure1":"f844d7b4","treasure2":"002572ae"}.get(chest["type"],"f844d7b4")
			if not unit_assets.has(id): unit_assets[id]=resolve_unit.call(id)
			if unit_assets[id].is_empty(): continue
			var actor := OriginalFollower.new()
			actor.assets=unit_assets[id]
			actor.visual_scale=0.003
			actor.animation_state="chest_stuck"
			actor.position=world_position(chest["x"],chest["z"])
			actor.position.y=float(chest["height"])*Terrain.STEP
			add_child(actor)
			progression_nodes[key]=actor
		if progression_nodes.has(key): progression_nodes[key].animation_state="chest_freed" if height_at(chest["x"],chest["z"])<=chest["height"] else "chest_stuck"


func update_growth_plots(plots: Array) -> void:
	var visible_ids := {}
	for plot: Dictionary in plots:
		var id := int(plot["id"])
		visible_ids[id]=true
		if not growth_plot_nodes.has(id):
			var sprite: Sprite3D=tutorial_plot.duplicate()
			add_child(sprite)
			growth_plot_nodes[id]=sprite
		var sprite: Sprite3D=growth_plot_nodes[id]
		var half := float(plot["size"])*0.5
		sprite.position=world_position(plot["x"]+half,plot["z"]+half)+Vector3(0,0.035,0)
		sprite.scale=Vector3(plot["size"],plot["size"],1)
		sprite.show()
	for id: int in growth_plot_nodes.keys():
		if visible_ids.has(id): continue
		growth_plot_nodes[id].queue_free()
		growth_plot_nodes.erase(id)


func update_home_badge(home: Dictionary, building: Node3D, complete: bool) -> void:
	if not state.has("campaign") or status_textures.is_empty() or home.get("kind","")=="ark": return
	var id: int = home["id"]
	var badge := {}
	var ready: bool = complete and int(home["stored"]) > 0 and int(home["stored"]) >= int(home.get("min_belief", 0))
	var name_ := "GFX_IWIcon_Belief.png" if ready else "GFX_Pawn_Worker.png"
	var harvest_ready: bool = (home.has("awaiting_influence") or home.get("direct_harvest",false)) and home["harvest_accumulator"] >= home["max_belief"]
	if home.get("kind","")=="farm":
		name_="GFX_IWIcon_Wheat.png" if harvest_ready else "GFX_Pawn_Farmer.png"
	elif home.get("kind","")=="mine":
		name_="GFX_IWIcon_Mining.png" if harvest_ready else "GFX_Pawn_Miner.png"
	var height := 1.0
	if building.has_method("set_stage"): height = maxf(height, building.source_bounds.end.y * building.scale.y)
	badge["position"] = building.position + Vector3(0, height + 0.4, 0)
	badge["source_sprite"] = name_
	badge["visible"] = true
	if state.get("opening",{}).get("promised_step")==5 and id==state["homes"][0]["id"]: badge["opacity"]=0.45
	var p: Dictionary = state.get("progression", {})
	if p.get("influence_enabled", false):
		badge["visible"] = false
		for area: Dictionary in p.get("influence", []):
			if Vector2(home["x"], home["z"]).distance_squared_to(Vector2(area["x"], area["z"])) <= pow(float(area["radius"]), 2):
				badge["visible"] = true
				break
	home_badges[id] = badge


func _exit_tree() -> void:
	for mesh: Node in prop_meshes.values():
		mesh.free()


func update_trees() -> void:
	trees.update(state,terrain_region)
	# Kept as a public cache reference for the asset/streaming checks.
	tree_templates=trees.templates


func preview_edits(edits: Array) -> void:
	var heights: Variant=state["terrain"]
	if heights is Array: heights=heights.duplicate()
	var land_changed:=false
	for edit: Dictionary in edits:
		if heights[edit["cell"]]!=edit["height"]:
			heights[edit["cell"]]=edit["height"]
			land_changed=true
	if land_changed:
		var draft:=state.duplicate(false)
		draft["terrain"]=heights
		terrain.rebuild(draft,true)
	elif terrain_preview: terrain.rebuild(state,true)
	terrain_preview=land_changed
	if not depth_pixels.is_empty():
		var pixels:=depth_pixels.duplicate()
		for edit: Dictionary in edits:
			pixels[edit["cell"]]=int(edit.get("raw_height",int(edit["height"])+19))
		show_water_field(pixels)
		depth_preview=true


func cancel_preview() -> void:
	layer_drag = false
	clear_preview()


func clear_preview() -> void:
	if terrain_preview: terrain.rebuild(state,true)
	if depth_preview: show_water_field(depth_pixels)
	terrain_preview=false
	depth_preview=false


func update_water_field() -> void:
	var width: int = state["width"]
	depth_pixels=bathymetry.duplicate()
	var submerged: Dictionary=state.get("opening",{}).get("submerged_levels",{})
	for key: String in submerged:
		var index:=int(key)
		var height:=int(state["terrain"][index])
		depth_pixels[index]=mini(255,height+19) if height>0 else int(submerged[key])
	for z in range(terrain_region.position.y,terrain_region.end.y):
		for x in range(terrain_region.position.x,terrain_region.end.x):
			var index := z*width+x
			if state["terrain"][index] > 0: depth_pixels[index]=mini(255,int(state["terrain"][index])+19)
	show_water_field(depth_pixels)
	depth_preview=false


func show_water_field(pixels: PackedByteArray) -> void:
	var width: int=state["width"]
	var image := Image.create_from_data(width,width,false,Image.FORMAT_R8,pixels)
	if depth_texture==null or depth_texture.get_width()!=width:
		depth_texture=ImageTexture.create_from_image(image)
		var material:=ocean.material_override as ShaderMaterial
		material.set_shader_parameter("use_terrain_depth",true)
		material.set_shader_parameter("terrain_width",float(width))
		material.set_shader_parameter("terrain_field",depth_texture)
	else: depth_texture.update(image)


func height_at(x: float, z: float) -> int:
	var width: int = state.get("width", 0)
	var ix := clampi(roundi(x), 0, maxi(width - 1, 0))
	var iz := clampi(roundi(z), 0, maxi(width - 1, 0))
	return int(state["terrain"][iz * width + ix]) if width > 0 else 0


func play_pit_beam(id: String) -> void:
	var effect: Dictionary=state.get("opening",{}).get("definition",{}).get("pit_beam",{})
	if effect.is_empty() or not resolve_model.is_valid(): return
	if not is_instance_valid(pit_beam):
		var data: Dictionary=resolve_model.call(effect["model"])
		var texture: Texture2D=load("res://assets/extracted/"+effect["texture"])
		if data.is_empty() or texture==null: return
		pit_beam=Actors.mesh(data)
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		material.albedo_texture=texture
		pit_beam.material_override=material
		pit_beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pit_beam.scale=Vector3.ONE*float(effect["scale"])
		add_child(pit_beam)
	for site: Dictionary in state["progression"]["shrines"]:
		if site["id"]!=id: continue
		pit_beam.position=temple_position(site)+Vector3.UP*float(effect["height_offset"])
		pit_beam_curve=effect["curve"]
		pit_beam_time=0.0
		pit_beam.show()
		advance_pit_beam(0.0)
		return


func advance_pit_beam(delta: float) -> void:
	if not is_instance_valid(pit_beam) or not pit_beam.visible: return
	pit_beam_time+=delta*animation_speed
	for index in range(1,pit_beam_curve.size()):
		var point: Array=pit_beam_curve[index]
		if pit_beam_time>point[0]: continue
		var previous: Array=pit_beam_curve[index-1]
		var alpha:=lerpf(previous[1],point[1],inverse_lerp(previous[0],point[0],pit_beam_time))
		pit_beam.material_override.albedo_color=Color(1.0,160.0/255.0,0.0,alpha)
		return
	pit_beam.hide()


func show_farming_preview(point: Vector2,models: Array) -> void:
	if models.is_empty():
		if is_instance_valid(farming_preview): farming_preview.hide()
		return
	if is_instance_valid(farming_preview) and farming_preview.get_meta("model_ids")!=models:
		farming_preview.hide()
		farming_preview.queue_free()
		farming_preview=null
	if not is_instance_valid(farming_preview):
		if not resolve_model.is_valid(): return
		farming_preview=Node3D.new()
		farming_preview.set_meta("model_ids",models.duplicate())
		farming_preview.scale=Vector3.ONE*0.003
		for id: String in models:
			var data: Dictionary=resolve_model.call(id)
			if data.is_empty(): continue
			var mesh:=Actors.mesh(data)
			var material: StandardMaterial3D=mesh.material_override
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a=0.55
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			farming_preview.add_child(mesh)
		add_child(farming_preview)
	farming_preview.position=world_position(point.x,point.y)
	farming_preview.show()


func world_position(x: float, z: float) -> Vector3:
	var center := (int(state["width"]) - 1) * 0.5
	return Vector3(x - center, height_at(x, z) * Terrain.STEP, z - center)


func home_at(x: float, z: float) -> int:
	var temple := -1
	for home: Dictionary in state.get("homes",[])+state.get("astari_village",{}).get("homes",[]):
		if home.get("kind","")=="village": continue
		if x >= home["x"] - 0.5 and x < home["x"] + float(home.get("span",2))-0.5 and z >= home["z"] - 0.5 and z < home["z"] + float(home.get("span",2))-0.5:
			if home.get("kind","")=="shrine": temple=int(home["id"])
			else: return int(home["id"])
	return temple


func pick(screen: Vector2, plane_height: Variant = null) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var center := (int(state["width"]) - 1) * 0.5
	if plane_height != null:
		var hit := origin + ray * ((float(plane_height) - origin.y) / ray.y)
		return Vector2(hit.x + center, hit.z + center)
	for level in range(63 if state.has("campaign") else 7, -1, -1):
		var hit := origin + ray * ((level * Terrain.STEP - origin.y) / ray.y)
		var point := Vector2(hit.x + center, hit.z + center)
		if point.x >= 0 and point.y >= 0 and point.x < state["width"] and point.y < state["width"] and height_at(point.x, point.y) == level:
			return point
	return Vector2(-1, -1)


func pick_shrine_cover(screen: Vector2,ground: Vector2) -> Dictionary:
	# The ground projection can hit a shrine through the roof or canopy above it.
	if visible_temple_at(ground).is_empty(): return {}
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var closest := origin.distance_to(world_position(ground.x,ground.y))
	var picked := pick_home_mesh(origin,direction,closest)
	var tree_cell: int=trees.pick_tree(origin,direction,float(picked.get("distance",closest)))
	if tree_cell>=0: return {"tree_cell":tree_cell}
	return picked


func finger_point(ground: Vector2) -> Vector2:
	if ground.x<0: return ground
	var origin := camera.project_ray_origin(pointer_screen)
	var direction := camera.project_ray_normal(pointer_screen)
	var closest := origin.distance_to(world_position(ground.x,ground.y))
	var home := pick_home_mesh(origin,direction,closest)
	var tree_cell: int=trees.pick_tree(origin,direction,float(home.get("distance",closest)))
	if tree_cell>=0 and tree_index.has(tree_cell):
		var tree: Dictionary=tree_index[tree_cell]
		return Vector2(tree["x"],tree["z"])
	return home.get("point",ground)


func pick_home_mesh(origin: Vector3,direction: Vector3,closest: float=INF) -> Dictionary:
	var picked := {}
	for home: Dictionary in state["homes"]+state.get("astari_village",{}).get("homes",[]):
		if home.get("kind","")=="shrine" or not home_nodes.has(int(home["id"])): continue
		var node: Node3D=home_nodes[int(home["id"])]
		var assembly: Node3D=node.get_node_or_null("Building") if not node.has_method("set_stage") else node
		if assembly==null: continue
		for child: Node in assembly.get_children():
			var mesh := child as MeshInstance3D
			if mesh==null or mesh.mesh==null or not mesh.visible or "shadow" in str(mesh.get_meta("role","")): continue
			var inverse := mesh.global_transform.affine_inverse()
			var hit: Variant=mesh.mesh.get_aabb().intersects_ray(inverse*origin,inverse.basis*direction)
			if hit==null: continue
			var distance := origin.distance_to(mesh.global_transform*hit)
			if distance>=closest: continue
			closest=distance
			var offset := (float(home.get("span",2))-1)*0.5
			picked={"home_id":int(home["id"]),"point":Vector2(home["x"]+offset,home["z"]+offset),"distance":distance}
	return picked


func set_marker(cell: Vector2i, valid: bool, span: float = 1.0) -> void:
	marker.visible = cell.x >= 0 and (valid or not state.has("progression"))
	if not marker.visible:
		return
	marker.position = world_position(cell.x, cell.y) + Vector3(0, 0.08, 0)
	marker.scale = Vector3(span, span, 1)
	marker.modulate.a = 1.0 if valid else 0.4


func update_camera(refresh: bool = true) -> void:
	camera.size = zoom
	camera.position = focus + Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * maxf(maxf(45,zoom*1.5),24/sin(elevation))
	camera.look_at(focus)
	badge_layer.queue_redraw()
	if refresh: camera_dirty = true
	if refresh and state.has("opening"):
		observer_settling=0.15
		observer_pending_end=true


func camera_observation(ended: bool = false) -> Dictionary:
	# The game camera is orthographic. Eight numbers map logical x/z and terrain
	# height to normalized screen coordinates; simulation needs no Camera3D.
	var size := get_viewport().get_visible_rect().size
	var center := (int(state["width"])-1)*0.5
	var origin := Vector3(-center,0,-center)
	var base := camera.unproject_position(origin)/size
	var x := camera.unproject_position(origin+Vector3.RIGHT)/size-base
	var z := camera.unproject_position(origin+Vector3.BACK)/size-base
	var height := camera.unproject_position(origin+Vector3.UP)/size-base
	var ground:=(Vector2(focus.x,focus.z)+Vector2.ONE*center).clamp(Vector2.ZERO,Vector2.ONE*float(state["width"]-1))
	return {"type":"campaign_view","projection":[x.x,z.x,height.x,base.x,x.y,z.y,height.y,base.y],"center":[ground.x,ground.y],"ended":ended}


func apply_campaign_camera(event: Dictionary) -> void:
	if event.get("action")=="SetCamera":
		var center := (int(state["width"])-1)*0.5
		focus.x=float(event["args"][0])-center
		focus.z=float(event["args"][1])-center
		update_camera()
	# Locks also live in snapshots so loading does not depend on past events.


func refresh_region() -> bool:
	var minimum := Vector2.INF
	var maximum := -Vector2.INF
	var viewport_size := get_viewport().get_visible_rect().size
	for corner: Vector2 in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
		for height: float in [0.0,19.2]:
			var point := pick(corner,height)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	var tile := Terrain.TILE
	var origin := Vector2i(floori((minimum.x-8)/tile)*tile,floori((minimum.y-8)/tile)*tile)
	var end := Vector2i(ceili((maximum.x+8)/tile)*tile,ceili((maximum.y+8)/tile)*tile)
	var next := Rect2i(origin,end-origin)
	next = next.intersection(Rect2i(0,0,state["width"]-1,state["width"]-1))
	if int(state["width"]) <= 64: next = Rect2i(0,0,state["width"]-1,state["width"]-1)
	if next == terrain_region: return false
	terrain_region = next
	terrain.view_region = next
	return true


func zoom_by(factor: float, screen: Vector2 = Vector2(-1, -1)) -> void:
	if state.is_empty() or tutorial_zoom_locked: return
	var anchored := screen.x >= 0
	var before := pick(screen, 0) if anchored else Vector2.ZERO
	zoom = clampf(zoom * factor, 0.6, float(state["width"]) * 2.5)
	update_camera()
	if anchored:
		var after := pick(screen, 0)
		focus += Vector3(before.x - after.x, 0, before.y - after.y)
		update_camera()


func trackpad_pan(delta: Vector2, change_angle: bool) -> void:
	if tutorial_camera_locked: return
	if change_angle:
		yaw -= delta.x * 0.004*float(preferences.get("camera.orbit_speed",1))
		elevation = clampf(elevation - delta.y * 0.003*float(preferences.get("camera.orbit_speed",1)), 0.12, 1.52)
	else:
		var middle := get_viewport().get_visible_rect().size * 0.5
		var before := pick(middle, 0)
		var after := pick(middle + Vector2(delta.x if preferences.get("camera.reverse_horizontal",true) else -delta.x,delta.y)*float(preferences.get("camera.pan_speed",1)), 0)
		focus += Vector3(after.x - before.x, 0, after.y - before.y)
	update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if state.is_empty():
		return
	if event is InputEventMagnifyGesture:
		zoom_by(pow(maxf(event.factor, 0.01), -float(preferences.get("camera.pinch_sensitivity",0.1))), event.position)
		get_viewport().set_input_as_handled()
	if event is InputEventPanGesture:
		trackpad_pan(event.delta, event.shift_pressed)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		pointer_screen = event.position
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed and not event.shift_pressed and not tutorial_camera_locked
			panning = event.pressed and event.shift_pressed and not tutorial_camera_locked
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed and not tutorial_camera_locked
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(pow(0.82, event.factor * (float(preferences.get("camera.wheel_sensitivity",0.1)) if event.button_index == MOUSE_BUTTON_WHEEL_UP else -float(preferences.get("camera.wheel_sensitivity",0.1)))), event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var point := pick(event.position)
				var target := pick_shrine_cover(event.position,point)
				var ready: Array=state.get("opening",{}).get("sprog_homes",[])
				for id: int in home_badges:
					if not badge_layer.hit(event.position,id): continue
					var badge: Dictionary=home_badges[id]
					var collect: bool=badge.get("source_sprite") in ["GFX_IWIcon_Belief.png","GFX_IWIcon_Wheat.png","GFX_IWIcon_Mining.png"]
					if badge.get("settlement",false):
						target={"settlement_collect" if collect else "settlement_worker":id}
						break
					if collect:
						target={"belief_home":id}
						break
					if id in ready:
						target={"sprog_home":id}
						break
				var cell := Vector2i(roundi(point.x),roundi(point.y))
				if event.double_click and not state.has("leash_lesson") and target.is_empty() and progression_at(point).is_empty() and visible_temple_at(point).is_empty():
					double_action.emit(cell)
				else: pointer_action.emit(cell,point,target)
			else:
				if layer_drag: drag_released.emit()
				pointer_released.emit()
	if event is InputEventMouseMotion:
		pointer_screen = event.position
		if orbiting and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.006*float(preferences.get("camera.orbit_speed",1))
			elevation = clampf(elevation + event.relative.y * 0.004*float(preferences.get("camera.orbit_speed",1)), 0.4, 1.2)
			update_camera()
		elif panning and event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			var before := pick(event.position - event.relative, 0)
			var after := pick(event.position, 0)
			focus += Vector3(before.x - after.x, 0, before.y - after.y)
			update_camera()
		elif layer_drag:
			drag_moved.emit(pick(event.position, drag_height))
		else:
			var point := pick(event.position)
			var cell := Vector2i(roundi(point.x), roundi(point.y))
			if cell != last_pointer:
				last_pointer = cell
				pointer_moved.emit(cell, point)
				if event.button_mask & MOUSE_BUTTON_MASK_LEFT: pointer_dragged.emit(cell)


func _process(delta: float) -> void:
	animation_time += delta
	advance_pit_beam(delta)
	if state.is_empty():
		return
	meteor_view.advance(delta*animation_speed,camera)
	if state.has("opening"):
		var observation := camera_observation()
		if observation["projection"]!=observer_projection:
			observer_projection=observation["projection"].duplicate()
			observer_changed.emit(observation)
		if observer_pending_end:
			observer_settling-=delta
			if observer_settling<=0 and not panning and not orbiting:
				observer_pending_end=false
				observer_changed.emit(camera_observation(true))
	if camera_dirty:
		camera_dirty = false
		trees.set_pixel_density(get_viewport().get_visible_rect().size.y/zoom)
		rocks.set_pixel_density(get_viewport().get_visible_rect().size.y/zoom)
		var changed_lod: bool=trees.next_lod!=trees.lod or rocks.next_lod!=rocks.lod
		var detail := 1 if zoom > 100 else 4
		var stride := 8 if zoom>800 else (4 if zoom>400 else (2 if zoom>200 else 1))
		var changed_detail := terrain.bevel_segments != detail or terrain.sample_stride!=stride
		terrain.sample_stride=stride
		terrain.bevel_segments = detail
		if refresh_region() or changed_detail or changed_lod:
			terrain.rebuild(state)
			update_trees()
			if state.has("progression"):
				update_rocks()
				update_progression()
	chest_glints.advance(delta*animation_speed,camera)
	if finger_preview:
		var opening: Dictionary=state.get("opening",{})
		finger_view.advance(delta*animation_speed,opening.get("finger_cast",{}),opening.get("definition",{}).get("finger_of_god",{}),
			pick(pointer_screen),self)
	elif finger_view.visible:
		finger_view.hide()
		finger_view.stroke.clear()
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction.y -= 1
	if Input.is_physical_key_pressed(KEY_S): direction.y += 1
	if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D): direction.x += 1
	if direction != Vector2.ZERO and not tutorial_camera_locked:
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		focus += (right * direction.x + forward * direction.y) * delta * zoom * 0.35*float(preferences.get("camera.keyboard_speed",1))
		var bound := float(state["width"])*0.5
		focus.x = clampf(focus.x, -bound, bound)
		focus.z = clampf(focus.z, -bound, bound)
		update_camera()
	for actor: Node3D in actor_nodes.values():
		var data: Dictionary = actor.get_meta("data")
		if actor is OriginalFollower:
			var archer: bool=data.get("kind")=="astari_archer"
			var definition: Dictionary=state.get("opening",{}).get("definition",{})
			var speed: float=1.0
			if archer: speed=definition.get("astari_raids",{}).get("stats",{}).get("AnimSpeedMult",1)
			elif data.get("race")=="Astari": speed=definition.get("astari_village",{}).get("actor_stats",{}).get("AnimSpeedMult",1)
			actor.playback_speed = animation_speed*speed
			var pixels := get_viewport().get_visible_rect().size.y/zoom
			actor.animation_interval=0.0 if pixels>50 else (1.0/30 if pixels>15 else (1.0/15 if pixels>4 else 1.0/8))
			if not camera.is_position_in_frustum(actor.position+Vector3(0,0.7,0)): actor.animation_interval=0.5
		var target := world_position(data["x"], data["z"])
		var offset := target - actor.position
		actor.position = actor.position.lerp(target, minf(delta * 14, 1))
		if int(data.get("shot_stage",0))>0:
			actor.rotation.y=lerp_angle(actor.rotation.y,deg_to_rad(float(data["rotation"])),minf(delta*10,1))
		elif data["state"] in ["hugging_give","hugging_take"]:
			for partner: Dictionary in state["followers"]:
				if partner["id"]==data["id"] or not partner["state"] in ["hugging_give","hugging_take"]: continue
				var hug_direction := Vector2(float(partner["x"])-float(data["x"]),float(partner["z"])-float(data["z"]))
				if hug_direction.length()>0.01: actor.rotation.y=atan2(-hug_direction.x,-hug_direction.y)
		elif Vector2(offset.x, offset.z).length() > 0.01:
			actor.rotation.y = lerp_angle(actor.rotation.y, atan2(-offset.x, -offset.z), minf(delta * 10, 1))


func temple_at(point: Vector2) -> String:
	var covering := home_at(point.x,point.y)
	for home: Dictionary in state.get("homes",[]):
		if int(home["id"])==covering and home.get("kind","")!="shrine": return ""
	if not progression_at(point).is_empty(): return ""
	return visible_temple_at(point)


func visible_temple_at(point: Vector2) -> String:
	for site: Dictionary in state.get("progression",{}).get("shrines",[]):
		if str(site.get("model_id","")).is_empty(): continue
		if not terrain_region.has_point(Vector2i(site["x"],site["z"])): continue
		if height_at(site["x"],site["z"])<=0 and not site.get("source_center",false): continue
		var displayed := false
		if site.get("started",false):
			for home: Dictionary in state.get("homes",[]):
				if home.get("shrine_id","")==site["id"] and home_nodes.has(int(home["id"])):
					displayed=home_nodes[int(home["id"])].has_method("set_stage")
					break
		else:
			var key: String="shrine:"+str(site["id"])
			displayed=progression_nodes.has(key) and progression_nodes[key].visible
		if not displayed: continue
		if height_at(roundi(point.x),roundi(point.y))>temple_position(site).y/Terrain.STEP+0.1: continue
		var offset := 0.0 if site.get("source_center",false) else 0.5
		if point.distance_to(Vector2(site["x"]+offset,site["z"]+offset))<1.2: return str(site["id"])
	return ""


func temple_position(site: Dictionary) -> Vector3:
	# Keep the authored horizontal anchor throughout repair. Older terrain
	# edits may have left that anchor's ground below the shrine.
	var offset := 0.0 if site.get("source_center",false) else 0.5
	var position_ := world_position(float(site["x"])+offset,float(site["z"])+offset)
	if site.get("source_height")!=null:
		var authored_height := (float(site["source_height"])-float(state.get("source_map",{}).get("sea_level",19)))*Terrain.STEP
		position_.y=minf(position_.y,authored_height)
	return position_


func progression_at(point: Vector2) -> Dictionary:
	if not state.has("progression"): return {}
	for prop: Dictionary in state.get("props",[]):
		if prop.get("kind") in ["belief_collector","capacity_shrine","speed_shrine"] and Vector2(prop["x"],prop["z"]).distance_squared_to(point)<=0.5:
			return {"type":"inspect_"+str(prop["kind"]),"id":prop["id"]}
	var rules: Dictionary=state.get("opening",{}).get("definition",{}).get("fountain",{})
	if not rules.is_empty():
		for prop: Dictionary in state.get("props",[]):
			if prop.get("kind")!="fountain": continue
			var area:=Rect2(prop["x"]-0.5,prop["z"]-0.5,rules["width"],rules["depth"])
			if area.has_point(point): return {"type":"campaign_fountain_tap","id":prop["id"]}
	var p: Dictionary = state["progression"]
	for chest: Dictionary in p["chests"]:
		var exposed: bool=chest.get("exposed",height_at(chest["x"],chest["z"])<=chest["height"])
		if not chest["opened"] and not chest.get("opening",false) and (chest["height"]>=0 or chest.get("native",false)) and exposed and point.distance_to(Vector2(chest["x"],chest["z"]))<0.7: return {"type":"open_chest","id":chest["id"]}
	var x := floori(point.x) if state.has("source_scenery") else roundi(point.x)
	var z := floori(point.y) if state.has("source_scenery") else roundi(point.y)
	var cell: int = z*int(state["width"])+x
	var authored_covered := false
	var rock_index := int(state.get("source_rock_cells",{}).get(str(cell),-1))
	if rock_index>=0:
		authored_covered=true
		if state["source_rock_visibility"][rock_index]: return {"type":"tap_object","cell":int(state["authored_rocks"][rock_index]["cell"])}
	if tree_targetable(x,z,cell):
		return {"type":"tap_tree","cell":cell}
	if authored_covered: return {}
	if x>=0 and z>=0 and x<state["width"] and z<state["width"] and height_at(x,z)>0 and cell<state.get("rocks",PackedByteArray()).size() and (not state.has("rock_heights") or height_at(x,z)==state["rock_heights"][cell]) and state.get("rocks",PackedByteArray())[cell]>0 and int(p["rock_taps"].get(str(cell),0))<int(p["rules"]["config"].get("tapsToDestroyRock",2)):
		return {"type":"tap_object","cell":cell}
	return {}


func tree_targetable(x: int,z: int,cell: int) -> bool:
	return x>=0 and z>=0 and x<state["width"] and z<state["width"] and tree_index.has(cell) \
		and (height_at(x,z)>0 or state.has("source_scenery")) and not state.get("removed_trees",{}).has(str(cell)) \
		and state.get("tree_response",{}).get("entries",{}).get(str(cell),{}).get("enabled",true)


func update_progression() -> void:
	var p: Dictionary = state["progression"]
	chest_glints.sync(p["chests"],int(state["width"]),int(state.get("tick",0)),terrain_region,ocean.position.y)
	var current_sites := {}
	for site: Dictionary in p["shrines"]: current_sites["shrine:"+str(site["id"])]=true
	var current_chests := {}
	for chest: Dictionary in p["chests"]: current_chests["chest:"+str(chest["id"])]=true
	for key: String in progression_nodes.keys():
		if (key.begins_with("shrine:") and not current_sites.has(key)) or (key.begins_with("chest:") and not current_chests.has(key)):
			progression_nodes[key].queue_free()
			progression_nodes.erase(key)
	for chest: Dictionary in p["chests"]:
		if chest["opened"] and not chest.get("native",false):
			var used_key: String = "chest:"+chest["id"]
			if progression_nodes.has(used_key):
				progression_nodes[used_key].queue_free()
				progression_nodes.erase(used_key)
			continue
		var exposed: bool=chest.get("exposed",height_at(chest["x"],chest["z"])<=chest["height"])
		var submerged: bool=chest["height"]<0.0
		if submerged and not (chest.get("native",false) and (exposed or chest.get("opening",false))): continue
		if not terrain_region.has_point(Vector2i(chest["x"],chest["z"])): continue
		var key: String = "chest:"+chest["id"]
		if not progression_nodes.has(key) and resolve_unit.is_valid():
			# All meshes and three lifecycle clips are recovered from chest.group.
			var model: String = {"treasure1":"f844d7b4","treasure2":"002572ae","treasure3":"009a2c5c","treasure4":"eae1d693","treasure5":"6c5ed019"}.get(chest["type"],"")
			var id := "chest.group.bin:"+model
			if not unit_assets.has(id): unit_assets[id]=resolve_unit.call(id)
			if unit_assets[id].is_empty(): continue
			var actor := OriginalFollower.new()
			actor.assets=unit_assets[id]
			actor.visual_scale=0.003
			actor.animation_state="chest_stuck"
			actor.position=world_position(chest["x"],chest["z"])
			actor.rotation_degrees.y=float(chest["rotation"])
			add_child(actor)
			progression_nodes[key]=actor
		if progression_nodes.has(key):
			var actor: Node3D = progression_nodes[key]
			actor.position.y=ocean.position.y if submerged else float(chest["height"])*Terrain.STEP
			actor.animation_state="chest_open" if chest.get("opening",chest["opened"]) else ("chest_freed" if exposed else "chest_stuck")
			actor.looped=not chest.get("opening",chest["opened"])
			actor.set_process(is_processing())
			if actor.cue_audio!=null:
				actor.cue_audio.set_effects_enabled(effects_enabled)
				actor.cue_audio.set_effects_volume(effects_db)
	for shrine: Dictionary in p["shrines"]:
		var key: String = "shrine:"+shrine["id"]
		if progression_nodes.has(key) and progression_nodes[key].get_meta("model_id","")!=shrine.get("model_id",""):
			progression_nodes[key].queue_free()
			progression_nodes.erase(key)
		if shrine["started"]:
			if progression_nodes.has(key): progression_nodes[key].visible=false
			continue
		var visible_site: bool=terrain_region.has_point(Vector2i(shrine["x"],shrine["z"])) and (height_at(shrine["x"],shrine["z"])>0 or shrine.get("source_center",false))
		if not visible_site:
			if progression_nodes.has(key): progression_nodes[key].visible=false
			continue
		if not progression_nodes.has(key) and resolve_building.is_valid():
			if str(shrine["model_id"]).is_empty(): continue
			var data: Dictionary = resolve_building.call(shrine["model_id"])
			if data.is_empty(): continue
			var node := preload("res://presentation/world/assembled_building.gd").new()
			node.data=data
			node.scale=Vector3.ONE*0.003
			node.rotation_degrees.y=float(shrine.get("rotation",0))
			node.set_meta("model_id",shrine["model_id"])
			add_child(node)
			progression_nodes[key]=node
		if progression_nodes.has(key):
			var node: Node3D=progression_nodes[key]
			node.visible=true
			node.position=temple_position(shrine)
			node.rotation_degrees.y=float(shrine.get("rotation",0))
			var complete: bool=shrine.get("complete",false) or int(shrine.get("build_ticks",0))==0
			node.set_stage(node.maximum_part() if complete else 1,complete)
	var totem: Dictionary = p["totem"]
	if not totem.is_empty() and ResourceLoader.exists("res://assets/extracted/VFX/Textures/GLO_SmokeyBeam_Blue.tga"):
		if not progression_nodes.has("totem"):
			var beam := Sprite3D.new()
			beam.texture=load("res://assets/extracted/VFX/Textures/GLO_SmokeyBeam_Blue.tga")
			beam.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			beam.pixel_size=2.1/beam.texture.get_width()
			beam.shaded=false
			add_child(beam)
			progression_nodes["totem"]=beam
		var beam: Sprite3D = progression_nodes["totem"]
		beam.position=world_position(totem["x"],totem["z"])+Vector3(0,2,0)
		beam.visible=totem.get("active",false)


func update_rocks() -> void:
	rocks.update(state,terrain_region)
	rock_templates=rocks.templates


func apply_source_lighting() -> void:
	var p: Dictionary = state.get("progression",{})
	var next_revision: int = p.get("revision",-1)
	if lighting_revision==next_revision: return
	lighting_revision=next_revision
	var config: Dictionary = p.get("rules",{}).get("config",{})
	if config.is_empty(): return
	var colors := {}
	for key: String in ["LightColour","LightAmbient","BGColour"]:
		var prefix: String={"LightColour":"light","LightAmbient":"ambient","BGColour":"background"}[key]
		colors[key]=Color(float(preferences.get("visuals."+prefix+"_r",config.get(key+".x",0.45))),float(preferences.get("visuals."+prefix+"_g",config.get(key+".y",0.45))),float(preferences.get("visuals."+prefix+"_b",config.get(key+".z",0.45))))
	light.light_color=colors["LightColour"]
	environment.environment.background_color=colors["BGColour"]
	environment.environment.ambient_light_color=colors["LightAmbient"]
	# Terrain materials may be created later by the asynchronous tile installer.
	preload("res://presentation/world/source_material.gd").crop_lighting(Vector3(colors["LightColour"].r,colors["LightColour"].g,colors["LightColour"].b),Vector3(colors["LightAmbient"].r,colors["LightAmbient"].g,colors["LightAmbient"].b))
	if terrain.shared_material==null: terrain.shared_material=Ground.terrain_material()
	for material: ShaderMaterial in [Ground.material(false),terrain.shared_material]:
		material.set_shader_parameter("source_light",Vector3(colors["LightColour"].r,colors["LightColour"].g,colors["LightColour"].b))
		material.set_shader_parameter("source_ambient",Vector3(colors["LightAmbient"].r,colors["LightAmbient"].g,colors["LightAmbient"].b))


func register_geometry(node: Node) -> void:
	if node is GeometryInstance3D and is_ancestor_of(node): influence_view.attach_overlays(node)
