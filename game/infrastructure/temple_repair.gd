extends RefCounted


static func load_rules(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-repair.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	return data["rules"] if preload("res://simulation/source_temple_repair.gd").valid_rules(data.get("rules")) else {}
