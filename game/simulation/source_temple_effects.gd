extends RefCounted
## Original shrine mask collection and numeric stat queries. Rows are raw
## 32-bit words so hashes, flags and untouched source fields survive unchanged.
## These queries return detached values; they never mutate an actor or its base.

const Membership = preload("res://simulation/source_temple_membership.gd")
const Modifiers = preload("res://simulation/source_temple_modifiers.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")


static func valid_mask(mask: Variant) -> bool:
	return mask is Array and mask.size()==2 and Numbers.integer_between(mask[0],0,4294967295) and Numbers.integer_between(mask[1],0,4294967295)


static func valid_content(content: Variant) -> bool:
	if not content is Dictionary or not Modifiers.valid_records(content.get("records")) or not content.get("row_words") is Dictionary or content["row_words"].size()!=3: return false
	for table: String in ["race","jobs","House Values"]:
		var count := 41 if table=="race" else (16 if table=="jobs" else 76)
		if not Numbers.integer_between(content["row_words"].get(table),count,count): return false
	if not content.get("monastery_types") is Array or content["monastery_types"].size()!=6: return false
	for entry: Variant in content["monastery_types"]:
		if not entry is Dictionary or not Numbers.integer_between(entry.get("id"),0,4294967295): return false
	for record: Dictionary in content["records"]:
		var table: Variant=record.get("table")
		if not table is String or not content["row_words"].has(table): return false
		if int(record["family"])!=(1 if table=="House Values" else 0): return false
		if not Numbers.integer_between(record.get("index"),0,int(content["row_words"][table])-1) or not Numbers.integer_between(record.get("operation"),0,4294967295): return false
		if not Membership.source_float(record.get("value")): return false
		for flag: String in ["abode","monastery","farm","mine"]:
			if not Numbers.integer_between(record.get(flag),0,4294967295): return false
	return true


static func valid_sites(sites: Variant,owners: Variant) -> bool:
	if not Membership.valid_sites(sites) or not Membership.valid_owners(owners): return false
	for site: Dictionary in sites:
		if not Modifiers.valid(site): return false
	return true


static func word_float(word: int) -> float:
	var data := PackedByteArray(); data.resize(4); data.encode_u32(0,word)
	return data.decode_float(0)


static func float_word(value: float) -> int:
	var data := PackedByteArray(); data.resize(4); data.encode_float(0,value)
	return data.decode_u32(0)


static func valid_words(words: Variant,count: int) -> bool:
	if not words is Array or words.size()!=count: return false
	for word: Variant in words:
		if not Numbers.integer_between(word,0,4294967295): return false
	return true


static func area(site: Dictionary,owners: Dictionary) -> Dictionary:
	if not Membership.valid_site(site) or not Membership.valid_owners(owners): return {}
	var center := site
	if int(site["settlement_id"])!=-1 and not site["is_settlement"]:
		center=owners.get(str(int(site["settlement_id"])),{})
		if center.is_empty(): return {}
	return {"center":[float(center["x"]),float(center["z"]),float(center["height"])],"radius":float(center["radius"])}


static func _collect(point: Variant,sites: Array,owners: Dictionary,family: int) -> Array:
	var mask := [0,0]
	if point==null: return mask
	var field := "follower_modifiers" if family==0 else "house_modifiers"
	for site: Dictionary in sites:
		if not Membership._contains(site,point,owners): continue
		for i in range(2): mask[i]=int(mask[i])|int(site[field][i])
	return mask


static func collect(point: Variant,sites: Array,owners: Dictionary,family: int) -> Array:
	if family not in [0,1] or not valid_sites(sites,owners) or (point!=null and not Membership.valid_point(point)): return []
	return _collect(point,sites,owners,family)


static func _apply(words: Array,record: Dictionary) -> void:
	var index := int(record["index"])
	var operation := int(record["operation"])
	if operation not in [0,1]: return
	var before := word_float(int(words[index]))
	words[index]=float_word(before+float(record["value"]) if operation==0 else before*float(record["value"]))


static func follower(base: Array,point: Variant,sites: Array,owners: Dictionary,extra_mask: Array,content: Dictionary,table: String) -> Dictionary:
	var mask := collect(point,sites,owners,0)
	if mask.is_empty(): return {}
	return follower_from_mask(base,mask,extra_mask,content,table)


static func follower_from_mask(base: Array,mask: Array,extra_mask: Array,content: Dictionary,table: String) -> Dictionary:
	if table not in ["race","jobs"] or not valid_content(content) or not valid_words(base,int(content["row_words"][table])) or not valid_mask(mask) or not valid_mask(extra_mask): return {}
	var active := [int(mask[0])|int(extra_mask[0]),int(mask[1])|int(extra_mask[1])]
	var result := base.duplicate()
	var slot := 0
	for record: Dictionary in content["records"]:
		if int(record["family"])!=0: continue
		if record["table"]==table and (int(active[slot>>5])&(1<<(slot&31)))!=0: _apply(result,record)
		slot+=1
	return {"mask":mask.duplicate(),"values":result}


static func house(base: Array,point: Array,sites: Array,owners: Dictionary,parameters: Dictionary,content: Dictionary) -> Dictionary:
	var mask := collect(point,sites,owners,1)
	if mask.is_empty(): return {}
	return house_from_mask(base,mask,parameters,content)


static func house_from_mask(base: Array,mask: Array,parameters: Dictionary,content: Dictionary) -> Dictionary:
	if not valid_content(content) or not valid_words(base,76) or not valid_mask(mask) or not parameters.get("special") is bool or not Numbers.integer_between(parameters.get("kind"),0,4294967295) or not Numbers.integer_between(parameters.get("model_type"),0,4294967295): return {}
	var result := base.duplicate()
	for record: Dictionary in house_modifiers(mask,parameters,content):
		_apply(result,record)
	return {"mask":mask.duplicate(),"values":result}


static func house_is_monastery(parameters: Dictionary,content: Dictionary) -> bool:
	if not parameters["special"]:
		for entry: Dictionary in content["monastery_types"]:
			if int(entry["id"])==int(parameters["model_type"]):
				return true
	return false


static func house_applies(record: Dictionary,parameters: Dictionary,monastery: bool) -> bool:
	var special: bool=parameters["special"]
	if int(record["abode"])==0 and not special: return false
	if int(record["monastery"])==0 and monastery: return false
	if int(record["farm"])==0 and special and int(parameters["kind"])==1: return false
	if int(record["mine"])==0 and special and int(parameters["kind"])==2: return false
	return true


static func house_modifiers(mask: Array,parameters: Dictionary,content: Dictionary) -> Array:
	var monastery := house_is_monastery(parameters,content)
	var result: Array=[]
	var slot := 0
	for record: Dictionary in content["records"]:
		if int(record["family"])!=1: continue
		var enabled := (int(mask[slot>>5])&(1<<(slot&31)))!=0
		slot+=1
		if enabled and house_applies(record,parameters,monastery):
			result.append(record)
	return result
