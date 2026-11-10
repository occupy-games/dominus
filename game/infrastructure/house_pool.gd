extends RefCounted


static func load_rules(executable_sha256: String) -> Dictionary:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-pool.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("executable_sha256")!=executable_sha256: return {}
	var rules: Variant=metadata.get("rules")
	if not rules is Dictionary or not preload("res://simulation/source_plot_schedule.gd").integer_between(rules.get("capacity"),1,65535): return {}
	return {"capacity":int(rules["capacity"])}
