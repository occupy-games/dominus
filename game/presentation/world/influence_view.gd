extends Node
## A small runtime geometry-parameter texture supplies the same simulation
## circles to all world shaders. No new artwork is generated.

var preference_tint := Vector3(-1,-1,-1)
var registered := false
var revision := -1
var color_value := Vector3(-1,-1,-1)
var overlays: Dictionary = {}
var shader := preload("res://presentation/world/influence_overlay.gdshader")
var regions_texture: ImageTexture


func apply_snapshot(state: Dictionary,world: Node) -> void:
	var p: Dictionary = state.get("progression",{})
	if state.has("voyage"):
		p={"influence_enabled":not state["voyage"].get("areas",[]).is_empty(),"influence_revision":state["voyage"].get("land_revision",0),"influence":[],"rules":{"config":state["voyage"].get("config",{})}}
		for area: Dictionary in state["voyage"].get("areas",[]):
			if area["enabled"]: p["influence"].append(area)
	var enabled: bool = p.get("influence_enabled",false)
	RenderingServer.global_shader_parameter_set("god_influence_enabled",enabled)
	if not enabled: return
	RenderingServer.global_shader_parameter_set("god_world_center",(int(state["width"])-1)*0.5)
	if revision!=int(p.get("influence_revision",0)):
		revision=int(p.get("influence_revision",0))
		var image := Image.create(32,1,false,Image.FORMAT_RGBAF)
		var areas: Array = p.get("influence",[])
		var lower := Vector2.INF
		var upper := -Vector2.INF
		for area: Dictionary in areas:
			lower=lower.min(Vector2(area["x"],area["z"])-Vector2.ONE*float(area["radius"]))
			upper=upper.max(Vector2(area["x"],area["z"])+Vector2.ONE*float(area["radius"]))
		RenderingServer.global_shader_parameter_set("god_influence_bounds",Vector4(lower.x,lower.y,upper.x,upper.y))
		for index in range(mini(32,areas.size())):
			var area: Dictionary = areas[index]
			image.set_pixel(index,0,Color(area["x"],area["z"],area["radius"],1))
		regions_texture=ImageTexture.create_from_image(image)
		RenderingServer.global_shader_parameter_set("god_influence_regions",regions_texture)
		RenderingServer.global_shader_parameter_set("god_influence_count",mini(32,areas.size()))
	var config: Dictionary = p["rules"]["config"]
	var next_color := Vector3(float(config.get("OutOfRange.x",0.67)),float(config.get("OutOfRange.y",0.79)),float(config.get("OutOfRange.z",0.81)))
	if preference_tint.x>=0: next_color=preference_tint
	if next_color!=color_value:
		color_value=next_color
		RenderingServer.global_shader_parameter_set("god_out_of_range",color_value)
	if not registered:
		registered=true
		attach_overlays(world)


func attach_overlays(node: Node) -> void:
	if node is GeometryInstance3D and not node.has_meta("influence_registered"):
		node.set_meta("influence_registered",true)
		var material: Material = node.material_override
		if material is StandardMaterial3D and material.albedo_texture!=null and material.transparency!=BaseMaterial3D.TRANSPARENCY_ALPHA:
			var key: String = material.albedo_texture.resource_path+str(material.transparency)
			if not overlays.has(key):
				var overlay := ShaderMaterial.new()
				overlay.shader=shader
				overlay.set_shader_parameter("original_texture",material.albedo_texture)
				overlay.set_shader_parameter("alpha_scissor",material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
				overlays[key]=overlay
			node.material_override=overlays[key]
	for child: Node in node.get_children(): attach_overlays(child)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("god_influence_enabled",false)
