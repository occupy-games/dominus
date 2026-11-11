extends "res://tests/test_house_build_time.gd"

const BaseStats = preload("res://simulation/source_house_base_stats.gd")
var base_content: Dictionary


func house_stats() -> Dictionary:
	var attachment: Variant=null
	if current["reference_attached"]:
		attachment={"kind":current["attached_kind"],"values":current["attached_values"]}
	return BaseStats.resolve(base_content,int(current["house_index"]),attachment).get("values",{})


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_house_base_stats.json")
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(raw)))
	var sha: String=fixture["executable_sha256"]
	var rules := Content.rules(sha)
	modifier_rules=Content.modifiers(sha)
	foundation_rules=preload("res://infrastructure/building_foundation.gd").rules(sha)
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	base_content=opening.get("story",{}).get("house_base_stats",{})
	check(BaseStats.valid(base_content),"Source campaign must receive the original stat rows and settlement routing")
	if failures:
		quit(1)
		return
	for case: Dictionary in fixture["cases"]:
		var expected: Dictionary=case["expected"]
		var index := int(case["index"])
		var row := BaseStats.resolve(base_content,index,case["attachment"])
		if int(expected["index"])<0:
			check(row.is_empty(),"A kind with no original settlement template must stay unavailable")
			continue
		check(row["index"]==expected["index"],"Original stat row index for house %d"%index)
		check(Numbers.canonical_numbers(row["values"])==expected["values"],"Original stat row values for house %d"%index)
		row["values"]["capacity"]=-100.0
		check(BaseStats.resolve(base_content,index,case["attachment"])["values"]["capacity"]!=-100.0,"A stat query must return detached values")
	for frame: Dictionary in fixture["frames"]:
		example=frame
		current=restore_after_save(frame["state"])
		live_modifiers=Modifiers.initial(modifier_rules)
		compare_step(rules,"Original selected-row frame for house %d"%int(current["house_index"]))
	check(BaseStats.resolve(base_content,-1).is_empty() and BaseStats.resolve(base_content,64).is_empty(),"Invalid ordinary row indices must reject")
	check(BaseStats.resolve(base_content,18,{"kind":1,"values":{"capacity":7.0}}).is_empty(),"A partial attachment cannot be interpreted as a real settlement row")
	print("Original house base stats: %d row cases, %d construction frames, %d failures"%[fixture["cases"].size(),fixture["frames"].size(),failures])
	quit(1 if failures else 0)
