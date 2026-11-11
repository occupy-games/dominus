extends "res://tests/test_temple_terrain.gd"

const Modifiers = preload("res://simulation/source_temple_modifiers.gd")


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),{"follower_modifiers":current["follower_modifiers"].duplicate(),"house_modifiers":current["house_modifiers"].duplicate()}])
	return null


func unlocked(id: int) -> bool:
	service("unlocked",[id])
	return id in example["unlocked"]


func advance_case() -> bool:
	events=[]
	return Modifiers.refresh(current,example["records"],unlocked,service)


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_modifiers.json"))))
	var Content = preload("res://infrastructure/temple_modifiers.gd")
	var records := Content.records(fixture["executable_sha256"],fixture["source_sha256"])
	check(records.size()==8,"The eight actual shrine upgrades must retain source order and unlock identities")
	check(Content.records("wrong",fixture["source_sha256"]).is_empty(),"Mismatched modifier metadata must reject")
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("temple_modifiers")==records,"The source campaign must receive its original modifier records")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=Modifiers.restore(case["state"])
			if saved: current=Modifiers.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			check(advance_case(),"Valid source modifier refresh "+str(case["name"]))
			compare(case["expected"],"Native modifier "+str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Modifiers.restore(sequence["initial"])
			for index in range(sequence["steps"].size()):
				if index==save_at: current=Modifiers.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
				example=sequence["steps"][index]
				check(advance_case(),"Restored modifier masks must continue")
				compare(example["expected"],"Saved modifier sequence")
				if save_at==0: steps+=1
	current=Modifiers.restore(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	for changes: Dictionary in [{"generic_type":0},{"follower_modifiers":[-1,0]},{"house_modifiers":[0,4294967296]},{"follower_modifiers":[0]},{"x":NAN}]:
		var invalid := before.duplicate(true); invalid.merge(changes,true)
		check(Modifiers.restore(invalid).is_empty(),"Invalid stored modifier masks must reject")
	example={"records":[{"type":0,"unlock":0,"family":0}],"unlocked":[]}
	check(not advance_case() and current==before and events.is_empty(),"Unresolved modifier types cannot clear saved masks or query unlocks")
	print("Original temple modifiers: %d native cases, %d sequence steps, saved continuation, %d failures"%[fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
