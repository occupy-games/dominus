extends SceneTree

const Selection = preload("res://simulation/source_weighted_rewards.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var word := 0
var calls := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func random_word() -> int:
	calls+=1
	return word


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_weighted_rewards.json")))
	for case: Dictionary in fixture["cases"]:
		word=int(case["word"])
		calls=0
		var entries: Array=case["entries"].duplicate(true)
		var value: Variant=Selection.choose(entries,int(case["total"]),int(case["override"]),random_word)
		check(value==case["expected"]["value"] and calls==case["expected"]["random_calls"],"Original draw and RNG consumption must match "+case["name"])
		check(entries==case["entries"],"A draw must not mutate the candidate bag")
	for era: Dictionary in fixture["eras"]:
		check(Selection.era_bucket(int(era["value"]))==int(era["bucket"]),"Original era bucket conversion")
		check(Selection.bucket_era(int(era["value"]))==int(era["era"]),"Original bucket era conversion")
	calls=0
	check(Selection.choose([],0,0,random_word)==0 and calls==1,"Empty draws consume one original word")
	calls=0
	check(Selection.choose([],0,65536,random_word)==0 and calls==0,"A nonzero override with zero low bits still bypasses RNG")
	check(Selection.choose([{"weight":1,"value":"Sticker_Tools_1"}],1,1,Callable())=="Sticker_Tools_1","Resolved source names may replace native hash tokens")
	check(not Selection.valid([{"weight":-1,"value":1}],1,0),"Invalid injected weight must reject")
	print("Original weighted rewards: %d draws, %d era values, %d failures"%[fixture["cases"].size(),fixture["eras"].size(),failures])
	quit(1 if failures else 0)
