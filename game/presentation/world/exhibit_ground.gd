extends RefCounted
## Smooth source-palette original game terrain and original ocean shader textures.

static var land_material: ShaderMaterial
static var water_material: ShaderMaterial


static func material(water: bool) -> ShaderMaterial:
	if water and water_material != null: return water_material
	if not water and land_material != null: return land_material
	var result := ShaderMaterial.new()
	result.shader = load("res://presentation/world/source_water.gdshader" if water else "res://presentation/world/source_land.gdshader")
	result.set_shader_parameter("palette", load("res://assets/extracted/sprites/colours_DNA.png"))
	if water:
		result.set_shader_parameter("ocean", load("res://assets/extracted/sprites/OceanComposite.tga"))
		water_material = result
	else:
		land_material = result
	return result


static func terrain_material() -> ShaderMaterial:
	var result := material(false).duplicate() as ShaderMaterial
	result.set_shader_parameter("use_vertex_color", true)
	return result


static func translucent_water(alpha: float) -> ShaderMaterial:
	var result := material(true).duplicate() as ShaderMaterial
	result.shader=load("res://presentation/world/source_water_translucent.gdshader")
	result.set_shader_parameter("opacity", alpha)
	return result


static func patch(kind: String, size: Vector2, height: float = -0.03) -> Node3D:
	var root := Node3D.new()
	root.set_meta("environment", kind)
	var plane := PlaneMesh.new()
	plane.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position.y = height
	mesh.material_override = material(kind in ["water", "underwater", "shore"])
	if kind == "underwater": mesh.material_override = translucent_water(0.38)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	if kind == "shore":
		var land := MeshInstance3D.new()
		var half := PlaneMesh.new()
		half.size = Vector2(size.x,size.y*0.5)
		land.mesh = half
		land.position = Vector3(0,height+0.008,size.y*0.25)
		land.material_override = material(false)
		root.add_child(land)
		var beach := MeshInstance3D.new()
		var strip := PlaneMesh.new()
		strip.size = Vector2(size.x,minf(0.6,size.y*0.1))
		beach.mesh = strip
		beach.position.y = height+0.012
		var sand := material(false).duplicate() as ShaderMaterial
		sand.set_shader_parameter("palette_pixel",Vector2(54,41))
		beach.material_override = sand
		root.add_child(beach)
	return root
