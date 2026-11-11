extends RefCounted
## Refreshes the original house object counts and circular beautification scan.
## The spatial query owns its result nodes. The field service owns map samples.

const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")
const Base = preload("res://simulation/source_house_base_stats.gd")
const Stats = preload("res://simulation/source_house_stats.gd")
const Pool = preload("res://simulation/source_house_pool.gd")
const EnvironmentBuffs = preload("res://simulation/source_house_environment.gd")
const MapFields = preload("res://simulation/source_map_fields.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Numbers.integer_between(rules.get("query_tag"),0,4294967295):
		return false
	if not Membership.source_float(rules.get("beauty_threshold")) or not Membership.source_float(rules.get("area_padding")):
		return false
	if not rules.get("query_flags") is Array or rules["query_flags"].size()!=6:
		return false
	for flag: Variant in rules["query_flags"]:
		if not Numbers.integer_between(flag,0,1):
			return false
	return true


static func bucket(object: Dictionary) -> int:
	var kind := int(object["type"])
	if kind>=20:
		return 2
	if kind>=15 and int(object.get("mode",0))==2:
		return 1
	return 0


static func scan_beauty(position: Array,radius: float,threshold: float,field: Callable) -> float:
	var center_x := int(position[0])
	var center_z := int(position[1])
	var extent := int(radius)
	var squared := int(radius*radius)
	var total := 0
	var beautified := 0
	for dz in range(-extent,extent+1):
		for dx in range(-extent,extent+1):
			if dx*dx+dz*dz>=squared:
				continue
			total+=1
			if Terrain.f32(float(field.call("beauty",center_x+dx,center_z+dz)))>threshold:
				beautified+=1
			field.call("blight",center_x+dx,center_z+dz)
	return Terrain.f32(float(beautified)/float(total)) if total>0 else NAN


static func valid_objects(objects: Variant) -> bool:
	if not objects is Array or objects.size()>4096:
		return false
	var nodes := {}
	for object: Variant in objects:
		if not object is Dictionary or not Numbers.integer_between(object.get("node"),0,4095):
			return false
		if not Numbers.integer_between(object.get("type"),-2147483648,2147483647) or not Numbers.integer_between(object.get("mode",0),-2147483648,2147483647):
			return false
		var node := int(object["node"])
		if nodes.has(node):
			return false
		nodes[node]=true
	return true


static func row_radius(row: Variant) -> float:
	if not row is Dictionary or not row.get("values") is Dictionary:
		return NAN
	var value: Variant=row["values"].get("visionradius")
	return float(value) if valid_radius(value) else NAN


static func valid_radius(value: Variant) -> bool:
	return Membership.source_float(value) and float(value)>=1.0 and float(value)<=256.0


static func area_distance_squared(position: Array,area: Array) -> float:
	var dx := Terrain.f32(float(area[0])-float(position[0]))
	var dz := Terrain.f32(float(area[1])-float(position[1]))
	return Terrain.f32(dx*dx+dz*dz)


static func refresh(house: Dictionary,rules: Dictionary,base: Callable,stats: Callable,query: Callable,release: Callable,field: Callable,area: Array=[]) -> bool:
	if not valid_rules(rules) or not Membership.valid_point(house.get("position")):
		return false
	if not EnvironmentBuffs.valid_samples(house.get("nearby"),house.get("beauty_fraction")):
		return false
	if not base.is_valid() or not stats.is_valid() or not query.is_valid() or not release.is_valid() or not field.is_valid():
		return false
	var position: Array=house["position"]
	var previous_counts: Array=house["nearby"]
	if not area.is_empty():
		if not Membership.valid_point(area) or float(area[2])<0.0:
			return false
		# The source area pass reads the current vision radius twice and
		# compares a stored float32 squared distance with a strict boundary.
		var distance_squared := area_distance_squared(position,area)
		var first := row_radius(stats.call())+float(area[2])+float(rules["area_padding"])
		var second := row_radius(stats.call())+float(area[2])+float(rules["area_padding"])
		if not is_finite(first) or not is_finite(second):
			return false
		if distance_squared>=first*second:
			return true
	else:
		house["nearby"]=[0,0,0]
		var radius := row_radius(base.call())
		if not is_finite(radius):
			house["nearby"]=previous_counts
			return false
		var request := [int(rules["query_tag"]),position[0],position[1],radius]
		request.append_array(rules["query_flags"])
		var objects: Variant=query.call(request)
		if not valid_objects(objects):
			house["nearby"]=previous_counts
			return false
		for object: Dictionary in objects:
			house["nearby"][bucket(object)]+=1
			release.call(int(object["node"]))
	var previous_beauty: Variant=house.get("beauty_fraction")
	house["beauty_fraction"]=0.0
	var radius := row_radius(stats.call())
	if not is_finite(radius):
		house["nearby"]=previous_counts
		house["beauty_fraction"]=previous_beauty
		return false
	house["beauty_fraction"]=scan_beauty(position,radius,float(rules["beauty_threshold"]),field)
	return true


static func refresh_pool(pool: Dictionary,definition: Dictionary,attachments: Dictionary,services: Dictionary,area: Array=[]) -> bool:
	if not Pool.valid(pool) or not valid_rules(definition.get("house_surroundings_rules")):
		return false
	if not area.is_empty() and (not Membership.valid_point(area) or float(area[2])<0.0):
		return false
	if not definition.has("house_base_stats") or not definition.has("temple_effects") or not definition.has("house_environment"):
		return false
	for name: String in ["unlocked","query","release"]:
		if not services.get(name) is Callable or not services[name].is_valid():
			return false
	var field: Callable
	if services.get("raster") is Dictionary and services["raster"].get("fields") is Dictionary:
		field=MapFields.surroundings.bind(services["raster"])
	elif services.get("field") is Callable and services["field"].is_valid():
		field=services["field"]
	else:
		return false
	for value: Variant in pool["active"]:
		var key := str(int(value))
		var house: Dictionary=pool["slots"].get(key,{})
		if not Numbers.integer_between(house.get("house_index"),0,63):
			return false
		var attachment: Variant=attachments.get(key)
		var base := func() -> Dictionary:
			return Base.resolve(definition["house_base_stats"],int(house["house_index"]),attachment)
		var stats := func() -> Dictionary:
			return Stats.resolve(definition,house,attachment,services["unlocked"])
		var query := func(request: Array) -> Variant:
			return services["query"].call(int(value),request)
		var release := func(node: int) -> void:
			services["release"].call(int(value),node)
		if not refresh(house,definition["house_surroundings_rules"],base,stats,query,release,field,area):
			return false
	return true
