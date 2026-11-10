extends RefCounted


static func content(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-membership.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	if not preload("res://simulation/source_temple_membership.gd").valid_rules(data.get("rules")) or not data.get("radii") is Dictionary: return {}
	for value: Variant in data["radii"].values():
		if not preload("res://simulation/source_temple_membership.gd").source_float(value): return {}
	return {"rules":data["rules"].duplicate(true),"radii":data["radii"].duplicate(true)}
