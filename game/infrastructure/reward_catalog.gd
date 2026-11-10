extends RefCounted


static func content(executable_sha256: String,source_sha256: String,scope: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/reward-catalog.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	var source: Variant=data.get("scopes",{}).get(scope)
	if not source is Dictionary or not source.get("available",false): return {}
	var records := {"packs":data.get("packs"),"stickers":data.get("stickers"),"cards":source.get("cards")}
	var Catalog = preload("res://simulation/source_reward_catalog.gd")
	if not Catalog.valid_rules(data.get("rules")) or not Catalog.valid_input(records,data.get("details")): return {}
	return preload("res://simulation/progression.gd").canonical_numbers({"records":records,"details":data["details"],"rules":data["rules"]})
