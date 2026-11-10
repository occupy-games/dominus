extends RefCounted


static func content(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/reward-queue.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256: return {}
	if not preload("res://simulation/source_reward_queue.gd").valid_rules(data.get("rules")): return {}
	return preload("res://simulation/progression.gd").canonical_numbers({"rules":data["rules"],"special":data["special"]})
