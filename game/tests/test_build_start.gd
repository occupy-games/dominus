extends SceneTree

const Start = preload("res://simulation/source_build_start.gd")
const Conversion = preload("res://simulation/source_plot_conversion.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")
const Numbers = preload("res://simulation/progression.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func execute(example: Dictionary,definition: Dictionary,resume: bool) -> Dictionary:
	var state := Registry.initial()
	var plot := {"id":0,"x":158,"z":120,"size":4,"height":6.0}
	plot.merge(example.get("plot",{}),true)
	var id := Registry.allocate(state,float(plot["x"]),float(plot["z"]),int(plot["size"]),6.0)
	state["slots"][id]["stored_size"]=int(plot["size"])
	state["slots"][id]["progress"]=1.0
	var actor := {"owner":int(example.get("owner",0)),"settlement":int(example.get("settlement",4294967295)),"position":example.get("position",[161.0,123.0,6.0]).duplicate(),"action":102,"target":{}}
	var economy := {"food":100.0}
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"registry":state,"actor":actor,"economy":economy}))))
		state=Registry.restore(saved["registry"])
		actor=saved["actor"]
		economy=saved["economy"]
	var log := {"operations":[],"targets":[],"transitions":[],"effects":[],"rectangles":[],"attachments":[],"ground_queries":[],"random_calls":0,"request":null}
	var existing: Array=example.get("houses",[]).duplicate(true)
	for house: Dictionary in existing:
		house["index"]=int(house.get("index",18))
		house["owner"]=int(house.get("owner",0))
	var ground := func(x: float,z: float) -> float:
		log["ground_queries"].append([x,z])
		return float(example.get("ground",6.0))
	var random_word := func() -> int:
		log["random_calls"]+=1
		return int(example.get("random_word",0))
	var unlocked := func(key: String) -> bool: return bool(example.get("biome_locked",true)) if key=="HousesBiomeLocked" else key in example.get("unlocks",["PlotsAppear"])
	var services := {
		"settlement":func(position: Array) -> int:
			check(position==actor["position"],"Settlement lookup must use the actor's complete position")
			log["operations"].append("settlement")
			return int(example.get("lookup_settlement",4294967295)),
		"food_enabled":func() -> bool:
			log["operations"].append("food_enabled")
			return bool(example.get("food_enabled",false)),
		"cost":func(input: Dictionary,mode: int) -> float:
			check(input==plot and mode==1,"Original ordinary construction must request mode-one plot food cost")
			log["operations"].append("cost")
			return float(example.get("cost",0.0)),
		"spend":func(amount: float) -> void:
			log["operations"].append(["spend",amount])
			economy["food"]-=amount,
		"factory":func(input: Dictionary,owner: int,settlement: int,kind: int,special: bool) -> Dictionary:
			log["operations"].append("allocate")
			if example.get("allocation_failed",false): return {}
			log["operations"].append("construct")
			log["request"]=Conversion.request(input,owner,kind,special,false,existing,definition["house_selection"],definition["plot_environment"],definition["plot_conversion_rules"],unlocked,ground,random_word)
			# Explicit constructor adapter, also used by the native comparison.
			# This test descriptor does not supply the unported house lifetime.
			var house := {"id":existing.size(),"identity":16777217|(owner<<29),"position":log["request"]["position"].slice(0,3),"size":input["size"]}
			log["operations"].append("attach")
			log["attachments"].append([house["id"],settlement])
			check(Conversion.release_plot(state,int(input["id"]),true,false),"Successful native factory creation must immediately release its source plot")
			return house,
		"payment_effect":func(_house: Dictionary,amount: float,a: int,b: int) -> void:
			log["operations"].append(["payment_effect",amount,a,b])
			log["operations"].append("payment_effect_finish"),
		"target":func(target: Dictionary,action: int) -> void:
			log["operations"].append("target")
			actor["target"]=target.duplicate(true)
			log["targets"].append({"identity":target["identity"],"house":target["building"],"position":target["position"],"flag":target["flag"],"action":action}),
		"transition":func(action: int) -> void:
			log["operations"].append("transition")
			log["transitions"].append(action)
			actor["action"]=action,
		"effect":func(_house: Dictionary,owner: int,category: int,event: int) -> void:
			log["operations"].append("effect")
			log["effects"].append([owner,category,event]),
		"rectangle":func(rectangle: Array) -> void:
			log["operations"].append("rectangle")
			log["rectangles"].append(rectangle)}
	log["started"]=Start.start(actor,plot,int(example.get("kind",0)),bool(example.get("special",false)),definition["build_start_rules"],services)
	log["registry"]=Registry.snapshot(state)
	log["dirty"]=[]
	for index in range(1024):
		if state["schedule"]["dirty"].has(str(index)): log["dirty"].append(index)
	var paid := 0.0
	for operation: Variant in example["expected"]["operations"]:
		if operation is Array and operation[0]=="spend": paid+=float(operation[1])
	check(economy["food"]==100.0-paid,"Native payment must survive allocation failure, including zero/negative supplied costs")
	check(actor["action"]==(int(log["transitions"][0]) if log["started"] else 102),"The follower must transition only after a successful factory result")
	return log


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_build_start.json"))
	var definition: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()["story"]
	check(Start.valid_rules(definition["build_start_rules"]),"Construction actions must be injected from the original executable")
	for example: Dictionary in fixture["cases"]:
		var expected: Dictionary=example["expected"].duplicate(true)
		if expected["request"]!=null:
			for i in range(4): expected["request"]["position"][i]=Terrain.f32(float(expected["request"]["position"][i]))
		var observed := execute(example,definition,false)
		check(Numbers.canonical_numbers(observed)==Numbers.canonical_numbers(expected),"Original %s construction-start operations and state must match"%example["name"])
		check(Numbers.canonical_numbers(observed)==Numbers.canonical_numbers(execute(example,definition,true)),"Source %s construction must preserve exact save-codec continuation"%example["name"])
	check(not Start.start({}, {},0,false,definition["build_start_rules"],{}),"Unavailable source services must reject before changing state")
	print("Original follower construction start: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
