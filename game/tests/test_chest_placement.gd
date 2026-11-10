extends SceneTree

const Placement = preload("res://simulation/source_chest_placement.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_chest_placement.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Original placement rules must load only for matching executable and archive")
	if content.is_empty(): quit(1); return
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["chest_placement_rules"]==content["placement_rules"],"Authored campaign must receive the original placement rules")
	for example: Dictionary in fixture["cases"]:
		var rules: Dictionary=content["placement_rules"].duplicate(true)
		rules.merge(example.get("rules",{}),true)
		var queries: Array=[]
		var field := func(kind: String,x: int,z: int) -> Variant:
			queries.append([kind,x,z])
			if kind=="category": return 0 if example.get("missing_category",false) else int(example.get("category",0))
			return float(example.get("restriction",0))
		var ground := func(x: float,z: float) -> float:
			queries.append(["ground",x,z])
			return float(example.get("height",6))
		var unlocked := func(key: String) -> bool:
			queries.append(["unlock",key])
			return key in example.get("unlocks",[])
		var custom := func(object: Dictionary,x: int,z: int) -> bool:
			queries.append(["custom",int(object["id"]),x,z])
			object["x"]=999999 # Detached shape queries cannot change scenery.
			return bool(object.get("custom_result",false))
		var scenery: Array=example.get("scenery",[]).duplicate(true)
		for index in range(scenery.size()): scenery[index]["id"]=index
		var buildings: Array=example.get("buildings",[]).duplicate(true)
		var before := [scenery.duplicate(true),buildings.duplicate(true)]
		var result := Placement.acceptable(float(example.get("x",160)),float(example.get("z",120)),scenery,buildings,rules,field,ground,unlocked,custom,bool(example.get("high_override",false)))
		var expected: Dictionary=example["expected"]
		for query: Array in expected["queries"]:
			for index in range(1,query.size()):
				if query[index] is float: query[index]=Terrain.f32(float(query[index]))
		check(result==expected["ok"],"Native %s candidate acceptance must match"%example["name"])
		check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(expected["queries"]),"Native %s must retain field, ground, unlock and object query order: %s / %s"%[example["name"],queries,expected["queries"]])
		check(before==[scenery,buildings],"Placement cannot mutate authoritative scenery or buildings")
	var invalid: Dictionary=content["placement_rules"].duplicate(true)
	invalid["spawn_padding"]=NAN
	check(not Placement.valid_rules(invalid),"Non-finite original placement constants must reject")
	check(not Placement.acceptable(INF,0,[],[],content["placement_rules"],Callable(),Callable(),Callable()),"Invalid candidates must reject before service calls")
	check(not Placement.valid_objects([{"x":0,"z":0,"size":4,"special":true,"radius":INF}],true),"Invalid special-building radii must reject")
	check(not Placement.valid_objects([{"x":0,"z":0,"size":4}],false),"Missing source shape classification must reject")
	check(Placement.scenery_contains({"x":160,"z":120,"size":4,"custom":true},160,120,content["placement_rules"],Callable()),"An unresolved authored shape must remain blocked, without a replacement box")
	print("Original chest placement: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
