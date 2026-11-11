extends RefCounted


static func content(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-effects.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	if not preload("res://simulation/source_temple_effects.gd").valid_content(data): return {}
	if not preload("res://simulation/source_temple_propagation.gd").valid_rules(data.get("propagation_rules")): return {}
	return {"records":data["records"].duplicate(true),"row_words":data["row_words"].duplicate(true),"monastery_types":data["monastery_types"].duplicate(true),"propagation_rules":data["propagation_rules"].duplicate(true)}
