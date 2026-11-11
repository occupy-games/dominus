extends "res://tests/test_house_base_stats.gd"

const Stats = preload("res://simulation/source_house_stats.gd")
const EnvironmentBuffs = preload("res://simulation/source_house_environment.gd")
const EnvironmentContent = preload("res://infrastructure/house_environment.gd")


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_house_environment.json")
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(raw)))
	var source := EnvironmentContent.records(fixture["executable_sha256"],fixture["source_sha256"])
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var definition: Dictionary=opening.get("story",{})
	check(source.size()==6 and source==definition.get("house_environment"),"The campaign must load the six original environment buffs")
	check(EnvironmentContent.records("wrong",fixture["source_sha256"]).is_empty(),"Mismatched environment executable provenance must reject")
	check(EnvironmentContent.records(fixture["executable_sha256"],"wrong").is_empty(),"Mismatched environment table provenance must reject")
	if failures:
		quit(1)
		return
	for index in range(fixture["contributions"].size()):
		var item: Dictionary=fixture["contributions"][index]
		var result := EnvironmentBuffs.contribution(item["record"],float(item["sample"]))
		check(result==item["expected"],"Original buff contribution %d: %s / %s"%[index,result,item["expected"]])
	var original_base: Dictionary=definition["house_base_stats"]
	for index in range(fixture["stats"].size()):
		var case: Dictionary=fixture["stats"][index]
		var house := restore_after_save(case["house"])
		var attachment: Variant=null
		if house["reference_attached"]:
			attachment={"kind":house["attached_kind"],"values":house["attached_values"]}
		var base := BaseStats.resolve(original_base,int(house["house_index"]),attachment)
		var edited := original_base.duplicate(true)
		edited["rows"][int(base["index"])]["values"].merge(case["row_values"],true)
		definition["house_base_stats"]=edited
		definition["house_environment"]=source if Numbers.canonical_numbers(source)==case["records"] else case["records"]
		var unlocked := Unlocks.initial()
		for name: String in case["unlocked"]:
			Unlocks.insert(unlocked["unlocked"],Hash.text(name))
		var gates: Array=[]
		var query := func(name: String) -> bool:
			var id := Hash.text(name)
			gates.append(id)
			return Unlocks.unlocked(unlocked,id)
		var prior := house.duplicate(true)
		var result := Stats.resolve(definition,house,attachment,query)
		check(house==prior,"A house stat query must preserve the house and its stored shrine mask")
		check(gates==case["expected"]["gates"],"Original environment unlock query order in case %d"%index)
		check(not result.is_empty(),"The original stat row must resolve in case %d"%index)
		for field: String in case["expected"]["values"]:
			var found: Variant=result.get("values",{}).get(field)
			check(found==case["expected"]["values"][field],"Original %s in case %d: %s / %s"%[field,index,found,case["expected"]["values"][field]])
	print("Original environment buffs: %d contributions, %d native stat queries, %d failures"%[fixture["contributions"].size(),fixture["stats"].size(),failures])
	quit(1 if failures else 0)
