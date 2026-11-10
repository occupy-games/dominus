extends RefCounted


static func load_content(executable_sha256: String,source_sha256: String) -> Dictionary:
	var content: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/storm-chests.json"))
	if not content is Dictionary or content.get("version")!=1 or content.get("executable_sha256")!=executable_sha256 or content.get("source_sha256")!=source_sha256: return {}
	if not preload("res://simulation/source_storm_chests.gd").valid_rules(content.get("rules")) or not content.get("scopes") is Dictionary: return {}
	if not preload("res://simulation/source_chest_placement.gd").valid_rules(content.get("placement_rules")): return {}
	if not preload("res://simulation/source_chest_factory.gd").valid_rules(content.get("factory_rules")): return {}
	if not preload("res://simulation/source_chest_constructor.gd").valid_rules(content.get("core_rules")): return {}
	if not preload("res://simulation/source_chest_lifetime.gd").valid_rules(content.get("lifetime_rules")): return {}
	if not preload("res://simulation/source_availability.gd").valid_rules(content.get("availability_rules")): return {}
	for scope: Variant in content["scopes"].values():
		if not scope is Dictionary or not scope.get("available") is bool or not preload("res://simulation/source_storm_chests.gd").valid_areas(scope.get("areas")): return {}
	return content
