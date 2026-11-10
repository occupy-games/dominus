extends RefCounted
## Original reward binding and limit registration. Detail references are source
## row indices, never assets or pointers; the fallback is represented by -1.

const Availability = preload("res://simulation/source_availability.gd")
const Research = preload("res://simulation/source_card_research.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const MASK := 4294967295
const GROUPS := ["packs","stickers","cards"]


static func valid_rules(rules: Variant) -> bool:
	return rules is Dictionary and rules.get("capacity")==256 and Numbers.integer_between(rules.get("standard_limit"),0,MASK)


static func valid_input(records: Variant,details: Variant) -> bool:
	if not records is Dictionary or not details is Dictionary: return false
	for group: String in GROUPS:
		if not records.get(group) is Array or records[group].size()>256 or not details.get(group) is Array or details[group].size()>256: return false
		for id: Variant in details[group]:
			if not Numbers.integer_between(id,0,MASK): return false
		for row: Variant in records[group]:
			if not row is Dictionary or not Numbers.integer_between(row.get("id"),0,MASK): return false
			if group=="cards" and (not Research.valid_card(row) or not Numbers.integer_between(row.get("max_collectable"),-2147483648,2147483647)): return false
			if group=="stickers" and not Research.valid_sticker(row): return false
			if group=="packs":
				if not row.get("slots") is Array or row["slots"].size()!=5: return false
				for slot: Variant in row["slots"]:
					if not slot is Dictionary or not Numbers.integer_between(slot.get("count"),-2147483648,2147483647) or not Numbers.integer_between(slot.get("reward"),0,MASK): return false
	return true


static func reset(row: Dictionary,group: String) -> void:
	row["id"]=0
	row["name"]=""
	match group:
		"packs":
			row["type"]=MASK
			for slot: Dictionary in row["slots"]: slot.merge({"count":0,"reward":0},true)
		"stickers":
			row.merge({"internal":true,"era":MASK,"categories":[0,0],"counts":[0,0]},true)
			if row.has("category"): row["category"]=0
			if row.has("count"): row["count"]=0
		"cards": row.merge({"type":4,"reward_type":4,"category":0,"research_needed":0},true)


static func bind(availability: Dictionary,records: Dictionary,details: Dictionary,rules: Dictionary) -> Dictionary:
	if not Availability.valid(availability) or not valid_rules(rules) or not valid_input(records,details): return {}
	var result := {"records":records.duplicate(true),"registry":{},"details":{}}
	for group: String in GROUPS:
		var info := {}
		for index in range(details[group].size()):
			var id := int(details[group][index])
			if id!=0: info[Availability.key(id)]=index
		result["details"][group]=info
		var registry := {}
		for index in range(result["records"][group].size()):
			var row: Dictionary=result["records"][group][index]
			var id := int(row["id"])
			row["detail_index"]=-1
			if group=="stickers": row["slot_08"]=1
			if id==0:
				reset(row,group)
				continue
			registry[Availability.key(id)]=index
			var limit := (int(row["max_collectable"])&MASK) if group=="cards" else int(rules["standard_limit"])
			Availability.register(availability,id,limit,limit)
			row["detail_index"]=int(info.get(Availability.key(id),-1))
		result["registry"][group]=registry
	return result
