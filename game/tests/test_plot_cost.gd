extends SceneTree

const Cost = preload("res://simulation/source_plot_cost.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func execute(example: Dictionary,definition: Dictionary,resume: bool) -> Dictionary:
	var data: Dictionary=definition.duplicate(true)
	for key: String in example.get("cost_override",{}): data["plot_cost"]["costs"][int(key)]["food"]=float(example["cost_override"][key])
	data["plot_environment"]["configuration"].merge(example.get("configuration",{}),true)
	var plot := {"x":158.0,"z":120.0,"size":4,"height":6.0}
	plot.merge(example.get("plot",{}),true)
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"definition":data,"plot":plot})) ))
		data=saved["definition"]
		plot=saved["plot"]
	var queries: Array=[]
	var unlocked := func(key: String) -> bool:
		if key=="HousesBiomeLocked": return bool(example.get("biome_locked",true))
		if key=="FoodSpending": return bool(example.get("food_enabled",true))
		return key in example.get("unlocks",["PlotsAppear"])
	var settlement := func(position: Array) -> int:
		queries.append(position)
		return int(example.get("settlement",4294967295))
	var mode := int(example.get("mode",1))
	var result := Cost.quote(plot,mode,data,unlocked,settlement,int(example.get("counted_houses",1)))
	check(not result.is_empty(),"Original %s cost inputs must be available"%example["name"])
	if result.is_empty(): return {}
	var amount := float(result["amount"])
	var expected: Dictionary=example["expected"]
	check(amount==Terrain.f32(float(expected["amount"])),"Original %s must charge the exact float32 source food cost"%example["name"])
	var expected_queries: Array=expected["queries"].duplicate(true)
	for position: Array in expected_queries:
		for i in range(3): position[i]=Terrain.f32(float(position[i]))
	check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(expected_queries),"Original %s must query settlement membership at the source center and height"%example["name"])
	check(Cost.affordable(amount,mode,int(example.get("food",100)),int(example.get("ore",100)),data["plot_cost"]["rules"])==bool(expected["allowed"]),"Original %s resource-mode affordability must match"%example["name"])
	# The combined predicate always requests mode-one food cost.
	var combined := Cost.quote(plot,1,data,unlocked,settlement,int(example.get("counted_houses",1)))
	check(Cost.affordable_both(float(combined["amount"]),int(example.get("food",100)),int(example.get("ore",100)),data["plot_cost"]["rules"])==bool(expected["both"]),"Original %s combined affordability must match"%example["name"])
	return {"amount":amount,"queries":queries}


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_cost.json"))
	var definition: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()["story"]
	check(Cost.valid_content(definition["plot_cost"]),"All original plot food costs must load through the infrastructure adapter")
	for example: Dictionary in fixture["cases"]:
		check(Numbers.canonical_numbers(execute(example,definition,false))==Numbers.canonical_numbers(execute(example,definition,true)),"Original %s quotes must preserve exact-number continuation"%example["name"])
	var broken: Dictionary=definition.duplicate(true)
	broken["plot_cost"]["costs"][18]["id"]="wrong row"
	check(Cost.quote({"x":158,"z":120,"size":4,"height":6.0},1,broken,func(_key: String) -> bool: return true,func(_position: Array) -> int: return 4294967295,1).is_empty(),"Mismatched source row identities must be unavailable rather than charging another row")
	broken["plot_cost"]["costs"][18]["food"]=NAN
	check(not Cost.valid_content(broken["plot_cost"]),"Nonfinite cost data must reject")
	print("Original plot cost: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
