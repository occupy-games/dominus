extends RefCounted


static func load_rules(executable_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-terrain.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256: return {}
	return preload("res://simulation/progression.gd").canonical_numbers(data["rules"]) if preload("res://simulation/source_temple_terrain.gd").valid_rules(data.get("rules")) else {}


static func footprint_rules(executable_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-terrain.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256: return {}
	return data["footprint_rules"] if preload("res://simulation/source_temple_footprint.gd").valid_rules(data.get("footprint_rules")) else {}


static func frame_rules(executable_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-terrain.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256: return {}
	return data["frame_rules"] if preload("res://simulation/source_temple_frame.gd").valid_rules(data.get("frame_rules")) else {}
