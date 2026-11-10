extends SceneTree

const Chests = preload("res://simulation/source_storm_chests.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_storm_chests.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Original chest metadata must match executable and archive provenance")
	if content.is_empty(): quit(1); return
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["storm_chest_rules"]==content["rules"],"Authored campaign must receive source chest rules independently of presentation")
	check(definition["story"]["storm_chest_areas"]==content["scopes"]["initialworldsetup6"]["areas"],"Authored campaign must receive every source area and its limits")
	check(not content["scopes"]["initialworldsetup"]["available"],"Older schemas must remain unresolved until their native defaults are recovered")
	for example: Dictionary in fixture["cases"]:
		var rules: Dictionary=content["rules"].duplicate(true)
		rules.merge(example.get("rules",{}),true)
		var calls := {"random":0,"queries":[]}
		var words: Array=example.get("words",[32767])
		var random_word := func() -> int:
			var value := int(words[int(calls["random"])%words.size()])
			calls["random"]+=1
			return value
		var unlocked := func(key: String) -> bool:
			# The fixture uses the same unlock name for multiple records; the
			# source table itself is keyed by unlock. Recover the current query
			# index from a unique per-record name for this controlled comparison.
			var index := int(key)
			calls["queries"].append(["unlock",index])
			var active: bool=index in example.get("unlocked",[])
			if not active: calls["queries"].append(["activated",index])
			return active
		var place := func(request: Dictionary) -> void:
			for count in range(int(example.get("placement_random",0))): random_word.call()
			request["count"]=-999 # Callback input must not alias the returned intent.
		var areas: Array=example["areas"].duplicate(true)
		for index in range(areas.size()): areas[index]["unlock"]=str(index)
		var chests: Array=example.get("chests",[]).duplicate(true)
		var before := chests.duplicate(true)
		var result := Chests.replenish(areas,chests,rules,unlocked,example.get("activated",[]),random_word,place)
		var expected: Dictionary=example["expected"]
		check(Numbers.canonical_numbers(result["counts"])==Numbers.canonical_numbers(expected["counts"]),"Native %s counts must match"%example["name"])
		for request: Dictionary in expected["requests"]:
			for key: String in ["x","z","radius","max_depth"]: request[key]=Terrain.f32(float(request[key]))
		check(Numbers.canonical_numbers(result["requests"])==Numbers.canonical_numbers(expected["requests"]),"Native %s requests must match: %s / %s"%[example["name"],result["requests"],expected["requests"]])
		check(calls["random"]==int(expected["random_calls"]) and calls["queries"]==expected["queries"],"Native %s must preserve RNG and eligibility order"%example["name"])
		check(chests==before,"Refill queries must not mutate existing chest records")
	for example: Dictionary in fixture["samples"]:
		var rules: Dictionary=content["rules"].duplicate(true)
		rules.merge(example.get("rules",{}),true)
		var calls := {"random":0,"samples":[]}
		var words: Array=example.get("words",[32767])
		var random_word := func() -> int:
			var value := int(words[int(calls["random"])%words.size()])
			calls["random"]+=1
			return value
		var acceptable := func(x: float,z: float) -> bool:
			calls["samples"].append([x,z])
			return calls["samples"].size()>=int(example.get("accept_at",1))
		var result := Chests.sample(float(example["x"]),float(example["z"]),float(example["radius"]),rules,random_word,acceptable)
		var expected: Dictionary=example["expected"]
		for point: Array in expected["samples"]:
			for i in range(2): point[i]=Terrain.f32(float(point[i]))
		for i in range(expected["position"].size()): expected["position"][i]=Terrain.f32(float(expected["position"][i]))
		check(result["ok"]==expected["ok"] and result["position"]==expected["position"] and result["attempts"]==int(expected["attempts"]),"Native %s disk result must match: %s / %s"%[example["name"],result["position"],expected["position"]])
		check(calls["random"]==int(expected["random_calls"]) and calls["samples"]==expected["samples"],"Native %s must preserve each attempted point and random draw"%example["name"])
	for example: Dictionary in fixture["batches"]:
		var rules: Dictionary=content["rules"].duplicate(true)
		rules.merge(example.get("rules",{}),true)
		var calls := {"random":0,"samples":[],"queries":[],"created":[],"released":[]}
		var words: Array=example.get("words",[32767])
		var random_word := func() -> int:
			var value := int(words[int(calls["random"])%words.size()])
			calls["random"]+=1
			return value
		var nearby := func(kind: int,x: float,z: float,radius: float) -> int:
			calls["queries"].append({"kind":kind,"position":[x,z,radius],"flags":[0,0,0,0,1,1]})
			return kind
		var acceptable := func(x: float,z: float,scenery: Variant,buildings: Variant) -> bool:
			check(scenery==2 and buildings==1,"The native batch must retain both broad-phase collections for every candidate")
			calls["samples"].append([x,z])
			return not example.get("reject",false) and calls["samples"].size()%int(example.get("accept_every",1))==0
		var create := func(chest: Dictionary) -> void:
			calls["created"].append(chest.duplicate(true))
			for count in range(int(example.get("create_random",0))): random_word.call()
			chest["depth"]=-999
		var release := func(collection: Variant) -> void: calls["released"].append(collection)
		var result := Chests.generate(example["request"],rules,example.get("widths",[1.0,2.0,3.0,4.0]),nearby,acceptable,random_word,create,release)
		var expected: Dictionary=example["expected"]
		for chest: Dictionary in expected["created"]:
			for key: String in ["x","z","depth"]: chest[key]=Terrain.f32(float(chest[key]))
		for query: Dictionary in expected["queries"]:
			for i in range(3): query["position"][i]=Terrain.f32(float(query["position"][i]))
		for point: Array in expected["samples"]:
			for i in range(2): point[i]=Terrain.f32(float(point[i]))
		check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(expected["created"]) and Numbers.canonical_numbers(calls["created"])==Numbers.canonical_numbers(expected["created"]),"Native %s must create the same chest positions and burial depths"%example["name"])
		for key: String in ["random","samples","queries","released"]:
			check(Numbers.canonical_numbers(calls[key])==Numbers.canonical_numbers(expected["random_calls" if key=="random" else key]),"Native %s batch must preserve %s ordering"%[example["name"],key])
	var bad: Dictionary=content["rules"].duplicate(true)
	bad["attempts"]=-1
	check(not Chests.valid_rules(bad),"Invalid sampling budgets must reject before entering any loop")
	bad=content["rules"].duplicate(true)
	bad["influence_padding"]=NAN
	check(not Chests.valid_rules(bad),"Non-finite configuration must reject")
	check(not Chests.valid_areas([{"force":true}]),"Incomplete area records must reject")
	check(not Chests.valid_chests([{"x":INF,"z":0,"source_id":0}]) and not Chests.valid_chests([{"x":0,"z":0}]),"Invalid chest records must reject before counting or RNG use")
	check(Chests.sample(INF,0,1,content["rules"],Callable(),Callable()).is_empty(),"Non-finite sampling input must reject before calling services")
	check(preload("res://infrastructure/storm_chests.gd").load_content("wrong",fixture["source_sha256"]).is_empty(),"Unmatched native content cannot be injected")
	print("Original storm chests: %d refill cases, %d disk cases, %d batches, %d failures"%[fixture["cases"].size(),fixture["samples"].size(),fixture["batches"].size(),failures])
	quit(1 if failures else 0)
