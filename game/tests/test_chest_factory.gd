extends SceneTree

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
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_chest_factory.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Original chest factory rules must match source provenance")
	if content.is_empty(): quit(1); return
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["chest_factory_rules"]==content["factory_rules"],"Authored campaign must receive original chest type and reward constants")
	for example: Dictionary in fixture["cases"]:
		var rules: Dictionary=content["factory_rules"].duplicate(true)
		rules.merge(example.get("rules",{}),true)
		var calls := {"events":[],"random":0,"constructor":{},"source_id":7,"reward":""}
		var allocate := func() -> Variant:
			calls["events"].append(["allocate"])
			return null if example.get("allocation_failed",false) else 13
		var ground := func(x: float,z: float) -> float:
			calls["events"].append(["ground",x,z])
			return float(example.get("height",6))
		var random_word := func() -> int:
			calls["random"]+=1
			calls["events"].append(["random"])
			return int(example.get("word",32767))
		var construct := func(handle: Variant,request: Dictionary) -> Array:
			check(handle==13,"Constructor must receive the allocated source identity")
			calls["constructor"]=request.duplicate(true)
			calls["events"].append(["construct",request.duplicate(true)])
			for index in range(int(example.get("construct_random",0))): random_word.call()
			request["kind"]=-999
			return example.get("constructed_position",request["position"]).duplicate(true)
		var reward := func(handle: Variant,source_id: int,name: String) -> void:
			check(handle==13,"Reward must target the same source identity")
			calls["source_id"]=source_id
			calls["reward"]=name
			calls["events"].append(["reward",source_id,name])
		var notify := func(handle: Variant,position: Array) -> void:
			check(handle==13 and calls["source_id"]==0 and not calls["reward"].is_empty(),"Source notification must follow generated ID and reward assignment")
			calls["events"].append(["notify",position.duplicate(true)])
			position[0]=-999
		var result := Factory.spawn(float(example.get("x",160)),float(example.get("z",120)),float(example.get("depth",0)),rules,allocate,ground,random_word,construct,reward,notify)
		var expected: Dictionary=stored_numbers(example["expected"])
		check(calls["random"]==int(expected["random_calls"]) and Numbers.canonical_numbers(calls["events"])==Numbers.canonical_numbers(expected["events"]),"Native %s factory must preserve every service call in order: %s / %s"%[example["name"],calls["events"],expected["events"]])
		check(calls["source_id"]==int(expected["source_id"]) and calls["reward"]==expected["reward"],"Native %s source ID and reward must match"%example["name"])
		if expected["request"]==null:
			check(result.is_empty(),"Failed original allocation must not sample, spend RNG or construct")
		else:
			check(Numbers.canonical_numbers(result["constructor"])==Numbers.canonical_numbers(expected["request"]) and result["handle"]==13 and result["source_id"]==0 and result["reward"]==expected["reward"],"Native %s chest type and constructor fields must match"%example["name"])
			check(Numbers.canonical_numbers(result["position"])==Numbers.canonical_numbers(expected["events"][-1][1]),"Native %s notification must use the stored construction result"%example["name"])
	var invalid: Dictionary=content["factory_rules"].duplicate(true)
	invalid["story_odds"]=INF
	check(not Factory.valid_rules(invalid),"Invalid type-selection constants must reject")
	check(Factory.spawn(INF,0,0,content["factory_rules"],Callable(),Callable(),Callable(),Callable(),Callable(),Callable()).is_empty(),"Invalid coordinates must reject before allocation")
	print("Original chest factory: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
