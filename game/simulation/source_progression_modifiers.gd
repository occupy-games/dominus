extends RefCounted
## Live floats written by the original ordered unlock descriptor pass.

const Membership = preload("res://simulation/source_temple_membership.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("defaults") is Dictionary or not rules.get("descriptors") is Array:
		return false
	if rules["descriptors"].size()!=15 or rules["defaults"].size()!=14:
		return false
	var names := {}
	var fields := {}
	for row: Variant in rules["descriptors"]:
		if not row is Dictionary or not row.get("unlock") is String or not row.get("field") is String:
			return false
		if row["unlock"].is_empty() or names.has(row["unlock"]) or not Membership.source_float(row.get("value")):
			return false
		if not Membership.source_float(rules["defaults"].get(row["field"])):
			return false
		names[row["unlock"]]=true
		fields[row["field"]]=true
	return fields.size()==14 and fields.has("build_time") and fields.has("farm_build_time")


static func initial(rules: Dictionary) -> Dictionary:
	return rules["defaults"].duplicate() if valid_rules(rules) else {}


static func valid(state: Variant,rules: Dictionary) -> bool:
	if not state is Dictionary or state.size()!=rules["defaults"].size():
		return false
	for field: String in rules["defaults"]:
		if not Membership.source_float(state.get(field)):
			return false
	return true


static func refresh(state: Dictionary,rules: Dictionary,unlocked: Callable) -> bool:
	if not valid_rules(rules) or not valid(state,rules) or not unlocked.is_valid():
		return false
	for row: Dictionary in rules["descriptors"]:
		if unlocked.call(row["unlock"]):
			state[row["field"]]=float(row["value"])
	return true


static func reset(state: Dictionary,rules: Dictionary) -> bool:
	if not valid_rules(rules) or not valid(state,rules):
		return false
	state.merge(rules["defaults"],true)
	return true
