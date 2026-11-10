extends RefCounted
## Original storm-end chest budget and bounded disk sampling. Placement services
## are explicit simulation callbacks; no devices, assets, clocks or filesystem.

const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("enabled") is bool or not Schedule.integer_between(rules.get("attempts"),0,10000): return false
	for key: String in ["influence_padding","debug_count","random_divisor","angle_scale","reflection","round_offset"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	return rules["influence_padding"]>=0 and rules["random_divisor"]>0 and rules["angle_scale"]>0 and rules["reflection"]==2.0 and rules["round_offset"]==0.5


static func valid_areas(areas: Variant) -> bool:
	if not areas is Array or areas.size()>64: return false
	for area: Variant in areas:
		if not area is Dictionary or not area.get("force") is bool or not area.get("unlock") is String: return false
		for key: String in ["x","z","radius"]:
			var value: Variant=area.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
		for key: String in ["max_spawn","max_depth","max_total"]:
			if not Schedule.integer_between(area.get(key),0,10000): return false
	return true


static func valid_chests(chests: Array) -> bool:
	if chests.size()>65535: return false
	for chest: Variant in chests:
		if not chest is Dictionary or not Schedule.integer_between(chest.get("source_id"),-2147483648,2147483647): return false
		for key: String in ["x","z"]:
			var value: Variant=chest.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	return true


static func replenish(areas: Array,chests: Array,rules: Dictionary,unlocked: Callable,activated: Array,random_word: Callable,place: Callable) -> Dictionary:
	var result := {"counts":[],"requests":[]}
	if not valid_rules(rules) or not valid_areas(areas) or not valid_chests(chests) or not rules["enabled"]: return result
	result["counts"].resize(areas.size())
	result["counts"].fill(0)
	# The native pass takes counts once, before generating any new chests. A
	# chest in overlapping areas counts in each. Only native ID zero counts;
	# authored reward-chest IDs are separate from the opening phase at +0x60.
	for index in range(areas.size()):
		var area: Dictionary=areas[index]
		if Terrain.f32(float(area["radius"]))<=0: break
		var count := 0
		var radius := Terrain.f32(float(area["radius"]))
		for chest: Dictionary in chests:
			if int(chest["source_id"])!=0: continue
			var x := Terrain.f32(Terrain.f32(float(chest["x"]))-Terrain.f32(float(area["x"])))
			var z := Terrain.f32(Terrain.f32(float(chest["z"]))-Terrain.f32(float(area["z"])))
			if Terrain.f32(x*x+z*z)<radius*radius: count+=1
		result["counts"][index]=count
	for index in range(result["counts"].size()):
		var area: Dictionary=areas[index]
		if Terrain.f32(float(area["radius"]))<=0: break
		if not area["force"] and not unlocked.call(str(area["unlock"])) and not index in activated: continue
		var draw := ((int(random_word.call())&0x7fff)*(int(area["max_spawn"])+1))>>15
		var count := mini(draw,maxi(0,int(area["max_total"])-int(result["counts"][index])))
		if float(rules["debug_count"])!=0: count=int(Terrain.f32(float(rules["debug_count"])))
		var request := {"x":Terrain.f32(float(area["x"])),"z":Terrain.f32(float(area["z"])),
			"radius":Terrain.f32(Terrain.f32(float(area["radius"]))-Terrain.f32(float(rules["influence_padding"]))),
			"count":count,"max_depth":Terrain.f32(float(area["max_depth"])),"debug":false}
		result["requests"].append(request)
		# Keep placement and its RNG consumption between successive area draws.
		# Even a zero-count request runs the native placement setup/cleanup.
		place.call(request.duplicate(true))
	return result


static func sample(x: float,z: float,radius: float,rules: Dictionary,random_word: Callable,acceptable: Callable) -> Dictionary:
	if not valid_rules(rules) or not is_finite(x) or not is_finite(z) or not is_finite(radius) or absf(x)>1000000 or absf(z)>1000000 or absf(radius)>1000000: return {}
	var position: Array=[]
	for attempt in range(int(rules["attempts"])):
		var angle := Terrain.f32(Terrain.f32(float(random_word.call())/float(rules["random_divisor"]))*float(rules["angle_scale"]))
		var first := Terrain.f32(float(random_word.call())/float(rules["random_divisor"]))
		var second := Terrain.f32(float(random_word.call())/float(rules["random_divisor"]))
		var fraction := Terrain.f32(first+second)
		if fraction>1.0: fraction=float(rules["reflection"])-fraction
		var distance := Terrain.f32(fraction*Terrain.f32(radius))
		position=[Terrain.f32(Terrain.f32(cos(angle)*distance)+Terrain.f32(x)),Terrain.f32(Terrain.f32(sin(angle)*distance)+Terrain.f32(z))]
		if acceptable.call(float(position[0]),float(position[1])): return {"ok":true,"position":position,"attempts":attempt+1}
	return {"ok":false,"position":position,"attempts":int(rules["attempts"])}


static func generate(request: Dictionary,rules: Dictionary,widths: Array,nearby: Callable,acceptable: Callable,random_word: Callable,create: Callable,release: Callable) -> Array:
	if not valid_rules(rules) or widths.size()!=4 or request.get("debug",false): return []
	for key: String in ["x","z","radius","max_depth"]:
		var value: Variant=request.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return []
	if not Schedule.integer_between(request.get("count"),-10000,10000): return []
	var padding := 0.0
	for value: Variant in widths:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return []
		padding=maxf(padding,Terrain.f32(float(value)))
	var x := Terrain.f32(float(request["x"]))
	var z := Terrain.f32(float(request["z"]))
	var radius := Terrain.f32(float(request["radius"]))
	var scan_radius := Terrain.f32(radius+padding)
	# Match the original broad-phase order and retain these collections for
	# this whole batch. The native candidate predicate owns narrow-phase tests.
	var scenery: Variant=nearby.call(2,x,z,scan_radius)
	var buildings: Variant=nearby.call(1,x,z,scan_radius)
	var predicate := func(px: float,pz: float) -> bool: return acceptable.call(px,pz,scenery,buildings)
	var created: Array=[]
	for index in range(maxi(0,int(request["count"]))):
		var point := sample(x,z,radius,rules,random_word,predicate)
		if not point["ok"]: continue
		var normalized := Terrain.f32(float(random_word.call())/float(rules["random_divisor"]))
		var maximum := Terrain.f32(Terrain.f32(float(request["max_depth"]))+1.0)
		var scaled := Terrain.f32(normalized*maximum)
		# Native 0x10357040 rounds by adding 0.5 before floor. It is not
		# integer truncation; endpoint depths retain their half-width bins.
		var depth := Terrain.f32(floor(scaled+float(rules["round_offset"])))
		var chest := {"x":point["position"][0],"z":point["position"][1],"depth":depth}
		created.append(chest)
		create.call(chest.duplicate(true))
	release.call(scenery)
	release.call(buildings)
	return created
