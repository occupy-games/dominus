extends RefCounted


static func load_rules(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/influence-rules.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	return data["rules"].duplicate(true) if preload("res://simulation/source_influence.gd").valid_rules(data.get("rules")) else {}
