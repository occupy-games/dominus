extends RefCounted


static func read_definition(executable_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-terrain-frame.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256:
		return {}
	return data


static func rules(executable_sha256: String) -> Dictionary:
	var data := read_definition(executable_sha256)
	if not data.get("rules") is Dictionary:
		return {}
	var result: Dictionary=data["rules"].duplicate(true)
	for key: String in ["ordinary_seconds","attached_seconds","forced_rate","other_phase_rate"]:
		if not (result.get(key) is int or result.get(key) is float): return {}
		result[key]=preload("res://simulation/source_terrain.gd").f32(float(result[key]))
	return result if preload("res://simulation/source_house_terrain_frame.gd").valid_rules(result) else {}


static func modifiers(executable_sha256: String) -> Dictionary:
	var data := read_definition(executable_sha256)
	if not data.get("modifiers") is Dictionary:
		return {}
	var result: Dictionary=data["modifiers"]
	if not result.get("descriptors") is Array:
		return {}
	for row: Variant in result["descriptors"]:
		if not row is Dictionary or not (row.get("value") is float or row.get("value") is int):
			return {}
		row["value"]=preload("res://simulation/source_terrain.gd").f32(float(row["value"]))
	return result if preload("res://simulation/source_progression_modifiers.gd").valid_rules(result) else {}
