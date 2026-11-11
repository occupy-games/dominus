extends "res://tests/test_house_terrain_frame.gd"

const BuildTime = preload("res://simulation/source_house_build_time.gd")
const Modifiers = preload("res://simulation/source_progression_modifiers.gd")
const Unlocks = preload("res://simulation/source_unlock_dispatch.gd")
const Hash = preload("res://simulation/source_hash.gd")

var modifier_rules: Dictionary
var live_modifiers: Dictionary


func house_stats() -> Dictionary:
	service("house_stats",[])
	return example["stats"]


func compare_step(rules: Dictionary,label: String) -> void:
	var unlocked := Unlocks.initial()
	for name: String in example["unlocked"]:
		Unlocks.insert(unlocked["unlocked"],Hash.text(name))
	var queries: Array=[]
	var has_unlock := func(name: String) -> bool:
		queries.append(name)
		return Unlocks.unlocked(unlocked,Hash.text(name))
	var effective_rules := modifier_rules.duplicate(true)
	for row: Dictionary in effective_rules["descriptors"]:
		if example.get("values",{}).has(row["unlock"]):
			row["value"]=example["values"][row["unlock"]]
	if example.get("reset",false):
		check(Modifiers.reset(live_modifiers,effective_rules),label+" must reset source modifier values")
	check(Modifiers.refresh(live_modifiers,effective_rules,has_unlock),label+" must refresh source modifiers")
	var expected: Dictionary=example["expected"]
	check(queries==expected["modifiers"]["queries"],label+" native unlock query order")
	check(Numbers.canonical_numbers(live_modifiers)==expected["modifiers"]["values"],label+" native live modifier values")
	var global_override := float(example.get("global_override",0.0))
	events=[]
	check(Frame.advance_with_build_time(current,rules,foundation_rules,0.25,live_modifiers,global_override,house_stats,service,overlay,ground),label+" must advance the composed frame")
	compare_case(expected,rules,label)
	check(BuildTime.resolve(current,live_modifiers,global_override,house_stats)==expected["target"],label+" native construction target")


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_house_build_time.json")
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(raw)))
	var sha: String=fixture["executable_sha256"]
	var rules := Content.rules(sha)
	modifier_rules=Content.modifiers(sha)
	foundation_rules=preload("res://infrastructure/building_foundation.gd").rules(sha)
	check(not rules.is_empty() and not modifier_rules.is_empty() and not foundation_rules.is_empty(),"Build time rules must match executable provenance")
	check(Content.modifiers("wrong").is_empty(),"Modifier rules must reject mismatched executable provenance")
	if failures:
		quit(1)
		return
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("progression_modifier_rules")==modifier_rules,"Source campaign must receive the original progression modifiers")
	for case: Dictionary in fixture["cases"]:
		example=case
		current=Frame.restore(case["state"])
		live_modifiers=Modifiers.initial(modifier_rules)
		compare_step(rules,case["name"])
	var sequence: Dictionary=fixture["sequence"]
	for save_at in range(sequence["steps"].size()):
		current=Frame.restore(sequence["initial"])
		live_modifiers=Modifiers.initial(modifier_rules)
		for index in range(sequence["steps"].size()):
			if index==save_at:
				current=restore_after_save(current)
				live_modifiers=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(live_modifiers))))
				check(Modifiers.valid(live_modifiers,modifier_rules),"Live modifier floats must survive save storage")
			example=sequence["steps"][index]
			current.merge(example["inputs"],true)
			compare_step(rules,"Build-time step %d, save at %d"%[index,save_at])
	var bad := modifier_rules.duplicate(true)
	bad["descriptors"][0]["value"]=NAN
	var prior := live_modifiers.duplicate()
	var called: Array=[]
	var query := func(name: String) -> bool:
		called.append(name)
		return true
	check(not Modifiers.refresh(live_modifiers,bad,query) and live_modifiers==prior and called.is_empty(),"Malformed modifiers must reject before queries or writes")
	print("Original house build time and modifiers: %d native cases, %d sequence steps, saved continuation, %d failures"%[fixture["cases"].size(),sequence["steps"].size(),failures])
	quit(1 if failures else 0)
