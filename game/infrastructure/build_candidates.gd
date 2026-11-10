extends RefCounted


static func load_values(executable_sha256: String,source_sha256: String,table_sha256: String) -> Dictionary:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/build-candidates.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("executable_sha256")!=executable_sha256 or metadata.get("source_sha256")!=source_sha256 or metadata.get("table_sha256")!=table_sha256: return {}
	return metadata["values"] if preload("res://simulation/source_build_candidates.gd").valid_values(metadata.get("values")) else {}
