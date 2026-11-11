extends RefCounted
## Original core building initialization, with resolved source stats and fields.
## Model/mesh lookup, dynamic stat modifiers and later house lifetime are separate.

const Terrain = preload("res://simulation/source_terrain.gd")
const Biomes = preload("res://simulation/source_biomes.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Surroundings = preload("res://simulation/source_house_surroundings.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("rotation_override_id") is String: return false
	for key: String in ["half","rank_divisor","rank_bias","pi","negative_pi","two_pi","update_delay","beauty_threshold","rotation_override"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000: return false
	for key: String in ["ordinary_event","special_event"]:
		if not Schedule.integer_between(rules.get(key),0,4294967295): return false
	if not rules.get("mine_ranges") is Array or rules["mine_ranges"].size()!=6: return false
	for pair: Variant in rules["mine_ranges"]:
		if not pair is Array or pair.size()!=2: return false
		for value: Variant in pair:
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if float(pair[0])>float(pair[1]): return false
	return rules["rank_divisor"]>0 and rules["half"]>0 and rules["pi"]>0 and rules["negative_pi"]<0 and rules["two_pi"]>rules["pi"]


static func valid_record(record: Variant) -> bool:
	if not record is Dictionary or not record.get("id") is String or record["id"].is_empty() or not Schedule.integer_between(record.get("index"),0,63) or not Schedule.integer_between(record.get("rank"),-1,6): return false
	var values: Variant=record.get("values")
	if not values is Dictionary: return false
	for key: String in ["base size","capacity","build capacity","buildbuildingpriority","visionradius"]:
		var value: Variant=values.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>65535: return false
	return Schedule.integer_between(values["base size"],1,16) and values["visionradius"]>=1 and values["visionradius"]<=256


static func valid_content(content: Variant) -> bool:
	if not content is Dictionary or not valid_rules(content.get("rules")) or not content.get("records") is Array or content["records"].size()!=62: return false
	var ids := {}
	for index in range(content["records"].size()):
		var record: Variant=content["records"][index]
		if not valid_record(record) or int(record["index"])!=index or ids.has(record["id"]): return false
		ids[record["id"]]=true
	return true


static func initialize(request: Dictionary,record: Dictionary,rules: Dictionary,configuration: Dictionary,identity_state: Dictionary,clock: int,seconds: float,nearby: Array,field: Callable,mine_roll: Callable,events: Array) -> Dictionary:
	if not valid_record(record) or not valid_rules(rules) or not field.is_valid() or not mine_roll.is_valid() or clock<0 or not is_finite(seconds) or seconds<0 or seconds>1000000000000: return {}
	for key: String in ["food_enabled","ore_enabled"]:
		if not configuration.get(key) is bool: return {}
	for key: String in ["loc2Start","loc3Start"]:
		var value: Variant=configuration.get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return {}
	if not Schedule.integer_between(identity_state.get("counter"),0,4294967295) or not Schedule.integer_between(request.get("owner"),0,7) or int(request.get("index",-1))!=int(record["index"]): return {}
	for key: String in ["configuration","unknown_a","unknown_b","kind"]:
		if not Schedule.integer_between(request.get(key),0,4294967295): return {}
	if not Schedule.integer_between(request.get("extra",0),0,4294967295) or not Schedule.integer_between(request.get("special"),0,1) or not request.get("reuse") is bool: return {}
	var position: Variant=request.get("position")
	if not position is Array or position.size()!=4: return {}
	for value: Variant in position:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return {}
	for object: Variant in nearby:
		if not object is Dictionary or not Schedule.integer_between(object.get("type"),0,255) or not Schedule.integer_between(object.get("mode",0),0,255): return {}
	var values: Dictionary=record["values"]
	var flags := int(request["configuration"])
	if flags==4294967295: flags=2*int(configuration["food_enabled"])+4*int(configuration["ore_enabled"])
	var identity := int(request["unknown_b"])&0xffffff
	if identity==0:
		identity_state["counter"]=(int(identity_state["counter"])+1)&0xffffffff
		identity=int(identity_state["counter"])&0xffffff
	identity|=(1<<24)|(int(request["owner"])<<29)
	var x := Terrain.f32(float(position[0]))
	var z := Terrain.f32(float(position[1]))
	var height := Terrain.f32(float(position[2]))
	var angle := Terrain.f32(float(rules["rotation_override"]) if record["id"]==rules["rotation_override_id"] else float(position[3]))
	if angle>float(rules["pi"]): angle=Terrain.f32(angle-float(rules["two_pi"]))
	if angle<float(rules["negative_pi"]): angle=Terrain.f32(angle+float(rules["two_pi"]))
	var size := int(values["base size"])
	# 0x10357040 rounds with floor(value + 0.5), including negative values
	# and odd sizes. The preceding subtraction is stored as float32 first.
	var origin := [floori(Terrain.f32(x-float(size)*float(rules["half"]))+float(rules["half"])),floori(Terrain.f32(z-float(size)*float(rules["half"]))+float(rules["half"]))]
	if not request["reuse"]: events.append({"type":"source_house_occupancy","rectangle":[origin[0],origin[1],int(origin[0])+size,int(origin[1])+size]})
	var counts := [0,0,0]
	for object: Dictionary in nearby:
		counts[Surroundings.bucket(object)]+=1
	var radius := Terrain.f32(float(values["visionradius"]))
	var beauty_fraction := Surroundings.scan_beauty([x,z],radius,float(rules["beauty_threshold"]),field)
	var weight := 0.0
	var mine_value := 0.0
	if not request["reuse"]:
		weight=Terrain.f32(minf(1.0,float(int(record["rank"])*int(record["rank"]))/float(rules["rank_divisor"])+float(rules["rank_bias"])))
		events.append({"type":"source_house_spatial","kind":1,"position":[x,z],"radius":Terrain.f32(float(values["base size"])*float(rules["half"])),"circular":true})
		if int(request["unknown_a"])==0:
			events.append({"type":"source_house_event","key":int(rules["special_event"] if int(request["special"])!=0 else rules["ordinary_event"]),"position":[x,z,height],"arguments":[0,7,0]})
		if int(request["special"])!=0 and int(request["kind"])==2 and int(record["rank"])>=1:
			var pair: Array=rules["mine_ranges"][int(record["rank"])-1]
			mine_value=Terrain.f32(float(mine_roll.call(float(pair[0]),float(pair[1]))))
	return {"priority":Terrain.f32(float(values["buildbuildingpriority"])),"capacity":int(float(values["capacity"]))&0xffff,
		"build_capacity":int(float(values["build capacity"]))&0xffff,"native_mode":4,"profession":int(request["kind"]),
		"special":int(request["special"]),"progress":0.0,"created_clock":clock,"timer":0.0,"identity":identity,
		"position":[x,z,height],"angle":angle,"update_after":Terrain.f32(Terrain.f32(seconds)+float(rules["update_delay"])),
		"base_seconds":Terrain.f32(seconds),"state":0,"variant":int(request.get("extra",0)),"category":"farm" if int(request["special"])!=0 else "house",
		"size":size,"origin":origin,"rank_weight":weight,"location":Biomes.band(int(height/Terrain.HEIGHT_SCALE),configuration)+1,
		"created_seconds":Terrain.f32(seconds),"nearby":counts,"beauty_fraction":beauty_fraction,
		"house_index":int(record["index"]),"settlement_index":-1,"resource_flags":flags,"mine_value":mine_value,"slots":[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]}


static func valid_state(state: Variant) -> bool:
	if not state is Dictionary: return false
	for key: String in ["capacity","build_capacity"]:
		if not Schedule.integer_between(state.get(key),0,65535): return false
	for key: String in ["identity","profession","variant","resource_flags"]:
		if not Schedule.integer_between(state.get(key),0,4294967295): return false
	if ((int(state["identity"])>>24)&31)!=1 or not Schedule.integer_between(state.get("special"),0,1) or state.get("native_mode")!=4: return false
	if not Schedule.integer_between(state.get("created_clock"),0,9223372036854775807) or not Schedule.integer_between(state.get("size"),1,16) or not Schedule.integer_between(state.get("state"),0,255) or not Schedule.integer_between(state.get("house_index"),0,63) or not Schedule.integer_between(state.get("location"),1,3): return false
	if state.get("category") not in ["house","farm"]: return false
	if not Schedule.integer_between(state.get("settlement_index"),-1,39): return false
	for key: String in ["priority","progress","timer","angle","update_after","base_seconds","rank_weight","created_seconds","beauty_fraction","mine_value"]:
		var value: Variant=state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000000000: return false
	for key: String in ["rank_weight","beauty_fraction"]:
		if state[key]<0 or state[key]>1: return false
	if not state.get("position") is Array or state["position"].size()!=3 or not state.get("origin") is Array or state["origin"].size()!=2: return false
	for value: Variant in state["position"]:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	for value: Variant in state["origin"]:
		if not Schedule.integer_between(value,-1000016,1000016): return false
	if not state.get("nearby") is Array or state["nearby"].size()!=3 or not state.get("slots") is Array or state["slots"].size()!=13: return false
	for value: Variant in state["nearby"]:
		if not Schedule.integer_between(value,0,1000000): return false
	for value: Variant in state["slots"]:
		if not Schedule.integer_between(value,-1,4294967295): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid_state(saved): return {}
	var state: Dictionary=saved.duplicate(true)
	for key: String in ["capacity","build_capacity","native_mode","profession","special","created_clock","identity","state","variant","size","location","house_index","settlement_index","resource_flags"]: state[key]=int(state[key])
	for key: String in ["priority","progress","timer","angle","update_after","base_seconds","rank_weight","created_seconds","beauty_fraction","mine_value"]: state[key]=float(state[key])
	for key: String in ["origin","nearby","slots"]:
		for i in range(state[key].size()): state[key][i]=int(state[key][i])
	for i in range(3): state["position"][i]=float(state["position"][i])
	return state


static func footprint_cells(state: Dictionary) -> Array:
	var origin: Variant=state.get("origin")
	if not origin is Array or origin.size()!=2 or not Schedule.integer_between(state.get("size"),1,16): return []
	for value: Variant in origin:
		if not Schedule.integer_between(value,-1000016,1000016): return []
	var cells: Array=[]
	for z in range(maxi(0,int(origin[1])),mini(1024,int(origin[1])+int(state["size"]))):
		for x in range(maxi(0,int(origin[0])),mini(1024,int(origin[0])+int(state["size"]))): cells.append(z*1024+x)
	return cells
