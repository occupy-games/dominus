extends RefCounted


static func rules(executable_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/building-foundation.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or not data.get("rules") is Dictionary: return {}
	var result: Dictionary=data["rules"].duplicate(true)
	# These original double constants are all promoted float32 values. Preserve
	# their exact values through the engine's decimal JSON parser.
	for key: String in ["half","inset","tolerance"]:
		if not (result.get(key) is int or result.get(key) is float): return {}
		result[key]=preload("res://simulation/source_terrain.gd").f32(float(result[key]))
	return result if preload("res://simulation/source_building_foundation.gd").valid_rules(result) else {}
