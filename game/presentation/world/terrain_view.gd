extends MeshInstance3D
## Small worlds rebuild directly. Large maps stream cached CPU-generated tiles.

const STEP := 0.3
const TILE := 64
const Ground = preload("res://presentation/world/exhibit_ground.gd")
const Geometry = preload("res://presentation/world/terrain_geometry.gd")
const LandEffectTexture = preload("res://presentation/world/land_effect_texture.gd")
var colors: Array[Color] = []
var detail_texture: Texture2D
var view_region := Rect2i()
var bevel_segments := 4
var sample_stride := 1
var chunks: Dictionary = {}
var pending: Array[Vector2i] = []
var source: Dictionary = {}
var worker := Thread.new()
var active_key := Vector2i()
var active_generation := -1
var generation := 0
var revision := -1
var detail := -1
var shared_material: ShaderMaterial
var hazard_material: ShaderMaterial
var hazard_texture: ImageTexture
var hazard_revision := -1
var land_effect_fields: Array = []
var land_effect_width := 0
var land_effect_texture: ImageTexture
var blight_fields: Array = [{},{}]
var blight_texture: ImageTexture


func terrain_material() -> ShaderMaterial:
	if shared_material==null:
		shared_material=Ground.terrain_material()
	return shared_material


func apply_land_effects(state: Dictionary) -> void:
	var width := int(state["width"])
	var fields := LandEffectTexture.fields_for(state)
	if width==land_effect_width and fields==land_effect_fields:
		return
	land_effect_width=width
	land_effect_fields=fields
	var image := LandEffectTexture.image_for(width,fields)
	if image==null:
		if land_effect_texture!=null:
			shared_material.set_shader_parameter("beautify_enabled",false)
			shared_material.set_shader_parameter("beauty_field",null)
			shared_material.set_shader_parameter("beautify_detail",null)
			land_effect_texture=null
		return
	var material := terrain_material()
	if land_effect_texture==null or land_effect_texture.get_width()!=width:
		var detail_mask := load("res://assets/extracted/sprites/GemDiffuse.tga") as Texture2D
		if detail_mask==null:
			return
		land_effect_texture=ImageTexture.create_from_image(image)
		material.set_shader_parameter("beauty_field",land_effect_texture)
		material.set_shader_parameter("beautify_detail",detail_mask)
		material.set_shader_parameter("beauty_width",float(width))
		material.set_shader_parameter("beautify_enabled",true)
	else:
		land_effect_texture.update(image)


func apply_voyage(state: Dictionary) -> void:
	if not state.has("voyage"): return
	if hazard_material==null:
		hazard_material=Ground.terrain_material()
		hazard_material.set_shader_parameter("voyage_hazards_enabled",true)
		hazard_material.set_shader_parameter("blight_gradient",load("res://assets/extracted/sprites/GradMap_Swamp.tga"))
		hazard_material.set_shader_parameter("voyage_width",float(state["width"]))
		material_override=hazard_material
		shared_material=hazard_material
	var voyage: Dictionary = state["voyage"]
	if hazard_revision==int(voyage.get("land_revision",0)): return
	hazard_revision=int(voyage.get("land_revision",0))
	var width := int(state["width"])
	var bytes := PackedByteArray()
	bytes.resize(width*width*3)
	for i in range(width*width):
		bytes[i*3]=voyage["blight"][i]
		bytes[i*3+1]=voyage["swamp"][i]
		bytes[i*3+2]=voyage["beauty"][i]
	var image := Image.create_from_data(width,width,false,Image.FORMAT_RGB8,bytes)
	if hazard_texture==null: hazard_texture=ImageTexture.create_from_image(image)
	else: hazard_texture.update(image)
	hazard_material.set_shader_parameter("voyage_hazards",hazard_texture)


func apply_blight(state: Dictionary) -> void:
	if not state.has("opening"): return
	var fields: Dictionary=state.get("source_influence",{}).get("raster",{}).get("fields",{})
	var dry: Dictionary=fields.get("2",{})
	var swamp: Dictionary=fields.get("3",{})
	if dry==blight_fields[0] and swamp==blight_fields[1]: return
	blight_fields=[dry,swamp]
	var field:=swamp.duplicate()
	for tile: String in dry:
		if not swamp.has(tile):
			field[tile]=dry[tile]
			continue
		var bytes: PackedByteArray=dry[tile].duplicate()
		var wet: PackedByteArray=swamp[tile]
		for i in range(bytes.size()): bytes[i]=maxi(bytes[i],wet[i])
		field[tile]=bytes
	var width: int=state["width"]
	var image:=LandEffectTexture.image_for(width,[field,{},{}])
	var material:=terrain_material()
	if image==null:
		material.set_shader_parameter("blight_enabled",false)
		return
	if blight_texture==null or blight_texture.get_width()!=width:
		blight_texture=ImageTexture.create_from_image(image)
		material.set_shader_parameter("blight_field",blight_texture)
		material.set_shader_parameter("blight_width",float(width))
		material.set_shader_parameter("blight_gradient",load("res://assets/extracted/sprites/GradMap_Swamp.tga"))
	else: blight_texture.update(image)
	material.set_shader_parameter("blight_enabled",true)


func rebuild(state: Dictionary, force: bool = false) -> void:
	if int(state["width"]) <= 64:
		mesh = make_mesh(Geometry.build(state,view_region,colors))
		material_override=terrain_material()
		return
	source = {"width":state["width"],"terrain":state["terrain"]}
	if force or revision != int(state["terrain_revision"]) or detail != bevel_segments*100+sample_stride:
		revision = int(state["terrain_revision"])
		detail = bevel_segments*100+sample_stride
		generation += 1
		# Keep the old tiles visible until their replacements arrive.
		for node: MeshInstance3D in chunks.values(): node.set_meta("generation",-1)
	update_tiles()
	set_process(true)


func update_tiles() -> void:
	if source.is_empty(): return
	var wanted: Array[Vector2i] = []
	for z in range(floori(view_region.position.y/float(TILE)), ceili(view_region.end.y/float(TILE))):
		for x in range(floori(view_region.position.x/float(TILE)), ceili(view_region.end.x/float(TILE))):
			wanted.append(Vector2i(x,z))
	for key: Vector2i in chunks.keys(): chunks[key].visible = key in wanted
	if chunks.size() > maxi(96,wanted.size()*2):
		for key: Vector2i in chunks.keys():
			if key not in wanted:
				chunks[key].queue_free()
				chunks.erase(key)
	pending.clear()
	for key: Vector2i in wanted:
		if chunks.has(key) and chunks[key].get_meta("generation") == generation: continue
		if worker.is_started() and key == active_key and active_generation == generation: continue
		pending.append(key)
	var center := Vector2(view_region.get_center())/TILE
	pending.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return Vector2(a).distance_squared_to(center)<Vector2(b).distance_squared_to(center))


static func make_mesh(arrays: Array) -> ArrayMesh:
	var result := ArrayMesh.new()
	if not arrays.is_empty(): result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result


func _process(_delta: float) -> void:
	if worker.is_started():
		if worker.is_alive(): return
		var arrays: Array = worker.wait_to_finish()
		if active_generation == generation:
			if not chunks.has(active_key):
				var node := MeshInstance3D.new()
				node.material_override=terrain_material()
				add_child(node)
				chunks[active_key] = node
			chunks[active_key].mesh = make_mesh(arrays)
			chunks[active_key].set_meta("generation",generation)
			chunks[active_key].visible = view_region.intersects(Rect2i(active_key*TILE,Vector2i.ONE*TILE))
	if pending.is_empty(): return
	active_key = pending.pop_front()
	active_generation = generation
	var region := Rect2i(active_key*TILE,Vector2i.ONE*TILE).intersection(Rect2i(0,0,source["width"]-1,source["width"]-1))
	worker.start(Geometry.build.bind(source,region,colors,bevel_segments,sample_stride))


func is_streaming() -> bool:
	return worker.is_started() or not pending.is_empty()


func _exit_tree() -> void:
	if worker.is_started(): worker.wait_to_finish()
