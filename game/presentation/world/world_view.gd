extends Node3D
## Camera, terrain and actor views. Decisions arrive only as detached snapshots.

signal pointer_action(cell: Vector2i, point: Vector2)
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
var scenery_assets: Dictionary = {}
var resolve_model: Callable
var prop_nodes: Dictionary = {}
var prop_meshes: Dictionary = {}
var animation_speed := 1.0
var terrain := Terrain.new()
var camera := Camera3D.new()
var marker := Sprite3D.new()
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
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ocean.mesh = plane
	ocean.position.y = 0.06
	var water := Ground.material(true)
	ocean.material_override = water
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
	update_camera()


func apply_snapshot(snapshot: Dictionary) -> void:
	var first := state.is_empty()
	var trees_changed := first or not is_same(state.get("trees"),snapshot.get("trees"))
	state = snapshot
	tutorial_camera_locked=state.get("opening",{}).get("camera_locked",false)
	tutorial_zoom_locked=state.get("opening",{}).get("zoom_locked",false)
	if tutorial_camera_locked:
		orbiting=false
		panning=false
	if trees_changed:
		tree_index.clear()
		for tree: Dictionary in state["trees"]: tree_index[int(tree.get("cell",int(tree["z"])*int(state["width"])+int(tree["x"])))]=true
	terrain.apply_voyage(state)
	apply_source_lighting()
	if first and state.has("camera_start"):
		var center := (int(state["width"])-1)*0.5
		focus = Vector3(state["camera_start"]["x"]-center,0,state["camera_start"]["z"]-center)
		zoom = 30
		(ocean.mesh as PlaneMesh).size = Vector2.ONE*(state["width"]*10)
		camera.far = 20000
		update_camera(false)
	var region_changed := refresh_region()
	if region_changed: tree_revision = -1
	if revision != int(state["terrain_revision"]) or region_changed:
		var terrain_changed := revision != int(state["terrain_revision"])
		revision = int(state["terrain_revision"])
		terrain.rebuild(state)
		if terrain_changed and not bathymetry.is_empty(): update_water_field()
	if trees_changed or state.has("tree_response") or tree_revision != revision or tree_home_count != state["homes"].size() or vegetation_revision!=int(state.get("vegetation_revision",0)):
		tree_revision = revision
		tree_home_count = state["homes"].size()
		vegetation_revision=int(state.get("vegetation_revision",0))
		update_trees()
	for key in ["followers", "sheep","enemies"]:
		for agent: Dictionary in state.get(key,[]):
			var id: int = agent["id"]
			var profession: String = agent.get("profession","") if key=="followers" else ""
			if actor_nodes.has(id) and actor_nodes[id].get_meta("profession","")!=profession:
				actor_nodes[id].queue_free()
				actor_nodes.erase(id)
			if not actor_nodes.has(id):
				var actor: Node3D
				var source_assets: Dictionary = follower_assets if key == "followers" else sheep_assets
				if not profession.is_empty() and resolve_worker.is_valid():
					if not worker_assets.has(profession): worker_assets[profession]=resolve_worker.call(profession)
					source_assets=worker_assets[profession]
				if key=="enemies": source_assets=enemy_assets.get(agent.get("kind","champion"),{})
				if not source_assets.is_empty():
					var human := OriginalFollower.new()
					human.assets = source_assets
					human.variant = (1 if agent["female"] else 0) if agent.has("female") else id
					human.visual_scale = 0.005 if key == "sheep" else 0.003
					actor = human
				else:
					actor = Node3D.new() # Unsupported content stays unrendered.
				actor.position = world_position(agent["x"], agent["z"])
				add_child(actor)
				actor_nodes[id] = actor
				actor.set_meta("profession",profession)
			actor_nodes[id].set_meta("data", agent)
			if actor_nodes[id] is OriginalFollower:
				actor_nodes[id].scale=Vector3.ONE*actor_nodes[id].visual_scale*float(agent.get("scale",1))
				actor_nodes[id].animation_state = agent["state"]
				actor_nodes[id].playback_speed = animation_speed
				actor_nodes[id].set_process(is_processing())
				if actor_nodes[id].cue_audio != null:
					actor_nodes[id].cue_audio.set_effects_enabled(effects_enabled)
					actor_nodes[id].cue_audio.set_effects_volume(effects_db)
	for home: Dictionary in state["homes"]:
		var id: int = home["id"]
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
			elif home.get("kind","")=="shrine": building=Node3D.new()
			else: building=Actors.home(scenery_assets.get("tents", {}), Style.source_font())
			building.set_meta("model_id",home.get("model_id",""))
			add_child(building)
			home_nodes[id] = building
		var node: Node3D = home_nodes[id]
		var offset := (float(home.get("span",2))-1)*0.5
		node.position = world_position(home["x"] + offset, home["z"] + offset)
		if home.get("kind","")=="shrine":
			for site: Dictionary in state.get("progression",{}).get("shrines",[]):
				if site["id"]==home.get("shrine_id",""):
					node.position=temple_position(site)
					break
		node.rotation_degrees.y=float(home.get("rotation",0))
		if home.get("kind","")=="shrine" and not node.has_method("set_stage"): continue
		var build_ticks: int = home.get("build_ticks",state.get("build_ticks", 60))
		var complete: bool = home["progress"] >= build_ticks
		update_home_badge(home, node, complete)
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
	building_batches.update(state,home_nodes)
	for id: int in home_nodes.keys():
		var found := false
		for home: Dictionary in state["homes"]:
			if home["id"]==id: found=true; break
		if not found:
			home_nodes[id].queue_free()
			home_nodes.erase(id)
			home_badges.erase(id)
	for id: int in actor_nodes.keys():
		var found := false
		for key: String in ["followers","sheep","enemies"]:
			for agent: Dictionary in state.get(key,[]):
				if agent["id"]==id: found=true; break
		if not found: actor_nodes[id].queue_free(); actor_nodes.erase(id)
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
			prop_nodes[id].position = world_position(prop["x"], prop["z"])
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
		var in_range: bool = not state["progression"].get("influence_enabled",false)
		for area: Dictionary in state["progression"].get("influence",[]):
			if Vector2(settlement["x"],settlement["z"]).distance_squared_to(Vector2(area["x"],area["z"]))<=pow(float(area["radius"]),2): in_range=true; break
		home_badges[id]={"position":prop_nodes[id].position+Vector3(0,2,0),"source_sprite":sprite,"visible":in_range}
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
			node.position=world_position(temple["x"],temple["z"])
			node.rotation_degrees.y=float(temple.get("rotation",0))
			add_child(node)
			progression_nodes[key]=node
			if temple.get("symbol","")=="speed" and resolve_model.is_valid():
				var symbol: Dictionary = resolve_model.call("symbols.group.bin:105f2796")
				if not symbol.is_empty(): node.add_child(Actors.mesh(symbol))
		if progression_nodes.has(key):
			var node: Node3D = progression_nodes[key]
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


func update_home_badge(home: Dictionary, building: Node3D, complete: bool) -> void:
	if not state.has("campaign") or status_textures.is_empty(): return
	var id: int = home["id"]
	var badge := {}
	var ready: bool = complete and int(home["stored"]) > 0 and int(home["stored"]) >= int(home.get("min_belief", 0))
	var name_ := "GFX_IWIcon_Belief.png" if ready else "GFX_Pawn_Worker.png"
	if home.get("kind","")=="farm": name_="GFX_Pawn_Farmer.png"
	elif home.get("kind","")=="mine": name_="GFX_Pawn_Miner.png"
	var height := 1.0
	if building.has_method("set_stage"): height = maxf(height, building.source_bounds.end.y * building.scale.y)
	badge["position"] = building.position + Vector3(0, height + 0.4, 0)
	badge["source_sprite"] = name_
	badge["visible"] = true
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
	var draft := state.duplicate(false)
	draft["terrain"] = state["terrain"].duplicate()
	for edit: Dictionary in edits:
		draft["terrain"][edit["cell"]] = edit["height"]
	terrain.rebuild(draft,true)


func cancel_preview() -> void:
	layer_drag = false
	if not state.is_empty():
		terrain.rebuild(state,true)


func update_water_field() -> void:
	var width: int = state["width"]
	var pixels := bathymetry.duplicate()
	for z in range(terrain_region.position.y,terrain_region.end.y):
		for x in range(terrain_region.position.x,terrain_region.end.x):
			var index := z*width+x
			if state["terrain"][index] > 0: pixels[index] = mini(255,int(state["terrain"][index])+19)
	var image := Image.create_from_data(width,width,false,Image.FORMAT_R8,pixels)
	var material := Ground.material(true).duplicate() as ShaderMaterial
	material.set_shader_parameter("use_terrain_depth",true)
	material.set_shader_parameter("terrain_width",float(width))
	material.set_shader_parameter("terrain_field",ImageTexture.create_from_image(image))
	ocean.material_override = material


func height_at(x: float, z: float) -> int:
	var width: int = state.get("width", 0)
	var ix := clampi(roundi(x), 0, maxi(width - 1, 0))
	var iz := clampi(roundi(z), 0, maxi(width - 1, 0))
	return int(state["terrain"][iz * width + ix]) if width > 0 else 0


func world_position(x: float, z: float) -> Vector3:
	var center := (int(state["width"]) - 1) * 0.5
	return Vector3(x - center, height_at(x, z) * Terrain.STEP, z - center)


func home_at(x: float, z: float) -> int:
	var temple := -1
	for home: Dictionary in state.get("homes", []):
		if x >= home["x"] - 0.5 and x < home["x"] + float(home.get("span",2))-0.5 and z >= home["z"] - 0.5 and z < home["z"] + float(home.get("span",2))-0.5:
			if home.get("kind","")=="shrine": temple=int(home["id"])
			else: return int(home["id"])
	return temple


func pick(screen: Vector2, plane_height: float = -1) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var center := (int(state["width"]) - 1) * 0.5
	if plane_height >= 0:
		var hit := origin + ray * ((plane_height - origin.y) / ray.y)
		return Vector2(hit.x + center, hit.z + center)
	for level in range(63 if state.has("campaign") else 7, -1, -1):
		var hit := origin + ray * ((level * Terrain.STEP - origin.y) / ray.y)
		var point := Vector2(hit.x + center, hit.z + center)
		if point.x >= 0 and point.y >= 0 and point.x < state["width"] and point.y < state["width"] and height_at(point.x, point.y) == level:
			return point
	return Vector2(-1, -1)


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
	return {"type":"campaign_view","projection":[x.x,z.x,height.x,base.x,x.y,z.y,height.y,base.y],"ended":ended}


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
				if event.double_click: double_action.emit(Vector2i(roundi(point.x),roundi(point.y)))
				else: pointer_action.emit(Vector2i(roundi(point.x), roundi(point.y)), point)
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
	if state.is_empty():
		return
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
			actor.animation_state = data["state"]
			actor.playback_speed = animation_speed
			var pixels := get_viewport().get_visible_rect().size.y/zoom
			actor.animation_interval=0.0 if pixels>50 else (1.0/30 if pixels>15 else (1.0/15 if pixels>4 else 1.0/8))
			if not camera.is_position_in_frustum(actor.position+Vector3(0,0.7,0)): actor.animation_interval=0.5
		var target := world_position(data["x"], data["z"])
		var offset := target - actor.position
		actor.position = actor.position.lerp(target, minf(delta * 14, 1))
		if data["state"] in ["hugging_give","hugging_take"]:
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
	# The same authored anchor applies before, during and after repair. House
	# plot centers must not move a temple when its construction record appears.
	var offset := 0.0 if site.get("source_center",false) else 0.5
	var position_ := world_position(float(site["x"])+offset,float(site["z"])+offset)
	if site.get("source_height")!=null:
		position_.y=(float(site["source_height"])-float(state.get("source_map",{}).get("sea_level",19)))*Terrain.STEP
	return position_


func progression_at(point: Vector2) -> Dictionary:
	if not state.has("progression"): return {}
	var p: Dictionary = state["progression"]
	for chest: Dictionary in p["chests"]:
		if not chest["opened"] and chest["height"]>=0 and height_at(chest["x"],chest["z"])<=chest["height"] and point.distance_to(Vector2(chest["x"],chest["z"]))<0.7: return {"type":"open_chest","id":chest["id"]}
	var x := floori(point.x) if state.has("source_scenery") else roundi(point.x)
	var z := floori(point.y) if state.has("source_scenery") else roundi(point.y)
	var cell: int = z*int(state["width"])+x
	var authored_covered := false
	var rock_index := int(state.get("source_rock_cells",{}).get(str(cell),-1))
	if rock_index>=0:
		authored_covered=true
		if state["source_rock_visibility"][rock_index]: return {"type":"tap_object","cell":int(state["authored_rocks"][rock_index]["cell"])}
	if x>=0 and z>=0 and x<state["width"] and z<state["width"] and (height_at(x,z)>0 or state.has("source_scenery")) and tree_index.has(cell) and not state.get("removed_trees",{}).has(str(cell)) and state.get("tree_response",{}).get("entries",{}).get(str(cell),{}).get("enabled",true):
		return {"type":"tap_tree","cell":cell}
	if authored_covered: return {}
	if x>=0 and z>=0 and x<state["width"] and z<state["width"] and height_at(x,z)>0 and cell<state.get("rocks",PackedByteArray()).size() and (not state.has("rock_heights") or height_at(x,z)==state["rock_heights"][cell]) and state.get("rocks",PackedByteArray())[cell]>0 and int(p["rock_taps"].get(str(cell),0))<int(p["rules"]["config"].get("tapsToDestroyRock",2)):
		return {"type":"tap_object","cell":cell}
	return {}


func update_progression() -> void:
	var p: Dictionary = state["progression"]
	var current_sites := {}
	for site: Dictionary in p["shrines"]: current_sites["shrine:"+str(site["id"])]=true
	var current_chests := {}
	for chest: Dictionary in p["chests"]: current_chests["chest:"+str(chest["id"])]=true
	for key: String in progression_nodes.keys():
		if (key.begins_with("shrine:") and not current_sites.has(key)) or (key.begins_with("chest:") and not current_chests.has(key)):
			progression_nodes[key].queue_free()
			progression_nodes.erase(key)
	for chest: Dictionary in p["chests"]:
		if chest["opened"]:
			var used_key: String = "chest:"+chest["id"]
			if progression_nodes.has(used_key):
				progression_nodes[used_key].queue_free()
				progression_nodes.erase(used_key)
			continue
		if chest["height"]<0 or not terrain_region.has_point(Vector2i(chest["x"],chest["z"])): continue
		var key: String = "chest:"+chest["id"]
		if not progression_nodes.has(key) and resolve_unit.is_valid():
			# All meshes and three lifecycle clips are recovered from chest.group.
			var model: String = {"treasure1":"f844d7b4","treasure2":"002572ae","treasure3":"009a2c5c","treasure4":"eae1d693"}.get(chest["type"],"")
			var id := "chest.group.bin:"+model
			if not unit_assets.has(id): unit_assets[id]=resolve_unit.call(id)
			if unit_assets[id].is_empty(): continue
			var actor := OriginalFollower.new()
			actor.assets=unit_assets[id]
			actor.visual_scale=0.003
			actor.animation_state="chest_stuck"
			actor.position=world_position(chest["x"],chest["z"])
			actor.position.y=float(chest["height"])*Terrain.STEP
			actor.rotation_degrees.y=float(chest["rotation"])
			add_child(actor)
			progression_nodes[key]=actor
		if progression_nodes.has(key):
			var actor: Node3D = progression_nodes[key]
			var exposed: bool = height_at(chest["x"],chest["z"])<=chest["height"]
			actor.animation_state="chest_open" if chest["opened"] else ("chest_freed" if exposed else "chest_stuck")
			actor.looped=not chest["opened"]
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
