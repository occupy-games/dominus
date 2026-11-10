extends RefCounted
## Original plot factory composed with source allocation/core initialization.
## This low-level operation does not grant an unported follower job or artwork.

const Pool = preload("res://simulation/source_house_pool.gd")
const Conversion = preload("res://simulation/source_plot_conversion.gd")
const House = preload("res://simulation/source_house_constructor.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func create(pool: Dictionary,plots: Dictionary,identities: Dictionary,definition: Dictionary,parameters: Dictionary,services: Dictionary,events: Array) -> Dictionary:
	if not Pool.valid(pool) or not House.valid_content(definition.get("house_constructor")) or not Conversion.valid_rules(definition.get("plot_conversion_rules")): return {}
	if not preload("res://simulation/source_houses.gd").valid(definition.get("house_selection")) or not preload("res://simulation/source_biomes.gd").valid(definition.get("plot_environment")): return {}
	for key: String in ["unlocked","ground","random_word","nearby","field","mine_roll","attach"]:
		if not services.get(key) is Callable or not services[key].is_valid(): return {}
	for key: String in ["owner","kind","plot","settlement","clock"]:
		if not Schedule.integer_between(parameters.get(key),0,9223372036854775807): return {}
	if int(parameters["owner"])>7 or int(parameters["kind"])>2 or int(parameters["settlement"])>4294967295 or not parameters.get("special") is bool: return {}
	if not Schedule.integer_between(parameters.get("reuse",-1),-1,int(pool["capacity"])-1): return {}
	var seconds: Variant=parameters.get("seconds")
	if not (seconds is int or seconds is float) or not is_finite(float(seconds)): return {}
	var plot_id := int(parameters["plot"])
	if not plots.get("active",[]).has(plot_id): return {}
	var plot: Dictionary=plots["slots"][plot_id].duplicate(true)
	if not Conversion.valid_input(plot,[]): return {}
	var reuse := int(parameters.get("reuse",-1))
	if reuse>=0 and not pool["active"].has(reuse): return {}
	# Keep validation failures local. Existing slot bodies are read, never
	# mutated; only the created/reconstructed slot is replaced on commit.
	var working := {"capacity":int(pool["capacity"]),"active":pool["active"].duplicate(),"free":pool["free"].duplicate(),"slots":pool["slots"].duplicate()}
	var id := reuse if reuse>=0 else Pool.allocate(working)
	if id<0: return {}
	var existing: Array=[]
	for value: Variant in working["active"]:
		var old: Dictionary=working["slots"].get(str(int(value)),{})
		existing.append({"index":int(old.get("house_index",0)),"owner":int(old.get("identity",0))>>29})
	var request := Conversion.request(plot,int(parameters["owner"]),int(parameters["kind"]),bool(parameters["special"]),reuse>=0,existing,definition["house_selection"],definition["plot_environment"],definition["plot_conversion_rules"],services["unlocked"],services["ground"],services["random_word"])
	if request.is_empty(): return {}
	var record: Dictionary=definition["house_constructor"]["records"][int(request["index"])]
	var nearby: Variant=services["nearby"].call(request["position"].slice(0,3),float(record["values"]["visionradius"]))
	if not nearby is Array: return {}
	var configuration: Dictionary=definition["plot_environment"]["configuration"].duplicate()
	configuration["food_enabled"]=bool(services["unlocked"].call("FoodSpending"))
	configuration["ore_enabled"]=bool(services["unlocked"].call("OreSpending"))
	var counter: Dictionary=identities.duplicate(true)
	var intents: Array=[]
	var house := House.initialize(request,record,definition["house_constructor"]["rules"],configuration,counter,int(parameters["clock"]),float(seconds),nearby,services["field"],services["mine_roll"],intents)
	if house.is_empty() or not House.valid_state(house): return {}
	house["id"]=id
	working["slots"][str(id)]=house
	pool.merge(working,true)
	identities.merge(counter,true)
	events.append_array(intents)
	if reuse<0:
		services["attach"].call(id,int(parameters["settlement"]))
		Conversion.release_plot(plots,plot_id,true,false)
	# The caller receives a detached descriptor; authoritative state stays in
	# the simulation-owned pool rather than in a presentation scene or callback.
	return {"house":house.duplicate(true),"request":request}


static func valid(pool: Variant) -> bool:
	# Persisted production state must contain complete initialized bodies.
	# The structural pool alone also supports transient allocation/capture data.
	if not Pool.valid(pool): return false
	for value: Variant in pool["active"]:
		if not pool["slots"].has(str(int(value))): return false
	for key: String in pool["slots"]:
		var house: Dictionary=pool["slots"][key]
		if house.is_empty() and not pool["active"].has(int(key)): continue
		if not House.valid_state(house) or not Schedule.integer_between(house.get("id"),int(key),int(key)): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var pool := Pool.restore(saved)
	for key: String in pool["slots"]:
		if pool["slots"][key].is_empty(): continue
		pool["slots"][key]=House.restore(pool["slots"][key])
		pool["slots"][key]["id"]=int(key)
	return pool


static func occupied(pool: Dictionary,x: int,z: int) -> bool:
	if x<0 or z<0 or x>=1024 or z>=1024: return false
	for value: Variant in pool["active"]:
		var house: Dictionary=pool["slots"][str(int(value))]
		var origin: Array=house["origin"]
		if x>=int(origin[0]) and z>=int(origin[1]) and x<int(origin[0])+int(house["size"]) and z<int(origin[1])+int(house["size"]): return true
	return false
