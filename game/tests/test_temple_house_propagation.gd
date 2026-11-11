extends "res://tests/test_temple_terrain.gd"

const Propagation = preload("res://simulation/source_temple_propagation.gd")
const Effects = preload("res://simulation/source_temple_effects.gd")
const Modifiers = preload("res://simulation/source_temple_modifiers.gd")
var content: Dictionary={}


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_house_propagation.json"


func test_name() -> String:
	return "Original house shrine propagation"


func restore_state(saved: Variant) -> Dictionary:
	return Propagation.restore_house(saved)


func additional_checks() -> void:
	pass


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),current["mask"].duplicate()])
	return null


func unlocked(id: int) -> bool:
	for identity: Variant in example.get("unlocked",[]):
		if int(identity)==id: return true
	return false


func modifier_service(_name: String,_args: Array) -> Variant:
	return null


func advance_case() -> bool:
	events=[]
	var sites: Array=example["sites"].duplicate(true)
	if example.has("unlocked"):
		for site: Dictionary in sites:
			check(Modifiers.refresh(site,example["records"],unlocked,modifier_service),"Original shrine unlock refresh must feed stored house masks")
	return Propagation.refresh_house(current,sites,example.get("owners",{}),service)


func compare_case(expected: Dictionary,label: String) -> void:
	check(Numbers.canonical_numbers(current)==Numbers.canonical_numbers(expected["state"]),label+" stored house masks")
	check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]),label+" geometry callback gate and ordering")
	var rules := content.duplicate(true); rules["records"]=example["records"]
	var before := current.duplicate(true)
	var result := Effects.house_from_mask(example["base"],current["mask"],example["parameters"],rules)
	check(Numbers.canonical_numbers(result.get("values"))==Numbers.canonical_numbers(expected["values"]),label+" original housing stats consume stored masks")
	if not result.is_empty(): result["mask"][0]=123; result["values"][0]=123
	check(current==before,label+" housing stat results cannot mutate source masks")


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string(fixture_path()))))
	content=preload("res://infrastructure/temple_effects.gd").content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"House propagation needs verified shrine stat metadata")
	if content.is_empty(): quit(1); return
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=restore_state(case["state"])
			if saved: current=restore_state(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			check(advance_case(),"Valid original house propagation "+str(case["name"]))
			compare_case(case["expected"],str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=restore_state(sequence["initial"])
			for index in range(sequence["steps"].size()):
				if index==save_at: current=restore_state(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
				example=sequence["steps"][index]
				current["position"]=example["point"].duplicate()
				check(advance_case(),"Saved house masks must continue through influence changes")
				compare_case(example["expected"],"Saved house influence")
				if save_at==0: steps+=1
	current=restore_state(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	example=fixture["cases"][0].duplicate(true)
	example["sites"].append(example["sites"][0].duplicate(true))
	check(not advance_case() and current==before and events.is_empty(),"Duplicate source sites cannot clear house masks or refresh geometry")
	for changes: Dictionary in [{"position":[NAN,0,0]},{"reference_attached":1},{"mask":[-1,0]}]:
		var invalid := before.duplicate(true); invalid.merge(changes,true)
		check(restore_state(invalid).is_empty(),"Malformed source house propagation state rejects")
	additional_checks()
	print("%s: %d native cases, %d moving steps, stored stat getter, saved continuation, %d failures"%[test_name(),fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
