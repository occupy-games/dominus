extends RefCounted
## Original 0x1003b690: count foundation samples differing from the stored raw
## anchor step. Position is the same source coordinate used by the house body.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["half","inset","tolerance"]:
		if not Membership.source_float(rules.get(key)) or float(rules[key])<=0: return false
	return true


static func valid(state: Variant) -> bool:
	return state is Dictionary and Membership.valid_point(state.get("position")) and Numbers.integer_between(state.get("anchor_step"),-2147483648,2147483647) and Numbers.integer_between(state.get("nav_size"),-1024,1024) and Numbers.integer_between(state.get("uneven_count"),0,4294967295)


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for key: String in ["anchor_step","nav_size","uneven_count"]: result[key]=int(result[key])
	for i in range(3): result["position"][i]=float(result["position"][i])
	return result


static func bounds(state: Dictionary,rules: Dictionary) -> Rect2i:
	var half := int(state["nav_size"])*float(rules["half"])
	var inset := float(rules["inset"])
	var x := float(state["position"][0]); var z := float(state["position"][1])
	var x0 := floori(Terrain.f32(x-half+inset)+float(rules["half"]))
	var x1 := floori(Terrain.f32(x+half-inset)+float(rules["half"]))
	var z0 := floori(Terrain.f32(z-half+inset)+float(rules["half"]))
	var z1 := floori(Terrain.f32(z+half-inset)+float(rules["half"]))
	# Unlike the temple obstruction scan, both endpoints are inclusive and an
	# inverted interval remains empty; no artificial sample is added.
	return Rect2i(x0,z0,maxi(0,x1-x0+1),maxi(0,z1-z0+1))


static func scan(state: Dictionary,rules: Dictionary,service: Callable,overlay: Callable,ground: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not service.is_valid() or not overlay.is_valid() or not ground.is_valid(): return false
	var region := bounds(state,rules)
	var anchor := Terrain.f32(float(state["anchor_step"]))
	state["uneven_count"]=0
	var available := bool(service.call("terrain_overlay",[]))
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var sampled: Variant=null
			var use_ground := true
			if available:
				var value: Variant=overlay.call(x,z)
				if not value is Dictionary or not value.get("found") is bool: return false
				if value["found"]:
					use_ground=false
					sampled=value.get("height")
			if use_ground: sampled=ground.call(x,z)
			if not (sampled is int or sampled is float) or not is_finite(float(sampled)) or not is_finite(Terrain.f32(float(sampled))): return false
			var difference := Terrain.f32(Terrain.f32(float(sampled))-anchor)
			if absf(difference)>float(rules["tolerance"]): state["uneven_count"]=int(state["uneven_count"])+1
	return true
