extends RefCounted


static func load_rules(executable_sha256: String,source_sha256: String) -> Dictionary:
	var content: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/sticker-selection.json"))
	if not content is Dictionary or content.get("version")!=1 or content.get("executable_sha256")!=executable_sha256 or content.get("source_sha256")!=source_sha256: return {}
	var rules: Variant=content.get("rules")
	return rules if preload("res://simulation/source_sticker_selection.gd").valid_rules(rules) else {}


static func bound_rules(executable_sha256: String,source_sha256: String) -> Dictionary:
	var rules := load_rules(executable_sha256,source_sha256)
	if rules.is_empty(): return {}
	rules=rules.duplicate(true)
	var Hash = preload("res://simulation/source_hash.gd")
	for i in range(rules["rare_rewards"].size()): rules["rare_rewards"][i]=Hash.text(rules["rare_rewards"][i])
	rules["gem_reward"]=Hash.text(rules["gem_reward"])
	rules["kinds"]={}
	for kind: String in preload("res://simulation/source_sticker_selection.gd").KINDS: rules["kinds"]["@"+str(Hash.text(kind))]=kind
	return rules
