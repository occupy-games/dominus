extends "res://tests/test_temple_terrain.gd"

const Propagation = preload("res://simulation/source_temple_propagation.gd")
const Effects = preload("res://simulation/source_temple_effects.gd")
var rules: Dictionary={}
var effect_content: Dictionary={}
var bases: Dictionary={}
var query_sites: Array=[]
var query_calls := 0
var free_head := 4095


func actor_masks() -> Dictionary:
	var result := {}
	for identity: String in current["actors"]:
		var actor: Dictionary=current["actors"][identity]
		result[identity]={"mask":actor["mask"].duplicate(),"extra_mask":actor["extra_mask"].duplicate()}
	return result


func query(tag: int,x: float,z: float,radius: float,a: int,b: int,c: int,d: int,e: int,f: int) -> Variant:
	events.append(["query",[tag,x,z,radius,a,b,c,d,e,f],actor_masks(),free_head])
	var handle := int(query_sites[query_calls]["handle"])
	query_calls+=1
	var result: Variant=example["candidates"].get(str(handle))
	return result.duplicate(true) if result is Array else null


func release(token: int) -> void:
	events.append(["release_candidate",[token],actor_masks(),free_head])
	free_head=token


func advance_case() -> bool:
	events=[]; query_calls=0; query_sites=[]
	for site: Dictionary in example["sites"]:
		if int(site["follower_modifiers"][0])!=0 or int(site["follower_modifiers"][1])!=0: query_sites.append(site)
	return Propagation.refresh(current,example["sites"],example.get("owners",{}),rules,query,release)


func compare_case(expected: Dictionary,label: String) -> void:
	check(Numbers.canonical_numbers(current)==Numbers.canonical_numbers(expected["state"]),label+" authoritative follower masks")
	check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]),label+" source query/release ordering: "+str(events)+" / "+str(expected["events"]))
	check(free_head==int(expected["free_head"]),label+" temporary candidate service continuation")
	for identity: String in current["actors"]:
		var actor: Dictionary=current["actors"][identity]
		for table: String in ["race","jobs"]:
			var before := actor.duplicate(true)
			var result := Effects.follower_from_mask(bases[table],actor["mask"],actor["extra_mask"],effect_content,table)
			check(Numbers.canonical_numbers(result.get("values"))==Numbers.canonical_numbers(expected["stats"][identity][table]),label+" propagated "+table+" stats for actor "+identity)
			if not result.is_empty(): result["mask"][0]=123; result["values"][0]=123
			check(actor==before,label+" a stat query cannot alter stored local/permanent masks")


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_propagation.json"))))
	effect_content=preload("res://infrastructure/temple_effects.gd").content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not effect_content.is_empty(),"Original propagation requires matched source stat metadata")
	if effect_content.is_empty(): quit(1); return
	rules=effect_content["propagation_rules"]
	check(Numbers.canonical_numbers(rules)==Numbers.canonical_numbers(fixture["rules"]),"Spatial request flags must come from the actual source routine")
	bases=fixture["base_rows"]
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=Propagation.restore(case["state"])
			if saved: current=Propagation.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			free_head=int(case.get("free_head",4095))
			check(advance_case(),"Valid original follower propagation "+str(case["name"]))
			compare_case(case["expected"],str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Propagation.restore(sequence["initial"]); free_head=int(sequence["free_head"])
			for index in range(sequence["steps"].size()):
				if index==save_at:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"actors":current,"free_head":free_head}))))
					current=Propagation.restore(saved["actors"]); free_head=int(saved["free_head"])
				example=sequence["steps"][index]
				current["followers"][0]["position"]=example["position"].duplicate()
				check(advance_case(),"Saved propagation must continue as a follower moves")
				compare_case(example["expected"],"Saved moving propagation")
				if save_at==0: steps+=1
	current=Propagation.restore(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	example=fixture["cases"][0].duplicate(true)
	current["followers"][0]["stats_ref"]=99
	var invalid := current.duplicate(true)
	check(not advance_case() and current==invalid and events.is_empty(),"Dangling stat references reject before masks clear or spatial services run")
	current=before.duplicate(true)
	example["sites"].append(example["sites"][0].duplicate(true))
	check(not advance_case() and current==before and events.is_empty(),"Duplicate active shrine identities reject before clearing")
	for changes: Dictionary in [{"mask":[-1,0]},{"extra_mask":[0,4294967296]}]:
		invalid=before.duplicate(true); invalid["actors"]["0"].merge(changes,true)
		check(Propagation.restore(invalid).is_empty(),"Malformed stored modifier words cannot restore")
	print("Original shrine propagation: %d native cases, %d moving steps, stored stat getters, saved continuation, %d failures"%[fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
