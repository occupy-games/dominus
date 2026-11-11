extends "res://tests/test_house_environment.gd"

const Surroundings = preload("res://simulation/source_house_surroundings.gd")
const HousePool = preload("res://simulation/source_house_pool.gd")
var surroundings_pool: Dictionary
var field_values: Array
var refresh_case: Dictionary
var refresh_events: Array


func query(house_id: int,request: Array) -> Array:
	var counts: Array=surroundings_pool["slots"][str(house_id)]["nearby"]
	refresh_events.append(["query",house_id,request,counts.duplicate()])
	return refresh_case["objects"].get(str(house_id),[])


func release(house_id: int,node: int) -> void:
	refresh_events.append(["release",house_id,node])


func field(name: String,x: int,z: int) -> float:
	refresh_events.append([name,x,z])
	var index := posmod(x*3+z*5+int(refresh_case["phase"]),field_values.size())
	return float(field_values[index]) if name=="beauty" else 0.0


func compare_refresh(definition: Dictionary,step: Dictionary,label: String) -> void:
	refresh_case=step
	refresh_events=[]
	for key: String in step["radii"]:
		definition["house_base_stats"]["rows"][int(key)]["values"]["visionradius"]=float(step["radii"][key])
	definition["house_environment"]=step["records"]
	var gates := Unlocks.initial()
	Unlocks.insert(gates["unlocked"],Hash.text("AlwaysUnlocked"))
	var unlocked := func(name: String) -> bool:
		return Unlocks.unlocked(gates,Hash.text(name))
	var services := {"unlocked":unlocked,"query":query,"release":release,"field":field}
	check(Surroundings.refresh_pool(surroundings_pool,definition,{},services,step["area"]),label+" must refresh")
	check(Numbers.canonical_numbers(surroundings_pool)==step["expected"]["pool"],label+" must match native surroundings state")
	check(Numbers.canonical_numbers(refresh_events)==step["expected"]["events"],label+" must match native callback order")


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_house_surroundings.json")
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(raw)))
	field_values=fixture["fields"]
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var definition: Dictionary=opening.get("story",{}).duplicate(true)
	check(Surroundings.valid_rules(definition.get("house_surroundings_rules")),"Source campaign must receive the original surroundings rules")
	if failures:
		quit(1)
		return
	var index := 0
	for step: Dictionary in fixture["cases"]:
		surroundings_pool=HousePool.restore(step["initial"])
		compare_refresh(definition,step,"Surroundings case %d"%index)
		index+=1
	var sequence: Dictionary=fixture["sequence"]
	for save_at in range(sequence["steps"].size()):
		surroundings_pool=HousePool.restore(sequence["initial"])
		for step_index in range(sequence["steps"].size()):
			if save_at==step_index:
				var saved := JSON.stringify(codec.encode_numbers(surroundings_pool))
				surroundings_pool=HousePool.restore(codec.decode_numbers(JSON.parse_string(saved)))
			compare_refresh(definition,sequence["steps"][step_index],"Surroundings step %d, save at %d"%[step_index,save_at])
	print("Original house surroundings: %d refresh cases, %d sequence steps, saved continuation, %d failures"%[fixture["cases"].size(),sequence["steps"].size(),failures])
	quit(1 if failures else 0)
