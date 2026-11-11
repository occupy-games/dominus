extends RefCounted


static func records(executable_sha256: String,source_sha256: String) -> Array:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-modifiers.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return []
	if not preload("res://simulation/source_temple_modifiers.gd").valid_records(data.get("records")): return []
	return data["records"].duplicate(true)
