extends RefCounted
## Original candidate gates and ordinary scenery/building clearances. Custom
## authored scenery shapes use an explicit simulation service, never a box proxy.

const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func finite(value: Variant,limit: float=1000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=limit


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["spawn_padding","deep_level","high_level","min_building_half","round_offset","inverse_height_scale","height_origin","footprint_inset"]:
		if not finite(rules.get(key)): return false
	for key: String in ["deep_unlock","high_unlock"]:
		if not rules.get(key) is String or rules[key].is_empty(): return false
	return rules["spawn_padding"]>=0 and rules["min_building_half"]>=0 and rules["round_offset"]==0.5 and rules["inverse_height_scale"]>0 and rules["footprint_inset"]>=0


static func valid_objects(objects: Array,buildings: bool) -> bool:
	if objects.size()>65535: return false
	for object: Variant in objects:
		if not object is Dictionary or not finite(object.get("x")) or not finite(object.get("z")) or not Schedule.integer_between(object.get("size"),0,4096): return false
		if buildings:
			if not object.get("special") is bool or not finite(object.get("radius",0)): return false
		elif not object.get("custom") is bool: return false
	return true


static func restricted(x: int,z: int,group: int,field: Callable) -> bool:
	# Original fields 2 (byte category) and 5 (restriction strength). Missing
	# category storage has the native zero default, supplied by the field owner.
	if x<0 or z<0 or x>=1024 or z>=1024: return false
	var value: Variant=field.call("category",x,z)
	if not Schedule.integer_between(value,0,255): return true
	var category := int(value)
	if category<group*64 or category>=(group+1)*64: return false
	value=field.call("restriction",x,z)
	return not finite(value) or float(value)!=0


static func scenery_contains(object: Dictionary,x: int,z: int,rules: Dictionary,custom: Callable) -> bool:
	if object["custom"]:
		# Unresolved authored shapes remain unavailable instead of silently
		# substituting a footprint which could put a chest through the object.
		return true if not custom.is_valid() else bool(custom.call(object.duplicate(true),x,z))
	var half := Terrain.f32(float(object["size"])*0.5)
	var padding := Terrain.f32(float(rules["spawn_padding"]))
	var inset := float(rules["footprint_inset"])
	var offset := float(rules["round_offset"])
	var cx := Terrain.f32(float(object["x"]))
	var cz := Terrain.f32(float(object["z"]))
	var left := int(floor(Terrain.f32(cx-half+inset-padding)+offset))
	var right := int(floor(Terrain.f32(cx+half-inset+padding)+offset))
	var top := int(floor(Terrain.f32(cz-half+inset-padding)+offset))
	var bottom := int(floor(Terrain.f32(cz+half-inset+padding)+offset))
	return x>=left and x<=right and z>=top and z<=bottom


static func building_contains(object: Dictionary,x: int,z: int,rules: Dictionary) -> bool:
	var half := Terrain.f32(maxf(float(object["size"])*0.5,Terrain.f32(float(rules["min_building_half"]))))
	var padding := Terrain.f32(float(rules["spawn_padding"]))
	var inset := float(rules["footprint_inset"])
	var cx := Terrain.f32(float(object["x"]))
	var cz := Terrain.f32(float(object["z"]))
	var left := int(floor(Terrain.f32(cx-half+inset-padding)))
	var right := int(ceil(Terrain.f32(cx+half-inset+padding)))
	var top := int(floor(Terrain.f32(cz-half+inset-padding)))
	var bottom := int(ceil(Terrain.f32(cz+half-inset+padding)))
	if x<left or x>right or z<top or z>bottom: return false
	if not object["special"] and absi(left-right)>2 and (x==left or x==right) and (z==top or z==bottom): return false
	return true


static func acceptable(x: float,z: float,scenery: Array,buildings: Array,rules: Dictionary,field: Callable,ground: Callable,unlocked: Callable,custom: Callable=Callable(),high_override: bool=false) -> bool:
	if not valid_rules(rules) or not finite(x) or not finite(z) or not valid_objects(scenery,false) or not valid_objects(buildings,true): return false
	var px := Terrain.f32(x)
	var pz := Terrain.f32(z)
	# Both coordinates use native truncation after adding 0.5, including
	# negative fractional positions. There is no floor at this conversion.
	var ix := int(px+float(rules["round_offset"]))
	var iz := int(pz+float(rules["round_offset"]))
	if restricted(ix,iz,0,field) or restricted(ix,iz,1,field): return false
	var sampled: Variant=ground.call(px,pz)
	if not finite(sampled): return false
	var height := Terrain.f32(Terrain.f32(float(sampled))*float(rules["inverse_height_scale"]))
	if height<=Terrain.f32(float(rules["deep_level"]))+float(rules["height_origin"]) and not unlocked.call(str(rules["deep_unlock"])): return false
	if height>=Terrain.f32(float(rules["high_level"]))+float(rules["height_origin"]) and not unlocked.call(str(rules["high_unlock"])) and not high_override: return false
	for object: Dictionary in scenery:
		if scenery_contains(object,ix,iz,rules,custom): return false
	for object: Dictionary in buildings:
		if building_contains(object,ix,iz,rules): return false
		if object["special"]:
			var radius := Terrain.f32(Terrain.f32(float(object.get("radius",0)))+Terrain.f32(float(rules["spawn_padding"])))
			var dx := Terrain.f32(px-Terrain.f32(float(object["x"])))
			var dz := Terrain.f32(pz-Terrain.f32(float(object["z"])))
			if Terrain.f32(dx*dx+dz*dz)<radius*radius: return false
	return true
