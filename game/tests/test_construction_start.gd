extends "res://tests/test_house_constructor.gd"

const Construction = preload("res://simulation/source_construction_start.gd")
const Factory = preload("res://simulation/source_house_factory.gd")
const Pool = preload("res://simulation/source_house_pool.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")
const References = preload("res://simulation/source_target_references.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


func execute(example: Dictionary,definition: Dictionary,resume: bool) -> Dictionary:
	var pool := Pool.initial(int(example.get("capacity",8)))
	for existing: Dictionary in example.get("houses",[]):
		var id := Pool.allocate(pool)
		pool["slots"][str(id)]={"house_index":int(existing.get("index",18)),"identity":int(existing.get("owner",0))<<29}
	for id: Variant in example.get("free_before",[]): Pool.release(pool,int(id))
	var plots := Registry.initial()
	var plot := {"x":158,"z":120,"size":4}
	plot.merge(example.get("plot",{}),true)
	var plot_id := Registry.allocate(plots,float(plot["x"]),float(plot["z"]),int(plot["size"]),6.0)
	plots["slots"][plot_id].merge(plot,true)
	plots["slots"][plot_id]["stored_size"]=int(plot["size"])
	plots["slots"][plot_id]["progress"]=1.0
	var settlement := int(example.get("settlement",4294967295))
	var initial_identity := int(example.get("next_identity",0))
	var state := {"houses":pool,"plots":plots,"identities":{"counter":initial_identity},"counters":References.counters_initial(),"target":References.initial(definition["target_reference_rules"]),"position":example.get("position",[161.0,123.0,6.0]).duplicate(),"follower":{"home":-1,"settlement_index":-1 if settlement==4294967295 else settlement,"profession":int(example.get("profession",0)),"owner":int(example.get("owner",0))}}
	if example.get("plot_target",false):
		state["target"]={"identity":7<<24,"entity":plot_id,"position":[float(plot["x"])+int(plot["size"])*0.5,float(plot["z"])+int(plot["size"])*0.5],"flag":true}
		state["counters"]["plots"][str(plot_id)]=[0,1,Terrain.f32(float(example.get("skill",1.0)))]
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		state=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state))))
		state["houses"]=Pool.restore(state["houses"])
		state["plots"]=Registry.restore(state["plots"])
		state["target"]=References.restore(state["target"])
		state["counters"]=References.restore_counters(state["counters"])
	var calls := {"spending":[],"payment_effects":[],"transitions":[],"effects":[],"rectangles":[],"attachments":[],"ground_queries":[],"settlement_queries":[],"random_calls":0,"skill_calls":0,"fields":[],"mine":[]}
	var services := {
		"unlocked":func(key: String) -> bool:
			if key=="HousesBiomeLocked": return bool(example.get("biome_locked",true))
			if key=="FoodSpending": return bool(example.get("food_enabled",false))
			if key=="OreSpending": return bool(example.get("ore_enabled",false))
			return key in example.get("unlocks",["PlotsAppear"]),
		"ground":func(x: float,z: float) -> float:
			calls["ground_queries"].append([x,z])
			return float(example.get("ground",6.0)),
		"random_word":func() -> int:
			calls["random_calls"]+=1
			return int(example.get("random_word",0)),
		"nearby":func(_position: Array,_radius: float) -> Array: return example.get("nearby",[]),
		"field":func(channel: String,x: int,z: int) -> float:
			calls["fields"].append([int(channel=="blight"),x,z])
			return float(example.get(channel,0.0)),
		"mine_roll":func(minimum: float,maximum: float) -> float:
			calls["mine"].append([minimum,maximum])
			return float(example.get("mine_value",15.0)),
		"attach":func(id: int,index: int) -> void:
			check(House.valid_state(state["houses"]["slots"][str(id)]),"Attachment must follow full original core initialization")
			state["houses"]["slots"][str(id)]["settlement_index"]=int(example.get("attachment_index",-1))
			calls["attachments"].append([id,index]),
		"settlement":func(position: Array) -> int:
			calls["settlement_queries"].append(position)
			return int(example.get("lookup_settlement",4294967295)),
		"food_enabled":func() -> bool: return bool(example.get("food_enabled",false)),
		"cost":func(input: Dictionary,mode: int) -> float:
			check(int(input["id"])==plot_id and mode==1,"Original plot-cost lookup must use mode one")
			return float(example.get("cost",0.0)),
		"spend":func(amount: float) -> void:
			check(state["identities"]["counter"]==initial_identity and state["plots"]["active"].has(plot_id),"Payment must precede allocation and plot release")
			calls["spending"].append(amount),
		"payment_effect":func(_house: Dictionary,amount: float,a: int,b: int) -> void: calls["payment_effects"].append([amount,a,b]),
		"skill":func() -> float:
			calls["skill_calls"]+=1
			return float(example.get("skill",1.0)),
		"transition":func(action: int) -> void:
			var id := int(state["target"]["entity"])
			check(id>=0 and state["houses"]["active"].has(id) and not state["plots"]["active"].has(plot_id),"Target assignment and plot release must precede action transition")
			check(state["counters"]["houses"][str(id)][0]==0 and state["counters"]["houses"][str(id)][1]==1,"Starting a job reserves a worker without marking it actively constructing")
			calls["transitions"].append(action),
		"effect":func(_house: Dictionary,owner: int,category: int,event: int) -> void: calls["effects"].append([owner,category,event]),
		"rectangle":func(rectangle: Array) -> void: calls["rectangles"].append(rectangle)}
	var parameters := {"plot":plot_id,"kind":int(example.get("kind",0)),"special":bool(example.get("special",false)),"clock":123456789,"seconds":12.5,"local_owner":int(example.get("local_owner",0))}
	var events: Array=[]
	var started := false
	if example.get("native_cost",false):
		parameters["counted_houses"]=int(example.get("counted_houses",1))
		services.erase("cost")
		started=Construction.start_priced(state,definition,parameters,services,events)
	else: started=Construction.start(state,definition,parameters,services,events)
	var expected: Dictionary=example["expected"]
	check(started==bool(expected["started"]),"Integrated %s must retain native start success"%example["name"])
	for key: String in ["spending","payment_effects","transitions","effects","rectangles","attachments","ground_queries","settlement_queries","random_calls","skill_calls"]:
		check(Numbers.canonical_numbers(calls[key])==Numbers.canonical_numbers(expected[key]),"Integrated %s must preserve %s"%[example["name"],key])
	var target: Dictionary=expected["target"].duplicate(true)
	for i in range(2): target["position"][i]=Terrain.f32(float(target["position"][i]))
	var counters: Dictionary=expected["counters"].duplicate(true)
	for group: String in ["houses","plots"]:
		for row: Array in counters[group].values(): row[2]=Terrain.f32(float(row[2]))
	check(Numbers.canonical_numbers(state["target"])==Numbers.canonical_numbers(target),"Integrated %s must assign the actual constructor identity"%example["name"])
	check(Numbers.canonical_numbers(state["counters"])==Numbers.canonical_numbers(counters),"Integrated %s must update native worker/skill/settlement counters"%example["name"])
	check(Numbers.canonical_numbers(Pool.snapshot(state["houses"]))==Numbers.canonical_numbers(expected["pool"]),"Integrated %s must retain native house-pool ordering"%example["name"])
	check(Numbers.canonical_numbers(Registry.snapshot(state["plots"]))==Numbers.canonical_numbers(expected["registry"]),"Integrated %s must retain native plot-pool state"%example["name"])
	var dirty: Array=[]
	for i in range(1024):
		if state["plots"]["schedule"]["dirty"].has(str(i)): dirty.append(i)
	check(Numbers.canonical_numbers(dirty)==Numbers.canonical_numbers(expected["dirty"]),"Integrated construction must dirty the original neighborhoods")
	if started:
		var house: Dictionary=state["houses"]["slots"][str(int(target["entity"]))]
		var core: Dictionary=expected["core"]
		var observed := fields(house,core["strings"])
		for key: String in core["fields"]: check(observed.get(key)==core["fields"][key],"Integrated %s native constructor field %s must match after target side effects"%[example["name"],key])
		check(state["identities"]["counter"]==int(core["next_identity"]),"Integrated start must consume the original identity count")
		check(Numbers.canonical_numbers(House.footprint_cells(house))==Numbers.canonical_numbers(core["occupied"]),"The reserved house must have the original complete occupancy")
		check(Numbers.canonical_numbers(calls["mine"])==Numbers.canonical_numbers(core["mine_queries"]),"Source mine initialization must run during the follower start")
		var sampled := PackedByteArray()
		sampled.resize(calls["fields"].size()*12)
		for i in range(calls["fields"].size()):
			for j in range(3): sampled.encode_s32(i*12+j*4,int(calls["fields"][i][j]))
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(sampled)
		check(hash.finish().hex_encode()==core["field_queries"]["sha256"],"The integrated constructor must sample the same surroundings")
	else:
		check(events.is_empty() and state["identities"]["counter"]==initial_identity,"Pool exhaustion must leave identity and constructor events untouched")
	var unchanged: Dictionary=state.duplicate(true)
	check(not Construction.start(state,definition,parameters,{},events) and state==unchanged,"Missing services must reject before any mutation or second payment")
	return {"state":state,"calls":calls,"events":events}


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_construction_start.json"))
	var definition: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()["story"]
	for example: Dictionary in fixture["cases"]:
		var result := execute(example,definition,false)
		check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(execute(example,definition,true)),"Integrated %s must survive save-codec continuation before execution"%example["name"])
		if example["name"]=="first":
			var state: Dictionary=result["state"]
			var codec := preload("res://infrastructure/world_store.gd").new()
			var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state))))
			saved["houses"]=Factory.restore(saved["houses"])
			saved["target"]=References.restore(saved["target"])
			saved["counters"]=References.restore_counters(saved["counters"])
			check(not saved["houses"].is_empty(),"A whole construction-start result must restore as a complete house pool")
			check(References.clear(saved["target"],saved["follower"],{"houses":saved["houses"]["slots"]},saved["counters"],definition["target_reference_rules"],func() -> float: return 1.0),"The reserved target must remain valid after restoring the integrated start")
			check(saved["counters"]["houses"].is_empty() and not state["counters"]["houses"].is_empty(),"Releasing the restored reservation must leave the original snapshot detached")
	print("Original integrated construction start: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
