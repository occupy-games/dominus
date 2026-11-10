extends RefCounted
## Repeated source rows are alternatives. Unknown script/level keys stay locked.


static func enabled(progression: Dictionary, unlock: String) -> bool:
	if progression.get("script_unlocks",{}).has(unlock): return bool(progression["script_unlocks"][unlock])
	for condition: String in progression["rules"].get("source_unlocks",{}).get(unlock,[]):
		if condition=="always": return true
		if condition=="never": continue
		if condition.begins_with("TEMPLE_COMPLETE_"):
			if preload("res://simulation/temple_rules.gd").completed(progression,condition.trim_prefix("TEMPLE_COMPLETE_")): return true
			continue
		if progression.get("script_unlocks",{}).has(condition):
			if bool(progression["script_unlocks"][condition]): return true
			continue
		if condition.ends_with("_COMPLETED"):
			if owns(progression,condition.trim_suffix("_COMPLETED"),"completed"): return true
		elif owns(progression,condition,"discovered"): return true
	return false


static func owns(progression: Dictionary,id: String, collection: String) -> bool:
	if id in progression[collection]: return true
	for binding: String in progression["rules"].get("card_bindings",{}).get(id,[]):
		if binding in progression[collection]: return true
	return false
