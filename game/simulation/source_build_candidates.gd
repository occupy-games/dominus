extends RefCounted
## Original builder selection over an explicitly ordered list of plot candidates.
## Spatial collection, follower decision dispatch and execution are separate.

const Terrain = preload("res://simulation/source_terrain.gd")
const Biomes = preload("res://simulation/source_biomes.gd")
const Houses = preload("res://simulation/source_houses.gd")


static func valid_values(values: Variant) -> bool:
	if not values is Dictionary or values.is_empty() or values.size()>64: return false
	for id: Variant in values:
		if not id is String or id.is_empty() or not values[id] is Dictionary: return false
		for key: String in ["build capacity","buildplotpriority"]:
			var value: Variant=values[id].get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>1000000: return false
	return true


static func valid_parameters(parameters: Dictionary) -> bool:
	if not parameters.get("position") is Array or parameters["position"].size()!=3: return false
	for value: Variant in parameters["position"]:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	for key: String in ["radius","height_balance","priority_scale"]:
		var value: Variant=parameters.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	return parameters.get("disabled") is bool and preload("res://simulation/source_plot_schedule.gd").integer_between(parameters.get("actor_mode"),0,10000)


static func score(x: float,z: float,target_x: float,target_z: float,height_term: float,weight: float,radius: float,target_radius: float) -> float:
	# Preserve every original float32 store. Native fsqrt and the final divide,
	# subtraction and multiply retain extra precision until the final store.
	var reach := Terrain.f32(Terrain.f32(radius)+Terrain.f32(target_radius))
	var dx := Terrain.f32(Terrain.f32(x)-Terrain.f32(target_x))
	var dz := Terrain.f32(Terrain.f32(z)-Terrain.f32(target_z))
	var distance := Terrain.f32(Terrain.f32(dx*dx)+Terrain.f32(dz*dz))
	distance=Terrain.f32(distance+Terrain.f32(height_term))
	if Terrain.f32(reach*reach)<=distance: return 0.0
	return Terrain.f32((1.0-sqrt(distance)/reach)*Terrain.f32(weight))


static func choose_plots(candidates: Array,parameters: Dictionary,rows: Array,values: Dictionary,environment: Dictionary,unlocked: Callable,allows: Callable,raw_height: Callable) -> Dictionary:
	var result := {"action":250,"plot":-1,"center":[],"score":0.0}
	if not valid_parameters(parameters) or parameters["disabled"] or int(parameters["actor_mode"])==6 or float(parameters["priority_scale"])<=0: return result
	var position: Array=parameters["position"].map(func(value: Variant) -> float: return Terrain.f32(float(value)))
	var actor_raw := int(float(position[2])/Terrain.HEIGHT_SCALE)
	for plot: Dictionary in candidates:
		var size := int(plot["size"])
		if size<=0: continue
		var half := Terrain.f32(float(size)*0.5)
		var x := Terrain.f32(Terrain.f32(float(plot["x"]))+half)
		var z := Terrain.f32(Terrain.f32(float(plot["z"]))+half)
		var biome := Biomes.biome_at(environment["biomes"],environment["configuration"],x,z)
		var band := Biomes.band(int(Terrain.f32(float(plot["height"]))/Terrain.HEIGHT_SCALE),environment["configuration"])
		var house := Houses.choose(rows,size,band,biome,unlocked,0,false,unlocked.call("HousesBiomeLocked"))
		if house.is_empty(): continue
		# The original builder requests the power/max influence gate at the
		# integer plot center. Fresh allocation has a different field predicate.
		if not allows.call(int(x),int(z),true): continue
		var input: Dictionary=values[house["id"]]
		# The native builder reads the +0x1004 worker array. The separate
		# +0x4 reservation array is not this capacity check.
		if int(plot.get("workers",0))>=int(Terrain.f32(float(input["build capacity"]))): continue
		var height := Terrain.f32(float(actor_raw-int(raw_height.call(x,z)))*Terrain.f32(float(parameters["height_balance"])))
		var weight := Terrain.f32(Terrain.f32(float(input["buildplotpriority"]))*Terrain.f32(float(parameters["priority_scale"])))
		var value := score(position[0],position[1],x,z,Terrain.f32(height*height),weight,float(parameters["radius"]),half)
		# Strict improvement preserves the first exact tie in native list order.
		if value>float(result["score"]): result={"action":102,"plot":int(plot["id"]),"center":[x,z],"score":value}
	return result
