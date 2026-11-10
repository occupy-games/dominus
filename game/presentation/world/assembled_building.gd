extends Node3D
## A fixed source-coordinate assembly. Construction reveals anchored chunks;
## completed geometry replaces embedded chunks without drawing duplicate faces.

const Actors = preload("res://presentation/world/actors.gd")
var data: Dictionary
var components: Array = []
var source_bounds := AABB()
var completed := true
var revealed_parts := 0
var has_complete_shadow := false


func _ready() -> void:
	var first := true
	for component: Dictionary in data["components"]:
		if component["model"].is_empty(): continue
		var mesh := Actors.mesh(component["model"])
		if data.get("crop_shader",false) and not "shadow" in component["role"]:
			mesh.material_override=preload("res://presentation/world/source_material.gd").crops(component["model"])
			mesh.set_meta("crop_shader",true)
		var offset: Array = component["offset"]
		mesh.position = Vector3(offset[0], offset[1], offset[2])
		mesh.set_meta("role", component["role"])
		mesh.set_meta("source_model_id", component["model_id"])
		if "shadow" in component["role"]:
			var material := mesh.material_override as StandardMaterial3D
			if material != null:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		components.append({"node": mesh, "role": component["role"], "number": component["part_number"], "embedded": component.get("embedded_in_complete", false)})
		if component["role"] == "shadow": has_complete_shadow = true
		var bounds := mesh.mesh.get_aabb()
		bounds.position += mesh.position
		if not "shadow" in component["role"]:
			source_bounds = bounds if first else source_bounds.merge(bounds)
			first = false
	set_stage(0, true)


func set_stage(parts: int, complete: bool) -> void:
	revealed_parts = parts
	completed = complete
	for component: Dictionary in components:
		match component["role"]:
			"complete": component["node"].visible = complete
			"scaffold": component["node"].visible = not complete
			"part": component["node"].visible = (complete and not component["embedded"]) or (not complete and component["number"] <= parts)
			"shadow": component["node"].visible = complete
			"part_shadow": component["node"].visible = (complete and not has_complete_shadow) or (not complete and component["number"] <= parts)
			"scaffold_shadow": component["node"].visible = not complete


func maximum_part() -> int:
	var result := 0
	for component: Dictionary in components: result = maxi(result, int(component["number"]))
	return result
