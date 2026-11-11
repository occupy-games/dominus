extends RefCounted
## Original Beautify terrain action after projection of the target onto the map.

const Terrain = preload("res://simulation/source_terrain.gd")
const Fields = preload("res://simulation/source_map_fields.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("configuration") is Dictionary:
		return false
	for key: String in ["dry_threshold","water_deduction","clear_threshold","encode_scale"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	if rules["encode_scale"]!=Fields.BYTE_SCALE:
		return false
	if rules.has("timer") and not preload("res://simulation/source_land_effect_timer.gd").valid_rules(rules["timer"]):
		return false
	for key: String in ["BEAUTIFY_RADIUS","BELIEF_PER_BEAUTIFY","BEAUTIFY_TIMEOUT","LE_TIMER_TICK_LENGTH"]:
		if not numeric(rules["configuration"].get(key)):
			return false
	return true


static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(Terrain.f32(float(value)))


static func timer_interval(rules: Dictionary,configuration: Dictionary) -> float:
	var value: Variant=configuration.get("LE_TIMER_TICK_LENGTH",rules["configuration"]["LE_TIMER_TICK_LENGTH"])
	if value is String and value.is_valid_float():
		value=float(value)
	return Terrain.f32(float(value)) if numeric(value) else NAN


static func settings(rules: Dictionary,configuration: Dictionary) -> Dictionary:
	if not valid_rules(rules):
		return {}
	var result := {}
	for key: String in rules["configuration"]:
		var value: Variant=configuration.get(key,rules["configuration"][key])
		if value is String and value.is_valid_float():
			value=float(value)
		if not numeric(value):
			return {}
		result[key]=Terrain.f32(float(value))
	if result["BEAUTIFY_RADIUS"]<0.0 or result["BEAUTIFY_RADIUS"]>32.0 or result["BELIEF_PER_BEAUTIFY"]<0.0 or result["BEAUTIFY_TIMEOUT"]<0.0 or result["LE_TIMER_TICK_LENGTH"]<=0.0:
		return {}
	return result


static func brush_axis(origin: int,extent: int) -> Array:
	# The rectangular field routines compare endpoints as unsigned values.
	if (origin&0xffffffff)>=((origin+extent)&0xffffffff):
		return []
	return range(origin,origin+extent)


static func quote(raster: Dictionary,x: float,z: float,rules: Dictionary,configuration: Dictionary,ground: Callable) -> Dictionary:
	if not is_finite(x) or not is_finite(z) or x<0.0 or z<0.0 or x>=1024.0 or z>=1024.0 or not ground.is_valid():
		return {}
	var config := settings(rules,configuration)
	if config.is_empty():
		return {}
	var center_x := int(Terrain.f32(x))
	var center_z := int(Terrain.f32(z))
	var radius := float(config["BEAUTIFY_RADIUS"])
	var half := int(radius)
	var diameter := Terrain.f32(radius*2.0)
	var extent := int(diameter)
	var left := center_x-half
	var top := center_z-half
	var maximum := Terrain.f32(diameter*diameter)
	for row in range(top,center_z+half+1):
		for column in range(left,center_x+half+1):
			if float(ground.call(column,row))<=float(rules["dry_threshold"]):
				maximum=Terrain.f32(maximum-float(rules["water_deduction"]))
	var existing := 0.0
	var columns := brush_axis(left,extent)
	for row: int in brush_axis(top,extent):
		for column: int in columns:
			existing=Terrain.f32(existing+Fields.read(raster,1,column,row))
	var remaining := maxf(0.0,Terrain.f32(maximum-existing))
	var charge := Terrain.f32(remaining*float(config["BELIEF_PER_BEAUTIFY"]))
	if not is_finite(charge) or charge>2147483647.0:
		return {}
	var ticks := Terrain.f32(float(config["BEAUTIFY_TIMEOUT"])/(float(config["LE_TIMER_TICK_LENGTH"])*Fields.BYTE_SCALE))
	if not is_finite(ticks):
		return {}
	return {"rect":[left,top,extent,extent],"charge":charge,"timer":ticks}


static func apply(raster: Dictionary,plan: Dictionary,rules: Dictionary,ground: Callable,events: Array) -> void:
	var rect: Array=plan["rect"]
	var rows := brush_axis(rect[1],rect[3])
	var columns := brush_axis(rect[0],rect[2])
	for kind: int in [2,3]:
		for z: int in rows:
			for x: int in columns:
				if not Fields.allocated(raster,kind,x,z):
					continue
				var changed := Fields.read(raster,kind,x,z)>float(rules["clear_threshold"])
				Fields.overwrite(raster,kind,x,z,0.0)
				if changed:
					events.append(["cell",x,z])
	for kind: int in [1,7]:
		for z: int in rows:
			for x: int in columns:
				if float(ground.call(x,z))>float(rules["dry_threshold"]):
					Fields.overwrite(raster,kind,x,z,1.0 if kind==1 else float(plan["timer"]))
	var reach := int(maxi(rect[2],rect[3])/2)+1
	var center_x := int(rect[0])+reach
	var center_z := int(rect[1])+reach
	events.append(["dirty",center_x,center_z,reach+1])
	events.append(["refresh",center_x,center_z,reach])
