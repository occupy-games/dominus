extends "res://tests/test_temple_terrain.gd"

const Membership = preload("res://simulation/source_temple_membership.gd")
var clock_calls := 0
var random_calls := 0


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),int(current["settlement_id"]),float(current["affiliation_due"])])
	if name=="refresh_modifiers" and example.has("modifiers_due"): current["affiliation_due"]=float(example["modifiers_due"])
	return null


func clock_value(mode: int) -> float:
	service("clock",[mode])
	var times: Array=example.get("times",[0.0])
	var value := float(times[mini(clock_calls,times.size()-1)])
	clock_calls+=1
	return value


func word() -> int:
	service("random_word",[])
	random_calls+=1
	return int(example.get("word",0))


func advance_case(rules: Dictionary) -> Dictionary:
	events=[]; clock_calls=0; random_calls=0
	return Membership.refresh(current,example.get("sites",[]),example.get("owners",{}),rules,clock_value,word,service)


func compare_membership(expected: Dictionary,label: String) -> void:
	check(Numbers.canonical_numbers(current)==Numbers.canonical_numbers(expected["state"]),label+" state")
	check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]),label+" clock/RNG/service ordering: "+str(events)+" / "+str(expected["events"]))
	check(clock_calls==int(expected["clock_calls"]) and random_calls==int(expected["random_calls"]),label+" clock/RNG consumption")


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_membership.json"))))
	var Content = preload("res://infrastructure/temple_membership.gd")
	var content := Content.content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Original affiliation metadata must match source provenance")
	check(Content.content("wrong",fixture["source_sha256"]).is_empty(),"Mismatched affiliation provenance must reject")
	if content.is_empty(): quit(1); return
	var rules: Dictionary=content["rules"]
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening["story"]["temple_membership_rules"]==rules and opening["story"]["temple_membership_radii"]==content["radii"],"The source campaign must receive exact affiliation cadence and radius records")
	for case: Dictionary in fixture["geometry"]:
		check(Membership.contains(case["site"],case["point"],case.get("owners",{}))==case["expected"],"Native temple containment "+str(case["name"]))
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=Membership.restore(case["state"])
			if saved: current=Membership.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			var result := advance_case(rules)
			check(result["ok"] and result["refreshed"]==case["expected"]["refreshed"],"Native affiliation status "+str(case["name"]))
			compare_membership(case["expected"],str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Membership.restore(sequence["initial"])
			for index in range(sequence["steps"].size()):
				if index==save_at: current=Membership.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
				example=sequence["steps"][index]
				var result := advance_case(rules)
				check(result["ok"] and result["refreshed"]==example["expected"]["refreshed"],"A restored affiliation clock must advance")
				compare_membership(example["expected"],"Saved affiliation")
				if save_at==0: steps+=1
	current=Membership.restore(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	var repeated: Dictionary=fixture["cases"][0]["sites"][0]
	example={"sites":[repeated,repeated]}
	check(not advance_case(rules)["ok"] and current==before and events.is_empty() and clock_calls==0 and random_calls==0,"A duplicate active identity cannot mutate affiliation or consume clock/RNG")
	for changes: Dictionary in [{"affiliation_due":INF},{"radius":NAN},{"handle":65535},{"settlement_id":-2}]:
		var invalid := before.duplicate(true); invalid.merge(changes,true)
		check(Membership.restore(invalid).is_empty(),"Invalid affiliation state must reject before restoration")
	print("Original temple membership: %d geometry cases, %d affiliation cases, %d sequence steps, saved continuation, %d failures"%[fixture["geometry"].size(),fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
