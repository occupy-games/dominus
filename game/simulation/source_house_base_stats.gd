extends RefCounted
## Original 0x100b6750 selects the base stat row before active modifiers.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")
const ATTACHED_FIELDS := ["capacity","breeder count","min belief","max belief","birth rate"]


static func valid(content: Variant) -> bool:
	if not content is Dictionary or not content.get("rows") is Array or not content.get("rules") is Dictionary:
		return false
	var rows: Array=content["rows"]
	if rows.is_empty() or rows.size()>64:
		return false
	for index in range(rows.size()):
		var row: Variant=rows[index]
		if not row is Dictionary or row.get("index")!=index or not row.get("id") is String or not row.get("values") is Dictionary:
			return false
		for value: Variant in row["values"].values():
			if not (value is int or value is float) or not is_finite(float(value)):
				return false
		for field: String in ["build time","new builder contribution"]:
			if not Membership.source_float(row["values"].get(field)):
				return false
	var rules: Dictionary=content["rules"]
	if not rules.get("kind_slots") is Array or rules["kind_slots"].size()!=10 or not Numbers.integer_between(rules.get("default_slot"),0,5):
		return false
	for slot: Variant in rules["kind_slots"]:
		if not Numbers.integer_between(slot,0,5):
			return false
	if not rules.get("settlement_rows") is Array or rules["settlement_rows"].size()!=6:
		return false
	for index: Variant in rules["settlement_rows"]:
		if not Numbers.integer_between(index,-1,rows.size()-1):
			return false
	if not rules.get("overrides") is Array or rules["overrides"].size()!=5:
		return false
	var names := {}
	for binding: Variant in rules["overrides"]:
		if not binding is Dictionary or binding.get("name") not in ATTACHED_FIELDS or names.has(binding["name"]):
			return false
		names[binding["name"]]=true
	return true


static func resolve(content: Dictionary,house_index: int,attachment: Variant=null) -> Dictionary:
	# The content has already been validated at load or restore. An attached
	# lookup ignores the stored house index, even when that index is stale.
	var rows: Array=content["rows"]
	if attachment==null:
		return rows[house_index].duplicate(true) if house_index>=0 and house_index<rows.size() else {}
	if not attachment is Dictionary or not Numbers.integer_between(attachment.get("kind"),0,4294967295) or not attachment.get("values") is Dictionary:
		return {}
	var kind := int(attachment["kind"])
	var rules: Dictionary=content["rules"]
	var slot := int(rules["kind_slots"][kind] if kind<rules["kind_slots"].size() else rules["default_slot"])
	var index := int(rules["settlement_rows"][slot])
	if index<0:
		return {}
	var row: Dictionary=rows[index].duplicate(true)
	for binding: Dictionary in rules["overrides"]:
		var field: String=binding["name"]
		var value: Variant=attachment["values"].get(field)
		if not Membership.source_float(value):
			return {}
		row["values"][field]=float(value)
	return row
