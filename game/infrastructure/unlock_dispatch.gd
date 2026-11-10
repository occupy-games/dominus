extends RefCounted


static func content(executable_sha256: String,source_sha256: String,scope: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/unlock-dispatch.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	var source: Variant=data.get("scopes",{}).get(scope)
	var Unlocks = preload("res://simulation/source_unlock_dispatch.gd")
	if not source is Dictionary or not Unlocks.valid_rules(data.get("rules")) or not source.get("dependencies") is Array: return {}
	var dependencies: Array=preload("res://simulation/progression.gd").canonical_numbers(source["dependencies"])
	if Unlocks.prepare(dependencies).is_empty(): return {}
	return {"rules":preload("res://simulation/progression.gd").canonical_numbers(data["rules"]),"dependencies":dependencies}
