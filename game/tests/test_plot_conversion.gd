extends SceneTree

const Conversion = preload("res://simulation/source_plot_conversion.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")
const Numbers = preload("res://simulation/progression.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_conversion.json"))
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var rules: Dictionary=definition["story"]["plot_conversion_rules"]
	check(Conversion.valid_rules(rules),"The campaign must inject original conversion constants")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for example: Dictionary in fixture["cases"]:
		var state := Registry.initial()
		var plot := {"id":0,"x":158,"z":120,"size":4,"height":6.0}
		plot.merge(example.get("plot",{}),true)
		var id := Registry.allocate(state,float(plot["x"]),float(plot["z"]),int(plot["size"]),6.0)
		state["slots"][id]["stored_size"]=int(plot["size"])
		state["slots"][id]["progress"]=1.0
		var existing: Array=example.get("houses",[]).duplicate(true)
		for house: Dictionary in existing:
			house["index"]=int(house.get("index",18))
			house["owner"]=int(house.get("owner",0))
		var calls := {"random":0,"ground":[]}
		var ground := func(x: float,z: float) -> float:
			calls["ground"].append([x,z])
			return float(example.get("ground",6.0))
		var random_word := func() -> int:
			calls["random"]+=1
			return int(example.get("random_word",0))
		var unlocked := func(key: String) -> bool: return key=="HousesBiomeLocked" or key in example.get("unlocks",["PlotsAppear"])
		var request: Variant=null
		# Match the original order: no sampling or RNG after allocation failure.
		if not example.get("allocation_failed",false):
			request=Conversion.request(plot,int(example.get("owner",0)),int(example.get("kind",0)),bool(example.get("special",false)),bool(example.get("reuse",false)),existing,definition["story"]["house_selection"],definition["story"]["plot_environment"],rules,unlocked,ground,random_word)
		var expected: Dictionary=example["expected"]
		if expected["request"]!=null:
			for i in range(4): expected["request"]["position"][i]=Terrain.f32(float(expected["request"]["position"][i]))
		check(Numbers.canonical_numbers(request)==Numbers.canonical_numbers(expected["request"]),"Native %s constructor arguments must match: %s / %s"%[example["name"],request,expected["request"]])
		check(calls["random"]==int(expected["random_calls"]) and calls["ground"]==expected["ground_queries"],"Native %s sampling and RNG consumption must match"%example["name"])
		var resumed := Registry.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state)))))
		check(not resumed.is_empty(),"Pending conversion input must restore through the save numeric codec")
		Conversion.release_plot(state,id,bool(expected["created"]),bool(example.get("reuse",false)))
		Conversion.release_plot(resumed,id,bool(expected["created"]),bool(example.get("reuse",false)))
		check(Numbers.canonical_numbers(Registry.snapshot(state))==Numbers.canonical_numbers(expected["registry"]),"Native %s must preserve exact ownership and immediate/free-slot order"%example["name"])
		var dirty: Array=[]
		for index in range(1024):
			if state["schedule"]["dirty"].has(str(index)): dirty.append(index)
		check(Numbers.canonical_numbers(dirty)==Numbers.canonical_numbers(expected["dirty"]),"Native %s must dirty the same source regions: %s / %s"%[example["name"],dirty,expected["dirty"]])
		check(state==resumed and Registry.valid(state),"A successful conversion or retained plot must continue identically after restoring")
		if not example.get("reuse",false) and expected["created"]:
			check(not Conversion.release_plot(state,id,true,false),"The old plot must not be released or added to the free list twice")
			check(Registry.allocate(state,160.0,124.0,4,6.0)==id,"Immediate source conversion must make that exact plot identity reusable")
	var invalid := {"x":158,"z":120,"size":4,"offset":[NAN,0]}
	check(not Conversion.valid_input(invalid,[]),"Non-finite placement offsets must reject")
	invalid={"height_offset":INF,"pi":rules["pi"]}
	check(not Conversion.valid_rules(invalid),"Invalid source placement constants must reject before sampling")
	print("Original plot conversion: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
