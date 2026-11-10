extends RefCounted


static func load_rules(executable_sha256: String) -> Dictionary:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/target-references.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("executable_sha256")!=executable_sha256: return {}
	return metadata["rules"] if preload("res://simulation/source_target_references.gd").valid_rules(metadata.get("rules")) else {}
