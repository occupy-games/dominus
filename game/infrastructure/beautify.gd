extends RefCounted


static func rules(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/beautify.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256:
		return {}
	var result: Variant=data.get("rules")
	return result if result is Dictionary and result.has("timer") and preload("res://simulation/source_beautify.gd").valid_rules(result) else {}
