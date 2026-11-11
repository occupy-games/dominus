extends "res://tests/test_temple_frame_repair.gd"

const Lifecycle = preload("res://simulation/source_temple_lifecycle.gd")
var membership_rules: Dictionary={}
var clock_calls := 0
var random_calls := 0


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_lifecycle.json"


func test_name() -> String:
	return "Original temple lifecycle"


func restore_state(saved: Variant) -> Dictionary:
	return Lifecycle.restore(saved)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path()))
	var content := preload("res://infrastructure/temple_membership.gd").content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"The composed lifecycle needs matching affiliation metadata")
	if content.is_empty(): quit(1); return
	membership_rules=content["rules"]
	super._initialize()


func service(name: String,args: Array) -> Variant:
	var result: Variant=super.service(name,args)
	events[-1].append(int(current["settlement_id"]))
	events[-1].append(float(current["affiliation_due"]))
	if name=="refresh_modifiers":
		if example.has("modifiers_due"): current["affiliation_due"]=float(example["modifiers_due"])
		for field: String in example.get("modifiers_state",{}): current[field]=example["modifiers_state"][field]
	return result


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


func rules() -> Dictionary:
	return {"membership":membership_rules,"frame":frame_rules,"phase":phase_rules,"footprint":footprint_rules,"repair":repair_rules}


func advance_case() -> bool:
	ground_data=example.get("ground",{})
	queries=[]; events=[]; clock_calls=0; random_calls=0
	var count := int(example.get("workers",1))
	var totals: Dictionary=example.get("totals",{"workers":count,"contributors":count,"skill_sum":1.0})
	var result := invoke_lifecycle(totals)
	if example.has("expected"):
		check(result["refreshed"]==example["expected"]["refreshed"],"The whole frame must preserve the original affiliation deadline gate")
		check(clock_calls==int(example["expected"]["clock_calls"]) and random_calls==int(example["expected"]["random_calls"]),"The whole frame must preserve clock and RNG consumption")
	var complete := false
	for event: Array in events:
		if event[0]=="hook" and event[1][0]==repair_rules["complete_hook"]: complete=true
	check(result["completed"]==complete,"The whole lifecycle must report the actual completion hook")
	return result["ok"]


func invoke_lifecycle(totals: Dictionary) -> Dictionary:
	return Lifecycle.advance(current,rules(),example.get("sites",[]),example.get("owners",{}),totals,float(example.get("delta",.1)),int(example.get("mode",0)),int(example.get("player",0)),clock_value,word,ground,world_ground,service)


func additional_checks() -> void:
	super.additional_checks()
	var before := current.duplicate(true)
	for changes: Dictionary in [{"affiliation_due":INF},{"radius":NAN},{"settlement_id":-2},{"is_settlement":1}]:
		var invalid := before.duplicate(true); invalid.merge(changes,true)
		check(restore_state(invalid).is_empty(),"Invalid membership state must not restore as a complete lifecycle")
	example={"sites":[before,before]}
	check(not advance_case() and current==before and events.is_empty() and clock_calls==0 and random_calls==0,"Duplicate active identities reject before modifier, clock or RNG callbacks")
	example={}
	var previous := repair_rules.duplicate(true)
	repair_rules["exponent"]=NAN
	check(not advance_case() and current==before and events.is_empty() and clock_calls==0 and random_calls==0,"Invalid later work rules cannot partially advance earlier affiliation")
	repair_rules=previous
