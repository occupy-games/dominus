extends SceneTree

const Core = preload("res://simulation/source_chest_constructor.gd")
const Factory = preload("res://simulation/source_chest_factory.gd")
const Numbers = preload("res://simulation/progression.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func stored_numbers(value: Variant) -> Variant:
	if value is float: return Terrain.f32(float(value))
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(stored_numbers(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key]=stored_numbers(value[key])
		return result
	return value


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_chest_constructor.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Chest numeric initialization must match source archive and executable")
	if content.is_empty(): quit(1); return
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["chest_core_rules"]==content["core_rules"],"Authored campaign must receive original constructor constants")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for example: Dictionary in fixture["cases"]:
		var rules: Dictionary=content["core_rules"].duplicate(true)
		rules.merge(example.get("core_rules",{}),true)
		var calls := {"events":[["construct",example["request"].duplicate(true)]],"random":0}
		var ground := func(x: float,z: float) -> float:
			calls["events"].append(["ground",x,z])
			return float(example.get("height",6))
		var register := func(spatial: Dictionary) -> void:
			calls["events"].append(["register",spatial.duplicate(true)])
			spatial["position"][0]=-999
		var random_word := func() -> int:
			calls["random"]+=1
			calls["events"].append(["random"])
			return int(example.get("word",32767))
		var request: Dictionary=example["request"].duplicate(true)
		var before := request.duplicate(true)
		var record := Core.initialize(request,rules,ground,random_word,register)
		var expected: Dictionary=stored_numbers(example["expected"])
		check(Numbers.canonical_numbers(record)==Numbers.canonical_numbers(expected["record"]),"Native %s constructor fields must match: %s / %s"%[example["name"],record,expected["record"]])
		check(Numbers.canonical_numbers(calls["events"])==Numbers.canonical_numbers(expected["events"]) and calls["random"]==int(expected["random_calls"]),"Native %s must preserve ground, spatial and random ordering"%example["name"])
		check(request==before and not record.has("source_id") and not record.has("reward") and not record["source_slots"].has("54"),"Core initialization must preserve its input and leave factory-owned fields untouched")
		check(Core.valid(record),"Every source constructor result must be valid plain save data")
		var resumed := Core.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(record)))))
		check(resumed==record,"Original numeric chest data must round-trip exactly through the save codec")
		resumed["position"][0]=-999
		check(record["position"][0]!=-999,"Restored records must detach mutable arrays")
	for example: Dictionary in fixture["composed"]:
		var rules: Dictionary=content["factory_rules"].duplicate(true)
		rules.merge(example.get("factory_rules",{}),true)
		var calls := {"events":[],"ground":0,"random":0,"record":{},"source_id":7,"reward":""}
		var allocate := func() -> Variant:
			calls["events"].append(["allocate"])
			return null if example.get("allocation_failed",false) else 13
		var ground := func(x: float,z: float) -> float:
			calls["events"].append(["ground",x,z])
			var values: Array=example.get("ground_heights",[example.get("height",6)])
			var value := float(values[mini(int(calls["ground"]),values.size()-1)])
			calls["ground"]+=1
			return value
		var random_word := func() -> int:
			calls["random"]+=1
			calls["events"].append(["random"])
			return int(example.get("word",32767))
		var register := func(spatial: Dictionary) -> void: calls["events"].append(["register",spatial.duplicate(true)])
		var construct := func(handle: Variant,request: Dictionary) -> Array:
			check(handle==13,"Core construction must retain the allocated identity")
			calls["events"].append(["construct",request.duplicate(true)])
			calls["record"]=Core.initialize(request,content["core_rules"],ground,random_word,register)
			return calls["record"]["position"].duplicate(true)
		var reward := func(handle: Variant,source_id: int,name: String) -> void:
			check(handle==13,"Reward must target the constructed chest")
			calls["source_id"]=source_id
			calls["reward"]=name
			calls["events"].append(["reward",source_id,name])
		var notify := func(handle: Variant,position: Array) -> void:
			check(handle==13,"The source notification must target the same chest")
			calls["events"].append(["notify",position.duplicate(true)])
		var result := Factory.spawn(float(example.get("x",160)),float(example.get("z",120)),float(example.get("depth",0)),rules,allocate,ground,random_word,construct,reward,notify)
		var expected: Dictionary=stored_numbers(example["expected"])
		check(Numbers.canonical_numbers(calls["events"])==Numbers.canonical_numbers(expected["events"]) and calls["random"]==int(expected["random_calls"]),"Native %s composed factory/constructor order must match"%example["name"])
		check(calls["source_id"]==int(expected["source_id"]) and calls["reward"]==expected["reward"],"Native %s factory-owned source ID and reward must match"%example["name"])
		if expected["record"]==null:
			check(result.is_empty() and calls["record"].is_empty(),"Allocation failure must skip the entire constructor")
		else:
			check(Numbers.canonical_numbers(calls["record"])==Numbers.canonical_numbers(expected["record"]),"Native %s must use actual core data, including final buried height"%example["name"])
			check(result["position"]==calls["record"]["position"],"Factory notification position must match constructed authoritative state")
	var rng := RandomNumberGenerator.new()
	rng.seed=43171
	var request := {"position":[160.125,120.375,0],"depth":.75,"rotation":180,"kind":0}
	var ground := func(_x: float,_z: float) -> float: return 6.125
	var random_word := func() -> int: return rng.randi()&0x7fff
	var register := func(_spatial: Dictionary) -> void: pass
	var first := Core.initialize(request,content["core_rules"],ground,random_word,register)
	var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"record":first,"rng":str(rng.state)}))))
	var continued := Core.initialize(request,content["core_rules"],ground,random_word,register)
	var resumed_rng := RandomNumberGenerator.new()
	resumed_rng.state=int(saved["rng"])
	var resumed_word := func() -> int: return resumed_rng.randi()&0x7fff
	check(Core.restore(saved["record"])==first and Core.initialize(request,content["core_rules"],ground,resumed_word,register)==continued and rng.state==resumed_rng.state,"Saved chest state and injected RNG must continue identically")
	var invalid := first.duplicate(true)
	invalid["source_slots"]["9c"]=NAN
	check(Core.restore(invalid).is_empty(),"Non-finite saved lifecycle timers must reject")
	invalid=first.duplicate(true)
	invalid["spatial"]["position"][0]+=1
	check(Core.restore(invalid).is_empty(),"Saved spatial ownership must match the chest position")
	invalid=first.duplicate(true)
	invalid["source_slots"]["60"]=3
	check(Core.restore(invalid).is_empty(),"Unsupported saved opening phases must reject")
	invalid=first.duplicate(true)
	invalid["source_slots"]["58"]=-1.0
	check(Core.restore(invalid).is_empty(),"Negative saved lifecycle elapsed time must reject")
	invalid=content["core_rules"].duplicate(true)
	invalid["height_scale"]=INF
	check(not Core.valid_rules(invalid),"Invalid constructor constants must reject")
	check(Core.initialize({"position":[INF,0,0],"depth":0,"rotation":0,"kind":0},content["core_rules"],Callable(),Callable(),Callable()).is_empty(),"Malformed requests must reject before any service call")
	print("Original chest constructor: %d core cases, %d factory cases, %d failures"%[fixture["cases"].size(),fixture["composed"].size(),failures])
	quit(1 if failures else 0)
