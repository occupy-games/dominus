extends "res://tests/test_temple_terrain.gd"

const Foundation = preload("res://simulation/source_building_foundation.gd")


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),int(current["uneven_count"])])
	return bool(example.get("overlay_available",false)) if name=="terrain_overlay" else null


func overlay(x: int,z: int) -> Dictionary:
	service("overlay",[x,z])
	var data: Dictionary=example.get("overlay",{})
	return data.get("values",{}).get("%d,%d"%[x,z],data.get("default",{"found":false,"height":0.0})).duplicate(true)


func ground(x: int,z: int) -> float:
	service("ground",[x,z])
	var data: Dictionary=example.get("ground",{})
	return float(data.get("values",{}).get("%d,%d"%[x,z],data.get("default",0.0)))


func advance_case(rules: Dictionary) -> bool:
	events=[]
	return Foundation.scan(current,rules,service,overlay,ground)


func compare_case(expected: Dictionary,rules: Dictionary,label: String) -> void:
	compare(expected,label)
	var region := Foundation.bounds(current,rules)
	check([region.position.x,region.position.y,region.size.x,region.size.y]==Numbers.canonical_numbers(expected["bounds"]),label+" native inclusive sample bounds")


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_building_foundation.json"))))
	var Content = preload("res://infrastructure/building_foundation.gd")
	var rules := Content.rules(fixture["executable_sha256"])
	check(not rules.is_empty(),"Original foundation constants must match executable provenance")
	check(Content.rules("wrong").is_empty(),"Mismatched foundation constants reject")
	if rules.is_empty(): quit(1); return
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("building_foundation_rules")==rules,"The source campaign receives the original foundation rules")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=Foundation.restore(case["state"])
			if saved: current=Foundation.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			check(advance_case(rules),"Valid original foundation scan "+str(case["name"]))
			compare_case(case["expected"],rules,str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Foundation.restore(sequence["initial"])
			for index in range(sequence["steps"].size()):
				if index==save_at: current=Foundation.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
				example=sequence["steps"][index]
				current["position"]=example["position"].duplicate()
				check(advance_case(rules),"A saved building foundation scan must continue")
				compare_case(example["expected"],rules,"Saved foundation")
				if save_at==0: steps+=1
	current=Foundation.restore(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	for changes: Dictionary in [{"anchor_step":2147483648},{"nav_size":1025},{"position":[NAN,0,0]},{"uneven_count":-1}]:
		var invalid := before.duplicate(true); invalid.merge(changes,true)
		check(Foundation.restore(invalid).is_empty(),"Invalid saved foundation state must reject")
	current["nav_size"]=1025
	var invalid := current.duplicate(true)
	check(not advance_case(rules) and current==invalid and events.is_empty(),"Invalid foundation dimensions cannot clear counters or query terrain")
	current=before.duplicate(true); current["nav_size"]=1
	example={"overlay_available":true,"overlay":{"default":{"found":true}},"ground":{"default":20.0}}
	check(not advance_case(rules),"A malformed successful override cannot masquerade as a fallback read")
	for event: Array in events: check(event[0]!="ground","A successful override never samples fallback terrain")
	print("Original building foundations: %d native cases, %d moving steps, saved continuation, %d failures"%[fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
