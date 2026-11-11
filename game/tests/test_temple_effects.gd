extends "res://tests/test_temple_terrain.gd"

const Effects = preload("res://simulation/source_temple_effects.gd")
const Modifiers = preload("res://simulation/source_temple_modifiers.gd")
var content: Dictionary={}


func unlocked(id: int) -> bool:
	for identity: Variant in example.get("unlocked",[]):
		if int(identity)==id: return true
	return false


func modifier_service(_name: String,_args: Array) -> Variant:
	return null


func query(case: Dictionary) -> Dictionary:
	var rules := content.duplicate(true)
	rules["records"]=case["records"]
	var sites: Array=case["sites"].duplicate(true)
	if case.has("unlocked"):
		for site: Dictionary in sites:
			check(Modifiers.refresh(site,rules["records"],unlocked,modifier_service),"Source modifier refresh must feed stat collection")
	if case["table"]=="House Values": return Effects.house(case["base"],case["point"],sites,case.get("owners",{}),case["parameters"],rules)
	return Effects.follower(case["base"],case["point"],sites,case.get("owners",{}),case.get("extra_mask",[0,0]),rules,case["table"])


func compare_case(case: Dictionary,label: String) -> void:
	example=case
	var before := case.duplicate(true)
	var result := query(case)
	check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(case["expected"]),label+" source stat words and masks: "+str(result)+" / "+str(case["expected"]))
	check(case==before,label+" cannot mutate source rows, actor inputs, metadata or saved sites")
	if not result.is_empty():
		result["values"][0]=123; result["mask"][0]=123
		check(case==before,label+" must return detached stat words and masks")


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_effects.json"))))
	var Content = preload("res://infrastructure/temple_effects.gd")
	content=Content.content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Original shrine effect bindings must match source provenance")
	check(Content.content("wrong",fixture["source_sha256"]).is_empty(),"Unmatched shrine effect provenance rejects")
	if content.is_empty(): quit(1); return
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("temple_effects")==content,"The source campaign must receive original stat bindings and flags")
	for case: Dictionary in fixture["areas"]:
		check(Numbers.canonical_numbers(Effects.area(case["site"],case.get("owners",{})))==Numbers.canonical_numbers(case["expected"]),"The native inherited center/radius query must preserve missing owners")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		compare_case(case,str(case["name"]))
		var restored: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(case))))
		compare_case(restored,"Saved "+str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for case: Dictionary in sequence["steps"]:
			compare_case(case,"Moving actor query")
			var restored: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(case))))
			compare_case(restored,"Saved moving actor query")
			steps+=1
	var sample: Dictionary=fixture["cases"][0].duplicate(true)
	var invalid := sample.duplicate(true)
	invalid["sites"].append(invalid["sites"][0].duplicate(true))
	check(query(invalid).is_empty(),"Duplicate active shrine identities reject instead of applying a bonus twice")
	invalid=sample.duplicate(true); invalid["base"][0]=-1
	check(query(invalid).is_empty(),"Invalid raw stat words cannot be coerced to another source value")
	invalid=sample.duplicate(true); invalid["records"][0]["index"]=41
	check(query(invalid).is_empty(),"A modifier cannot write outside the original row layout")
	invalid=sample.duplicate(true); invalid["records"][0]["value"]=INF
	check(query(invalid).is_empty(),"Nonfinite effect metadata rejects before actor queries")
	print("Original shrine effects: %d areas, %d native stat cases, %d moving steps, saved queries, %d failures"%[fixture["areas"].size(),fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
