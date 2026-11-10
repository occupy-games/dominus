extends "res://tests/test_house_constructor.gd"

const Factory = preload("res://simulation/source_house_factory.gd")
const Pool = preload("res://simulation/source_house_pool.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


func execute(example: Dictionary,definition: Dictionary,resume: bool) -> Dictionary:
	var pool := Pool.initial(int(example.get("capacity",8)))
	var existing: Array=example.get("houses",[])
	for i in range(existing.size()):
		var id := Pool.allocate(pool)
		pool["slots"][str(id)]={"house_index":int(existing[i].get("index",18)),"identity":int(existing[i].get("owner",0))<<29}
	if example.has("stale"):
		for value: Variant in pool["free"]: pool["slots"][str(int(value))]={"house_index":int(example["stale"].get("index",18)),"identity":int(example["stale"].get("owner",0))<<29}
	for value: Variant in example.get("free_before",[]): Pool.release(pool,int(value))
	var plots := Registry.initial()
	var input := {"x":158,"z":120,"size":4}
	input.merge(example.get("plot",{}),true)
	var plot_id := Registry.allocate(plots,float(input["x"]),float(input["z"]),int(input["size"]),6.0)
	plots["slots"][plot_id].merge(input,true)
	plots["slots"][plot_id]["stored_size"]=int(input["size"])
	plots["slots"][plot_id]["progress"]=1.0
	var identities := {"counter":0}
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		var encoded: Variant=codec.encode_numbers({"pool":pool,"plots":plots,"identities":identities})
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(encoded)))
		pool=Pool.restore(saved["pool"])
		plots=Registry.restore(saved["plots"])
		identities=saved["identities"]
		check(not pool.is_empty() and not plots.is_empty(),"Both source pools must restore before factory execution")
	var calls := {"ground":[],"random":0,"mine":[],"attach":[],"fields":[]}
	var services := {
		"unlocked":func(key: String) -> bool:
			if key=="HousesBiomeLocked": return bool(example.get("biome_locked",true))
			if key=="FoodSpending": return bool(example.get("food_enabled",false))
			if key=="OreSpending": return bool(example.get("ore_enabled",false))
			return key in example.get("unlocks",["PlotsAppear"]),
		"ground":func(x: float,z: float) -> float:
			calls["ground"].append([x,z])
			return float(example.get("ground",6.0)),
		"random_word":func() -> int:
			calls["random"]+=1
			return int(example.get("random_word",0)),
		"nearby":func(_position: Array,_radius: float) -> Array: return example.get("nearby",[]),
		"field":func(channel: String,x: int,z: int) -> float:
			calls["fields"].append([int(channel=="blight"),x,z])
			return float(example.get(channel,0.0)),
		"mine_roll":func(minimum: float,maximum: float) -> float:
			calls["mine"].append([minimum,maximum])
			return float(example.get("mine_value",15.0)),
		"attach":func(id: int,settlement: int) -> void:
			check(pool["active"].has(id) and House.valid_state(pool["slots"][str(id)]),"Settlement attachment must see an initialized authoritative house")
			calls["attach"].append([id,settlement])}
	var parameters := {"plot":plot_id,"owner":int(example.get("owner",0)),"kind":int(example.get("kind",0)),"special":bool(example.get("special",false)),"settlement":4294967295,"clock":123456789,"seconds":12.5,"reuse":0 if example.get("reuse",false) else -1}
	var intents: Array=[]
	var result := Factory.create(pool,plots,identities,definition,parameters,services,intents)
	var expected: Dictionary=example["expected"]
	check((not result.is_empty())==bool(expected["created"]),"Original %s must preserve factory allocation success"%example["name"])
	check(Numbers.canonical_numbers(Pool.snapshot(pool))==Numbers.canonical_numbers(expected["pool"]),"Original %s must preserve exact active/free house order"%example["name"])
	check(Numbers.canonical_numbers(Registry.snapshot(plots))==Numbers.canonical_numbers(expected["registry"]),"Original %s must preserve plot ownership and immediate release"%example["name"])
	check(calls["random"]==int(expected["random_calls"]) and Numbers.canonical_numbers(calls["ground"])==Numbers.canonical_numbers(expected["ground_queries"]),"Original %s must preserve source sampling and random-word consumption"%example["name"])
	var dirty: Array=[]
	for i in range(1024):
		if plots["schedule"]["dirty"].has(str(i)): dirty.append(i)
	check(Numbers.canonical_numbers(dirty)==Numbers.canonical_numbers(expected["dirty"]),"Original %s must dirty the same plot regions"%example["name"])
	if not result.is_empty():
		var state: Dictionary=result["house"]
		check(state["id"]==int(expected["house_id"]),"Native allocation must select the same stable house identity")
		var expected_request: Dictionary=expected["request"].duplicate(true)
		for i in range(4): expected_request["position"][i]=Terrain.f32(float(expected_request["position"][i]))
		check(Numbers.canonical_numbers(result["request"])==Numbers.canonical_numbers(expected_request),"Original %s must retain exact constructor arguments"%example["name"])
		var core: Dictionary=expected["core"]
		var expected_fields: Dictionary=core["fields"].duplicate()
		var observed := fields(state,core["strings"])
		for key: String in expected_fields: check(observed.get(key)==expected_fields[key],"Original %s integrated constructor field %s must match"%[example["name"],key])
		check(int(identities["counter"])==int(core["next_identity"]),"Source factory must consume exactly one native identity")
		var occupied: Array=[] if example.get("reuse",false) else House.footprint_cells(state)
		check(Numbers.canonical_numbers(occupied)==Numbers.canonical_numbers(core["occupied"]),"The source building must occupy its actual initialized footprint")
		var sampled := PackedByteArray()
		sampled.resize(calls["fields"].size()*12)
		for i in range(calls["fields"].size()):
			for j in range(3): sampled.encode_s32(i*12+j*4,int(calls["fields"][i][j]))
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(sampled)
		check(hash.finish().hex_encode()==core["field_queries"]["sha256"] and sampled.size()/12==int(core["field_queries"]["count"]),"Integrated construction must query the original surroundings")
		check(Numbers.canonical_numbers(calls["mine"])==Numbers.canonical_numbers(core["mine_queries"]),"Integrated source mine initialization must keep its original random range")
		check(calls["attach"].size()==(0 if example.get("reuse",false) else 1),"Reconstruction must not attach a new building to a settlement")
		result["house"]["slots"][0]=5
		check(pool["slots"][str(state["id"])]["slots"][0]==-1,"Factory results must detach mutable house state")
	else:
		check(calls["fields"].is_empty() and calls["attach"].is_empty() and identities["counter"]==0 and intents.is_empty(),"A full original pool must fail before initializing, consuming identity or publishing effects")
	check(Pool.valid(pool) and Registry.valid(plots),"Both authoritative pools must remain structurally valid")
	return {"pool":pool,"plots":plots,"identities":identities,"calls":calls,"intents":intents}


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_house_factory.json"))
	var definition: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()["story"]
	var initialized := Pool.initial(int(definition["house_pool_rules"]["capacity"]))
	check(Numbers.canonical_numbers(Pool.snapshot(initialized))==Numbers.canonical_numbers(fixture["pool_initialization"]),"Source capacity and every initial free-list identity must match the original world initializer")
	check(Factory.valid(initialized),"The empty original house pool must be valid persisted simulation state")
	for example: Dictionary in fixture["cases"]:
		var state := execute(example,definition,false)
		check(Numbers.canonical_numbers(state)==Numbers.canonical_numbers(execute(example,definition,true)),"Original %s factory transaction must continue identically after restoring both pools"%example["name"])
		if example["name"]=="first":
			var codec := preload("res://infrastructure/world_store.gd").new()
			var encoded: Variant=codec.encode_numbers(state["pool"])
			var restored := Factory.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(encoded))))
			check(Factory.valid(restored) and Numbers.canonical_numbers(restored)==Numbers.canonical_numbers(state["pool"]),"Created source houses must validate and restore as authoritative pool state")
			for z in range(118,126):
				for x in range(156,164): check(Factory.occupied(restored,x,z)==(x>=158 and x<162 and z>=120 and z<124),"Source occupancy must query initialized geometry independently of presentation")
			restored["slots"]["0"]["slots"][0]=7
			check(state["pool"]["slots"]["0"]["slots"][0]==-1,"Restoring a source pool must detach individual house bodies")
			restored["slots"]["0"]["id"]=1
			check(not Factory.valid(restored) and Factory.restore(restored).is_empty(),"A house body must not impersonate a different pool identity")
	var pool := Pool.initial(4)
	for i in range(4): check(Pool.allocate(pool)==i,"Source free-list allocation must start in ascending slot order")
	check(Pool.allocate(pool)==-1,"Exhaustion must not invent a house slot")
	check(Pool.release(pool,1)==0 and Pool.release(pool,3)==2,"Freeing must return the next original active identity")
	check(Pool.allocate(pool)==3 and Pool.allocate(pool)==1,"Released house slots must reuse in native LIFO order")
	check(not Pool.valid({"capacity":1,"active":[0],"free":[0],"slots":{}}),"A duplicated pool identity must reject")
	print("Original house factory: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
