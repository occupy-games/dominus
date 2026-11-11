extends RefCounted
## Original entity obstruction scan, 0x1003b550. Coordinates and world height
## are source values. The supplied query returns a discrete raw terrain step.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["height_scale","half","inset","clearance"]:
		if not (rules.get(key) is int or rules.get(key) is float) or not is_finite(float(rules[key])) or float(rules[key])<=0: return false
	return true


static func valid(site: Variant) -> bool:
	if not site is Dictionary or not Numbers.integer_between(site.get("footprint_width"),0,1024): return false
	for key: String in ["x","z","height"]:
		if not (site.get(key) is int or site.get(key) is float) or not is_finite(float(site[key])) or absf(float(site[key]))>1000000 or Terrain.f32(float(site[key]))!=float(site[key]): return false
	return true


static func bounds(site: Dictionary,rules: Dictionary) -> Rect2i:
	var half := int(site["footprint_width"])*float(rules["half"])
	var inset := float(rules["inset"])
	var x0 := floori(Terrain.f32(float(site["x"])-half+inset)+float(rules["half"]))
	var x1 := floori(Terrain.f32(float(site["x"])+half-inset)+float(rules["half"]))
	var z0 := floori(Terrain.f32(float(site["z"])-half+inset)+float(rules["half"]))
	var z1 := floori(Terrain.f32(float(site["z"])+half-inset)+float(rules["half"]))
	if x0==x1: x1+=1
	if z0==z1: z1+=1
	return Rect2i(x0,z0,x1-x0,z1-z0)


static func clearance_threshold(site: Dictionary,rules: Dictionary) -> float:
	return Terrain.f32(float(site["height"])/float(rules["height_scale"]))+float(rules["clearance"])


static func count(site: Dictionary,rules: Dictionary,ground: Callable) -> int:
	if not valid(site) or not valid_rules(rules) or not ground.is_valid(): return -1
	var region := bounds(site,rules)
	var threshold := clearance_threshold(site,rules)
	var result := 0
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if float(ground.call(x,z))>threshold: result+=1
	return result
