extends RefCounted
## Authoritative numeric portion of the original chest constructor. Render
## resources/matrices are presentation; spatial registration is a pure callback.
## The factory separately owns the source ID and the reward identifier.

const Terrain = preload("res://simulation/source_terrain.gd")
const Placement = preload("res://simulation/source_chest_placement.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const ZERO_INTEGERS := ["60","6c","70","a0","a4"]
const FLOAT_SLOTS := ["1c","58","9c"]


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["glint_min","glint_max","random_divisor","height_scale","minimum_height"]:
		if not Placement.finite(rules.get(key)): return false
	return rules["random_divisor"]>0 and rules["height_scale"]>0 and rules["minimum_height"]>=0 and rules["glint_min"]>=0 and rules["glint_max"]>=0


static func valid_request(request: Variant) -> bool:
	if not request is Dictionary or not request.get("position") is Array or request["position"].size()!=3 or not Schedule.integer_between(request.get("kind"),0,4): return false
	for value: Variant in request["position"]:
		if not Placement.finite(value): return false
	return Placement.finite(request.get("depth")) and Placement.finite(request.get("rotation"))


static func can_register(x: float,z: float) -> bool:
	# Native spatial registration truncates then uses an unsigned comparison.
	# It accepts both endpoints, including a negative fractional coordinate
	# which truncates to zero; these are distinct from terrain sampling bounds.
	return int(x)>=0 and int(x)<=1024 and int(z)>=0 and int(z)<=1024


static func initialize(request: Dictionary,rules: Dictionary,ground: Callable,random_word: Callable,register: Callable) -> Dictionary:
	if not valid_rules(rules) or not valid_request(request): return {}
	var x := Terrain.f32(float(request["position"][0]))
	var z := Terrain.f32(float(request["position"][1]))
	var sampled: Variant=ground.call(x,z)
	if not Placement.finite(sampled): return {}
	var height := Terrain.f32(Terrain.f32(float(sampled))-Terrain.f32(float(request["depth"]))*float(rules["height_scale"]))
	height=maxf(height,Terrain.f32(float(rules["minimum_height"])))
	var registered := can_register(x,z)
	var spatial := {"kind":5,"position":[x,z],"radius":1.0,"flag":1}
	if registered: register.call(spatial.duplicate(true))
	var normalized := Terrain.f32(float(random_word.call())/float(rules["random_divisor"]))
	var minimum := Terrain.f32(float(rules["glint_min"]))
	var maximum := Terrain.f32(float(rules["glint_max"]))
	var interval := Terrain.f32(minimum+(maximum-minimum)*normalized)
	var slots := {"1c":0.0,"58":0.0,"98":true,"9c":interval}
	for key: String in ZERO_INTEGERS: slots[key]=0
	return {"kind":int(request["kind"]),"position":[x,z,height],"base_height":height,
		"rotation":Terrain.f32(float(request["rotation"])),"source_slots":slots,"spatial":spatial,"registered":registered}


static func stored(value: Variant) -> bool:
	# Valid finite input/configuration bounds can produce a larger buried
	# height or interval. Preserve those original float32 results as well.
	return Placement.finite(value,1000000000000000.0) and Terrain.f32(float(value))==float(value)


static func valid(record: Variant) -> bool:
	if not record is Dictionary or not Schedule.integer_between(record.get("kind"),0,4) or not record.get("position") is Array or record["position"].size()!=3: return false
	for value: Variant in record["position"]:
		if not stored(value): return false
	if not Placement.finite(record["position"][0]) or not Placement.finite(record["position"][1]): return false
	if not stored(record.get("base_height")) or not stored(record.get("rotation")) or not record.get("source_slots") is Dictionary or not record.get("registered") is bool: return false
	var slots: Dictionary=record["source_slots"]
	for key: String in ZERO_INTEGERS:
		if not Schedule.integer_between(slots.get(key),0,4294967295): return false
	for key: String in FLOAT_SLOTS:
		if not stored(slots.get(key)): return false
	if not Schedule.integer_between(slots["60"],0,2) or float(slots["58"])<0 or float(slots["9c"])<0: return false
	if not slots.get("98") is bool: return false
	var spatial: Variant=record.get("spatial")
	if not spatial is Dictionary or spatial.get("kind")!=5 or spatial.get("radius")!=1.0 or spatial.get("flag")!=1 or not spatial.get("position") is Array or spatial["position"].size()!=2: return false
	for index in range(2):
		if not stored(spatial["position"][index]) or float(spatial["position"][index])!=float(record["position"][index]): return false
	return record["registered"]==can_register(float(record["position"][0]),float(record["position"][1]))


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var record: Dictionary=saved.duplicate(true)
	record["kind"]=int(record["kind"])
	for index in range(3): record["position"][index]=float(record["position"][index])
	for key: String in ["base_height","rotation"]: record[key]=float(record[key])
	for key: String in ZERO_INTEGERS: record["source_slots"][key]=int(record["source_slots"][key])
	for key: String in FLOAT_SLOTS: record["source_slots"][key]=float(record["source_slots"][key])
	record["spatial"]["kind"]=int(record["spatial"]["kind"])
	record["spatial"]["flag"]=int(record["spatial"]["flag"])
	record["spatial"]["radius"]=float(record["spatial"]["radius"])
	for index in range(2): record["spatial"]["position"][index]=float(record["spatial"]["position"][index])
	return record
