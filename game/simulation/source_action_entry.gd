extends RefCounted
## Original 0x10067620 state entry. Clip resolution/duration are pure services;
## playback requests never determine simulation completion or working counts.

const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Schedule.integer_between(rules.get("missing_clip"),1,65535) or not Schedule.integer_between(rules.get("missing_update"),1,65535): return false
	var scale: Variant=rules.get("orientation_scale")
	return (scale is int or scale is float) and is_finite(float(scale)) and scale>0 and scale<1


static func valid_entry(entry: Variant) -> bool:
	return entry is Dictionary and Schedule.integer_between(entry.get("update_type"),0,2147483647) and entry.get("loop") is bool


static func valid_content(content: Variant) -> bool:
	if not content is Dictionary or not valid_rules(content.get("rules")) or not content.get("records") is Array or content["records"].size()>5020: return false
	var identities := {}
	for record: Variant in content["records"]:
		if not record is Dictionary or not Schedule.integer_between(record.get("action"),0,250) or not Schedule.integer_between(record.get("index"),0,19) or not record.get("available") is bool: return false
		var key := "%d:%d"%[int(record["action"]),int(record["index"])]
		if identities.has(key): return false
		identities[key]=true
		if record["available"] and not valid_entry(record): return false
	return true


static func find(content: Dictionary,action: int,index: int) -> Dictionary:
	if not valid_content(content): return {}
	for record: Dictionary in content["records"]:
		if int(record["action"])==action and int(record["index"])==index:
			return {"update_type":int(record["update_type"]),"loop":bool(record["loop"])} if record["available"] else {}
	return {}


static func valid_actor(actor: Variant) -> bool:
	if not actor is Dictionary or not Schedule.integer_between(actor.get("step"),0,19) or not actor.get("entry_done") is bool or not actor.get("has_channel") is bool or not Schedule.integer_between(actor.get("clip"),-2147483648,2147483647): return false
	for key: String in ["orientation","orientation_rate","clip_duration","clip_phase","clip_time"]:
		var value: Variant=actor.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	return true


static func enter(actor: Dictionary,index: int,profile: int,entry: Dictionary,rules: Dictionary,services: Dictionary) -> Dictionary:
	if not valid_actor(actor) or index<0 or index>=20 or not valid_entry(entry) or not valid_rules(rules): return {}
	for key: String in ["resolve","duration","orientation","animate"]:
		if not services.get(key) is Callable or not services[key].is_valid(): return {}
	actor["step"]=index
	actor["entry_done"]=false
	var local: Dictionary=entry.duplicate(true)
	var clip := int(services["resolve"].call(actor,local,profile))
	var failed := clip>=int(rules["missing_clip"]) and int(local["update_type"])>=int(rules["missing_update"])
	if not failed and actor["has_channel"]:
		services["orientation"].call(Terrain.f32(float(actor["orientation"])),Terrain.f32(Terrain.f32(float(actor["orientation_rate"]))*float(rules["orientation_scale"])))
	actor["clip_duration"]=Terrain.f32(float(services["duration"].call(clip)))
	actor["clip"]=clip
	if actor["has_channel"]: services["animate"].call(clip,bool(local["loop"]),1.0,0.0)
	actor["clip_phase"]=0.0
	actor["clip_time"]=0.0
	return {"result":not failed}


static func restore(saved: Variant) -> Dictionary:
	if not valid_actor(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for key: String in ["step","clip"]: result[key]=int(result[key])
	for key: String in ["orientation","orientation_rate","clip_duration","clip_phase","clip_time"]: result[key]=Terrain.f32(float(result[key]))
	return result
