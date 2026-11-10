extends RefCounted
## Instantiates recovered original game meshes. No generated replacement geometry.
const SourceMaterial = preload("res://presentation/world/source_material.gd")


static func mesh(data: Dictionary) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for point: Array in data["vertices"]: vertices.append(Vector3(point[0], point[1], point[2]))
	for normal: Array in data["normals"]: normals.append(Vector3(normal[0], normal[1], normal[2]).normalized())
	for uv: Array in data["uvs"]: uvs.append(Vector2(uv[0], uv[1]))
	for index: int in data["indices"]: indices.append(index)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var original_mesh := ArrayMesh.new()
	original_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = original_mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = data.get("texture_resource")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if data.get("has_alpha", false):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	node.material_override = material
	if data.get("source_shader") == "shdrTree":
		node.material_override = SourceMaterial.tree(data)
	node.set_meta("source_resource", data["resource_id"])
	return node


static func tree(assets: Dictionary, variant: int) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * 0.003
	var choices: Array = assets.get("standing", [])
	if not choices.is_empty():
		root.add_child(mesh(assets["models"][choices[variant % choices.size()]]))
	root.set_meta("source", assets.get("source", ""))
	return root


static func home(assets: Dictionary, font: Font) -> Node3D:
	var root := Node3D.new()
	var building := Node3D.new()
	building.name = "Building"
	building.scale = Vector3.ONE * 0.003
	root.add_child(building)
	if not assets.is_empty():
		var base := mesh(assets["models"][int(assets["base"])])
		base.name = "Complete"
		building.add_child(base)
		for data: Dictionary in assets["models"]:
			if int(data["resource_id"]) == 0x89611233: # source scaffolds, HouseModels.h
				var scaffolds := mesh(data)
				scaffolds.name = "Scaffolds"
				building.add_child(scaffolds)
	root.set_meta("source", assets.get("source", ""))
	var label := Label3D.new()
	label.name = "Indicator"
	label.position.y = 1.7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = font
	label.font_size = 38
	label.pixel_size = 0.009
	root.add_child(label)
	return root
