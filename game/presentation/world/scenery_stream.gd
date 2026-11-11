extends Node3D
## Persistent source-mesh batches, rebuilt a tile at a time rather than on pan.
const Actors=preload("res://presentation/world/actors.gd")
const TILE := 64
var index: Dictionary = {}
var templates: Dictionary = {}
var tiles: Dictionary = {}
var pending: Array[Vector2i] = []
var wanted: Dictionary = {}
var models: Array = []
var choices: Array = []
var state: Dictionary = {}
var region := Rect2i()
var generation := 0
var revision := -1
var home_count := -1
var rock_revision := -1
var vegetation_revision := -1
var removed_trees: Dictionary = {}
var vegetation_tiles: Dictionary = {}
var rock_mode := false
var initialized := false
var max_build_usec := 0
var max_request_usec := 0
var builds := 0
var blocked: Dictionary = {}
var imposters: Dictionary = {}
var lod := 0
var next_lod := 0
var imposter_material: ShaderMaterial
var imposter_mesh := QuadMesh.new()
var sprite_shapes: Dictionary = {}
var pixels_per_unit := 25.0
var authored_rocks: Dictionary = {}
var model_choices: Dictionary = {}
var legacy_variant_count := 0
var rock_instances: Dictionary = {}
var motion_targets: Dictionary = {}
var motion_revision := -1
var tree_instances: Dictionary = {}
var tree_motion: Dictionary = {}
var tree_response_revision := -1
var tree_tick := -1
var tree_clock := 0.0
var tree_between := 0.0
var tree_fires: Dictionary = {}
var charred_trees: Dictionary = {}
var indexed_trees: Array = []
var planted_ticks: Dictionary = {}
const TreeAnimation = preload("res://presentation/world/source_tree_animation.gd")

func configure(assets: Dictionary,rocks: bool) -> void:
	imposters=assets.get("imposters",{})
	rock_mode=rocks
	models=assets.get("models",[])
	choices=assets.get("standing",[])
	if rocks:
		for i in range(models.size()): choices.append(i)
	legacy_variant_count=int(assets.get("variant_count",choices.size()))
	for i in range(choices.size()):
		var model: Dictionary = models[choices[i]]
		var id: String = model.get("source_model_id",model.get("descriptor",{}).get("id",""))
		if not id.is_empty(): model_choices[id]=i

func update(data: Dictionary,area: Rect2i) -> void:
	if models.is_empty() or choices.is_empty(): return
	var started := Time.get_ticks_usec()
	state=data
	if not initialized:
		initialized=true
		var width: int=state["width"]
		if rock_mode:
			var covered := {}
			var objects: Array = state.get("authored_rocks",[])
			for i in range(objects.size()):
				var rock: Dictionary = objects[i]
				var cell := int(rock["cell"])
				authored_rocks[cell]=i
				var key := Vector2i((cell%width)/TILE,(cell/width)/TILE)
				if not index.has(key): index[key]=[]
				index[key].append(cell)
				for dz in range(int(rock["size_z"])):
					for dx in range(int(rock["size_x"])): covered[(int(rock["origin_z"])+dz)*width+int(rock["origin_x"])+dx]=true
			var field: PackedByteArray=state.get("rocks",PackedByteArray())
			for cell in range(field.size()):
				if field[cell]==0 or covered.has(cell): continue
				var key := Vector2i((cell%width)/TILE,(cell/width)/TILE)
				if not index.has(key): index[key]=[]
				index[key].append(cell)
	var trees_changed: bool=not rock_mode and not is_same(indexed_trees,state["trees"])
	if trees_changed:
		var previous := index
		index={}
		planted_ticks.clear()
		indexed_trees=state["trees"]
		for item: Dictionary in indexed_trees:
			var key := Vector2i(int(item["x"])/TILE,int(item["z"])/TILE)
			if not index.has(key): index[key]=[]
			index[key].append(item)
			if item.has("planted_tick"): planted_ticks[int(item["cell"])]=int(item["planted_tick"])
		for key: Vector2i in index:
			if previous.get(key,[])!=index[key]: vegetation_tiles[key]=true
	if rock_mode: receive_motion()
	elif state.has("tree_response"): receive_trees()
	var next_rocks: int=state.get("progression",{}).get("rock_revision",0)
	var terrain_changed: bool=revision!=int(state["terrain_revision"]) and not (rock_mode and state.has("rock_motion") or not rock_mode and state.has("tree_response"))
	var structural: bool = terrain_changed or home_count!=state["homes"].size() or rock_revision!=next_rocks or next_lod!=lod
	var vegetation_changed: bool = not rock_mode and vegetation_revision!=int(state.get("vegetation_revision",0))
	if vegetation_changed:
		var next_removed: Dictionary = state.get("removed_trees",{})
		for cell: String in next_removed:
			if not removed_trees.has(cell): vegetation_tiles[Vector2i((int(cell)%int(state["width"]))/TILE,(int(cell)/int(state["width"]))/TILE)]=true
		for cell: String in removed_trees:
			if not next_removed.has(cell): vegetation_tiles[Vector2i((int(cell)%int(state["width"]))/TILE,(int(cell)/int(state["width"]))/TILE)]=true
		removed_trees=next_removed
	var changed: bool = structural or vegetation_changed or trees_changed
	if changed:
		lod=next_lod
		if structural: generation+=1
		revision=state["terrain_revision"]
		home_count=state["homes"].size()
		rock_revision=next_rocks
		vegetation_revision=int(state.get("vegetation_revision",0))
		blocked.clear()
		var width: int=state["width"]
		for home: Dictionary in state["homes"]:
			for dz in range(int(home.get("span",2))):
				for dx in range(int(home.get("span",2))): blocked[(int(home["z"])+dz)*width+int(home["x"])+dx]=true
	if rock_mode and lod>=2:
		for node: Node3D in tiles.values(): node.visible=false
		pending.clear()
		region=area
		return
	if region==area and not changed: return
	region=area
	wanted.clear()
	pending.clear()
	for z in range(floori(area.position.y/float(TILE)),ceili(area.end.y/float(TILE))):
		for x in range(floori(area.position.x/float(TILE)),ceili(area.end.x/float(TILE))):
			var key := Vector2i(x,z)
			if not index.has(key): continue
			wanted[key]=true
			if not tiles.has(key) or tiles[key].get_meta("generation",-1)!=generation or vegetation_tiles.has(key): pending.append(key)
	for key: Vector2i in tiles:
		tiles[key].visible=wanted.has(key)
	if tiles.size()>maxi(160,wanted.size()*2):
		for key: Vector2i in tiles.keys():
			if not wanted.has(key): forget_rock_tile(key); forget_tree_tile(key); tiles[key].queue_free(); tiles.erase(key)
	var center := Vector2(area.get_center())/TILE
	pending.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return Vector2(a).distance_squared_to(center)<Vector2(b).distance_squared_to(center))
	max_request_usec=maxi(max_request_usec,Time.get_ticks_usec()-started)

func _process(delta: float) -> void:
	advance_motion(delta)
	advance_trees(delta)
	if pending.is_empty(): return
	var started := Time.get_ticks_usec()
	build_tile(pending.pop_front())
	max_build_usec=maxi(max_build_usec,Time.get_ticks_usec()-started)

func build_tile(key: Vector2i) -> void:
	var width: int=state["width"]
	var center := (width-1)*0.5
	var groups := {}
	var angles := {}
	var point_cells := {}
	var tree_min := Vector3.INF
	var tree_max := -Vector3.INF
	forget_rock_tile(key)
	forget_tree_tile(key)
	for item: Variant in index[key]:
		var cell: int=int(item) if rock_mode else int(item.get("cell",int(item["z"])*width+int(item["x"])))
		var source_tree: bool=not rock_mode and item.has("source_y")
		var source_rock: bool=rock_mode and authored_rocks.has(cell) and state.has("rock_motion")
		if blocked.has(cell) or (state["terrain"][cell]<=0 and not (source_tree and (item["anchor_height"]==0 or state.has("tree_response"))) and not source_rock): continue
		if not rock_mode and state.get("removed_trees",{}).has(str(cell)): continue
		if rock_mode and not authored_rocks.has(cell):
			if state.has("rock_heights") and state["terrain"][cell]!=state["rock_heights"][cell]: continue
			if int(state["progression"]["rock_taps"].get(str(cell),0))>=int(state["progression"]["rules"]["config"].get("tapsToDestroyRock",2)): continue
		var variant: int=(int(state["rocks"][cell])-1)%choices.size() if rock_mode else tree_variant(item)
		var point := Vector3(cell%width-center,int(state["terrain"][cell])*0.3,cell/width-center)
		if source_tree:
			if variant<0: continue
			point=tree_position(item,cell)
			angles[point]=float(item["rotation"])
			point_cells[point]=cell
		if rock_mode and authored_rocks.has(cell):
			var object_index: int=authored_rocks[cell]
			if object_index>=state.get("source_rock_visibility",PackedByteArray()).size() or not state["source_rock_visibility"][object_index]: continue
			var rock: Dictionary = state["authored_rocks"][object_index]
			variant=-1
			for i in range(choices.size()):
				if models[choices[i]].get("descriptor",{}).get("name")==rock["model_name"]: variant=i; break
			if variant<0: continue # Missing original models stay unavailable.
			point.x=float(rock["x"])-center
			point.z=float(rock["z"])-center
			if rock.has("source_y"): point.y=motion_height(cell,float(rock["source_y"]))
			angles[point]=float(rock["rotation"]) if rock.has("source_y") else deg_to_rad(float(rock["rotation"]))
			point_cells[point]=cell
		if rock_mode and lod>=2: continue # Visible rock tops are subpixel at this scale.
		if not rock_mode:
			tree_min=tree_min.min(point)
			tree_max=tree_max.max(point)
		if not groups.has(variant): groups[variant]=[]
		groups[variant].append(point)
	var root := Node3D.new()
	root.set_meta("generation",generation)
	var variants := groups.keys()
	if not rock_mode and lod>=1 and not imposters.is_empty():
		var sprites := {}
		for variant: int in groups.keys():
			if models[choices[variant]].has("imposter_index"):
				sprites[variant]=groups[variant]
				groups.erase(variant)
		if not sprites.is_empty(): root.add_child(make_imposter_batch(sprites,point_cells,key))
	for variant: int in groups:
		if not templates.has(variant): templates[variant]=Actors.mesh(models[choices[variant]])
		var template: MeshInstance3D=templates[variant]
		var multi := MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=template.mesh
		multi.use_colors=not rock_mode and has_finger_trees()
		multi.instance_count=groups[variant].size()
		var transforms := PackedFloat32Array()
		var stride := 16 if multi.use_colors else 12
		transforms.resize(multi.instance_count*stride)
		for i in range(multi.instance_count):
			var point: Vector3=groups[variant][i]
			var offset := i*stride
			transforms[offset]=0.003
			transforms[offset+3]=point.x
			transforms[offset+5]=0.003
			transforms[offset+7]=point.y
			transforms[offset+10]=0.003
			if not angles.is_empty():
				var angle: float=angles.get(point,0.0)
				if angle!=0:
					transforms[offset]=cos(angle)*0.003
					transforms[offset+2]=sin(angle)*0.003
					transforms[offset+8]=-sin(angle)*0.003
					transforms[offset+10]=cos(angle)*0.003
			transforms[offset+11]=point.z
			if multi.use_colors:
				for component in range(12,16): transforms[offset+component]=1.0
		multi.buffer=transforms
		var node := MultiMeshInstance3D.new()
		node.multimesh=multi
		node.custom_aabb=multi.get_aabb().grow(3)
		node.material_override=template.material_override
		# Source geometry still renders; no shadow-map redraw for static batches.
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
		if not rock_mode and state.has("tree_response"):
			for i in range(groups[variant].size()):
				var point: Vector3=groups[variant][i]
				if point_cells.has(point):
					var transform := Transform3D(Basis(Vector3.UP,float(angles.get(point,0.0))).scaled(Vector3.ONE*0.003),point)
					bind_tree(int(point_cells[point]),multi,node,i,key,transform,0.0)
		if rock_mode:
			for i in range(groups[variant].size()):
				var point: Vector3=groups[variant][i]
				if point_cells.has(point):
					var transform := Transform3D(Basis(Vector3.UP,float(angles.get(point,0.0))).scaled(Vector3.ONE*0.003),point)
					rock_instances[int(point_cells[point])]={"multi":multi,"node":node,"index":i,"tile":key,"height":point.y,"transform":transform}
	if not rock_mode and not variants.is_empty():
		var radius := 0.0
		for variant: int in variants:
			var bounds: AABB=templates[variant].mesh.get_aabb()
			radius=maxf(radius,bounds.position.abs().max(bounds.end.abs()).length()*0.003)
		if state.has("tree_response"):
			var config: Dictionary=state["opening"]["definition"]["tree_response_config"]
			radius*=maxf(TreeAnimation.scale_at(config,true,0.0,0.0),float(config["vertical_scale"]))
		root.set_meta("pick_bounds",AABB(tree_min,tree_max-tree_min).grow(radius))
	if tiles.has(key): tiles[key].queue_free()
	tiles[key]=root
	vegetation_tiles.erase(key)
	add_child(root)
	builds+=1


func tree_variant(tree: Dictionary) -> int:
	if tree.has("source_y"): return int(model_choices.get(tree["model_id"],-1))
	return posmod(int(tree["variant"]),legacy_variant_count) if legacy_variant_count>0 else -1


func tree_position(tree: Dictionary,cell: int) -> Vector3:
	var center := (int(state["width"])-1)*0.5
	if tree.has("source_y"):
		var displacement := 0.0 if state.has("tree_response") else (int(state["terrain"][cell])-int(tree["anchor_height"]))*0.3
		return Vector3(float(tree["x"])-center,float(tree["source_y"])+displacement,float(tree["z"])-center)
	return Vector3(int(tree["x"])-center,int(state["terrain"][cell])*0.3,int(tree["z"])-center)


func tree_ray_distance(tree: Dictionary,cell: int,origin: Vector3,direction: Vector3) -> float:
	var tile := Vector2i(int(tree["x"])/TILE,int(tree["z"])/TILE)
	if not tiles.has(tile) or not tiles[tile].visible or blocked.has(cell): return INF
	var variant := tree_variant(tree)
	if not templates.has(variant): return INF
	var transform := Transform3D(Basis(Vector3.UP,float(tree.get("rotation",0.0))).scaled(Vector3.ONE*0.003),tree_position(tree,cell))
	if tree_instances.has(cell):
		var instance: Dictionary=tree_instances[cell]
		var scale_: float=instance.get("scale",1.0)
		if scale_<=0.0: return INF
		transform.basis=transform.basis.scaled(Vector3.ONE*scale_)
		transform.origin.y+=float(instance.get("vertical_offset",0.0))
	var inverse := transform.affine_inverse()
	var hit: Variant=templates[variant].mesh.get_aabb().intersects_ray(inverse*origin,inverse.basis*direction)
	return origin.distance_to(transform*hit) if hit!=null else INF


func pick_tree(origin: Vector3,direction: Vector3,closest: float) -> int:
	var picked := -1
	var width: int=state.get("width",0)
	var responses: Dictionary=state.get("tree_response",{}).get("entries",{})
	for key: Vector2i in tiles:
		var tile: Node3D=tiles[key]
		if not tile.visible: continue
		var bounds: AABB=tile.get_meta("pick_bounds",AABB())
		if not bounds.has_volume() or bounds.intersects_segment(origin,origin+direction*closest)==null: continue
		for tree: Dictionary in index[key]:
			var cell := int(tree.get("cell",int(tree["z"])*width+int(tree["x"])))
			if removed_trees.has(str(cell)) or not responses.get(str(cell),{}).get("enabled",true): continue
			if int(state["terrain"][cell])<=0 and not (tree.has("source_y") and (tree["anchor_height"]==0 or state.has("tree_response"))): continue
			var distance := tree_ray_distance(tree,cell,origin,direction)
			if distance>=closest: continue
			closest=distance
			picked=cell
	return picked


func motion_height(cell: int,fallback: float) -> float:
	var heights: Dictionary=state.get("rock_motion",{}).get("heights",{})
	if not heights.has(str(cell)): return fallback
	return float(heights[str(cell)])-float(state["opening"]["definition"]["rock_motion_config"]["sea_height"])


func forget_rock_tile(key: Vector2i) -> void:
	for cell: int in rock_instances.keys():
		if rock_instances[cell]["tile"]==key: rock_instances.erase(cell); motion_targets.erase(cell)


func receive_motion() -> void:
	var next_revision := int(state.get("rock_motion",{}).get("revision",0))
	if motion_revision==next_revision: return
	motion_revision=next_revision
	for key: String in state.get("rock_motion",{}).get("heights",{}):
		var cell := int(key)
		if not rock_instances.has(cell): continue
		var entry: Dictionary=rock_instances[cell]
		var target := motion_height(cell,float(entry["height"]))
		if motion_targets.has(cell) and float(motion_targets[cell]["target"])==target or not motion_targets.has(cell) and float(entry["height"])==target: continue
		motion_targets[cell]={"from":float(entry["height"]),"target":target,"elapsed":0.0}
		var transform: Transform3D=entry["transform"]
		transform.origin.y=target
		var node: MultiMeshInstance3D=entry["node"]
		node.custom_aabb=node.custom_aabb.expand(transform.origin-Vector3.ONE*3).expand(transform.origin+Vector3.ONE*3)


func advance_motion(delta: float) -> void:
	for cell: int in motion_targets.keys():
		if not rock_instances.has(cell): motion_targets.erase(cell); continue
		var motion: Dictionary=motion_targets[cell]
		motion["elapsed"]=minf(0.1,float(motion["elapsed"])+delta)
		var entry: Dictionary=rock_instances[cell]
		var transform: Transform3D=entry["transform"]
		entry["height"]=lerpf(float(motion["from"]),float(motion["target"]),float(motion["elapsed"])/0.1)
		transform.origin.y=float(entry["height"])
		entry["transform"]=transform
		entry["multi"].set_instance_transform(int(entry["index"]),transform)
		if float(motion["elapsed"])>=0.1: motion_targets.erase(cell)

func _exit_tree() -> void:
	for template: Node in templates.values(): template.free()


func set_pixel_density(pixels: float) -> void:
	pixels_per_unit=pixels
	# Hysteresis prevents repeated mesh swaps around the transition.
	if next_lod==0 and pixels<12: next_lod=1
	elif next_lod==1 and pixels>15: next_lod=0
	if rock_mode:
		if pixels<3: next_lod=2
		elif next_lod==2 and pixels>4: next_lod=1


func make_imposter_batch(groups: Dictionary,point_cells: Dictionary={},tile: Vector2i=Vector2i()) -> MultiMeshInstance3D:
	if imposter_material==null:
		imposter_material=ShaderMaterial.new()
		imposter_material.shader=preload("res://presentation/world/source_imposter.gdshader")
		imposter_material.set_shader_parameter("source_texture",imposters["texture"])
		imposter_material.set_shader_parameter("foliage_color",imposters["foliage_color"])
		imposter_material.set_shader_parameter("trunk_color",imposters["trunk_color"])
		imposter_mesh.size=Vector2.ONE
	var count := 0
	for group: Array in groups.values(): count+=group.size()
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.use_custom_data=true
	multi.use_colors=has_finger_trees()
	multi.mesh=imposter_mesh
	multi.instance_count=count
	var buffer := PackedFloat32Array()
	var stride := 20 if multi.use_colors else 16
	buffer.resize(count*stride)
	var index_ := 0
	var texture_size: Vector2=imposters["texture"].get_size()
	var bindings: Array=[]
	for variant: int in groups:
		if not sprite_shapes.has(variant):
			if not templates.has(variant): templates[variant]=Actors.mesh(models[choices[variant]])
			var bounds: AABB=templates[variant].mesh.get_aabb()
			var model: Dictionary=models[choices[variant]]
			var rect: Array=imposters["entries"][model["imposter_index"]]["rect"]
			var height := bounds.size.y*0.003*0.8
			sprite_shapes[variant]={"width":height*float(rect[2])/float(rect[3]),"height":height,"center":bounds.get_center().y*0.003,"rect":Vector4(float(rect[0])/texture_size.x,float(rect[1])/texture_size.y,float(rect[2])/texture_size.x,float(rect[3])/texture_size.y)}
		var shape: Dictionary=sprite_shapes[variant]
		for point: Vector3 in groups[variant]:
			var offset := index_*stride
			buffer[offset]=shape["width"]
			buffer[offset+3]=point.x
			buffer[offset+5]=shape["height"]
			buffer[offset+7]=point.y+shape["center"]
			buffer[offset+10]=1
			buffer[offset+11]=point.z
			if multi.use_colors:
				for component in range(12,16): buffer[offset+component]=1.0
			for component in range(4): buffer[offset+stride-4+component]=shape["rect"][component]
			if state.has("tree_response") and point_cells.has(point):
				bindings.append({"cell":int(point_cells[point]),"index":index_,"point":point,"shape":shape})
			index_+=1
	multi.buffer=buffer
	var node := MultiMeshInstance3D.new()
	node.multimesh=multi
	node.material_override=imposter_material
	node.custom_aabb=multi.get_aabb().grow(3)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for entry: Dictionary in bindings:
		var point: Vector3=entry["point"]
		var shape: Dictionary=entry["shape"]
		var transform := Transform3D(Basis.from_scale(Vector3(shape["width"],shape["height"],1.0)),point+Vector3.UP*float(shape["center"]))
		bind_tree(int(entry["cell"]),multi,node,int(entry["index"]),tile,transform,float(shape["center"]))
	return node


func forget_tree_tile(key: Vector2i) -> void:
	for cell: int in tree_instances.keys():
		if tree_instances[cell]["tile"]==key: tree_instances.erase(cell); tree_motion.erase(cell)


func receive_trees() -> void:
	if tree_tick!=int(state["tick"]):
		tree_tick=int(state["tick"])
		tree_clock=tree_tick*0.1
		tree_between=0.0
	receive_tree_fires()
	var revision_: int=state["tree_response"]["revision"]
	if tree_response_revision==revision_: return
	tree_response_revision=revision_
	for key: String in state["tree_response"]["entries"]:
		var cell := int(key)
		if not tree_instances.has(cell): continue
		var entry: Dictionary=state["tree_response"]["entries"][key]
		if tree_instances[cell].get("response",{})==entry: continue
		tree_instances[cell]["response"]=entry
		tree_motion[cell]=true
	advance_trees(0.0)


func has_finger_trees() -> bool:
	return state.get("opening",{}).get("definition",{}).has("finger_of_god")


func receive_tree_fires() -> void:
	var opening: Dictionary=state["opening"]
	var fires: Dictionary=opening.get("finger_fires",{})
	var charred: Dictionary=opening.get("finger_burned",{})
	if tree_fires==fires and charred_trees==charred: return
	for key: String in tree_fires.keys()+fires.keys()+charred_trees.keys()+charred.keys():
		var cell := int(key)
		if tree_instances.has(cell) and (tree_fires.get(key)!=fires.get(key) or charred_trees.get(key)!=charred.get(key)):
			tree_motion[cell]=true
	tree_fires=fires
	charred_trees=charred


func bind_tree(cell: int,multi: MultiMesh,node: MultiMeshInstance3D,index_: int,tile: Vector2i,transform: Transform3D,center: float) -> void:
	tree_instances[cell]={"multi":multi,"node":node,"index":index_,"tile":tile,"base":transform,"center":center,
		"transform":transform,"planted_tick":planted_ticks.get(cell,-1),"response":state["tree_response"]["entries"].get(str(cell),{})}
	node.custom_aabb=node.custom_aabb.merge(AABB(transform.origin-Vector3.ONE*5,Vector3.ONE*10))
	tree_motion[cell]=true
	advance_tree(cell)


func advance_trees(delta: float) -> void:
	if tree_motion.is_empty(): return
	tree_between=minf(0.1,tree_between+delta)
	for cell: int in tree_motion.keys(): advance_tree(cell)


func advance_tree(cell: int) -> void:
	var entry: Dictionary=tree_instances[cell]
	var response: Dictionary=entry["response"]
	var config: Dictionary=state["opening"]["definition"]["tree_response_config"]
	var now := tree_clock+tree_between
	var changed := float(response.get("changed_ms",0.0))
	var enabled: bool=response.get("enabled",true)
	var scale_ := TreeAnimation.scale_at(config,enabled,now,changed)
	var vertical_offset := 0.0
	var emerging := false
	if enabled and int(entry["planted_tick"])>=0:
		var forest: Dictionary=state["opening"]["definition"]["god_seed"]
		var growth := clampf((now-float(entry["planted_tick"])*0.1)/float(forest["emerge_seconds"]),0.0,1.0)
		emerging=growth<1.0
		scale_=TreeAnimation.f32((scale_*0.8+0.2)*growth)
		if bool(forest["rise"]): vertical_offset=-float(forest["sink_distance"])*(1.0-growth)
	var fire_active := tree_fires.has(str(cell))
	if entry["multi"].use_colors:
		var rules: Dictionary=state["opening"]["definition"]["finger_of_god"]
		var charred := 1.0 if charred_trees.has(str(cell)) else 0.0
		if fire_active:
			charred=clampf(1.0-(float(tree_fires[str(cell)])*0.1-now)*float(rules["burn_rate"]),0.0,1.0)
		var tint := 1.0-charred*float(rules["burn_tint"])
		if entry.get("tint",1.0)!=tint:
			entry["multi"].set_instance_color(int(entry["index"]),Color(tint,tint,tint))
			entry["tint"]=tint
		if entry["multi"].use_custom_data: scale_*=lerpf(1.0,float(rules["burn_imposter_scale"]),charred)
	var transform: Transform3D=entry["base"]
	transform.basis=transform.basis.scaled(Vector3.ONE*scale_)
	transform.origin.y+=float(entry["center"])*(scale_-1.0)+vertical_offset
	entry["multi"].set_instance_transform(int(entry["index"]),transform)
	entry["transform"]=transform
	entry["scale"]=scale_
	entry["vertical_offset"]=vertical_offset
	if not enabled or not fire_active and not emerging and now-changed/1000.0>=float(config["duration"]): tree_motion.erase(cell)
