extends RefCounted


static func load_content(executable_sha256: String,source_sha256: String) -> Dictionary:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/action-sequences.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("executable_sha256")!=executable_sha256 or metadata.get("source_sha256")!=source_sha256: return {}
	if not preload("res://simulation/source_action_sequence.gd").valid_content(metadata): return {}
	return {"rules":metadata["rules"],"default_state":metadata["default_state"],"actions":metadata["actions"]}
