extends "res://tests/test_temple_lifecycle.gd"

const Modifiers = preload("res://simulation/source_temple_modifiers.gd")


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_modified_lifecycle.json"


func test_name() -> String:
	return "Original modified temple lifecycle"


func restore_state(saved: Variant) -> Dictionary:
	var result := Lifecycle.restore(saved)
	return Modifiers.restore(result)


func service(name: String,args: Array) -> Variant:
	var result: Variant=super.service(name,args)
	events[-1].append({"follower_modifiers":current["follower_modifiers"].duplicate(),"house_modifiers":current["house_modifiers"].duplicate()})
	return result


func unlocked(id: int) -> bool:
	service("unlocked",[id])
	return id in example.get("unlocked",[])


func invoke_lifecycle(totals: Dictionary) -> Dictionary:
	return Lifecycle.advance_modifiers(current,rules(),example.get("records",[]),example.get("sites",[]),example.get("owners",{}),totals,float(example.get("delta",.1)),int(example.get("mode",0)),int(example.get("player",0)),clock_value,word,unlocked,ground,world_ground,service)


func additional_checks() -> void:
	super.additional_checks()
	var before := current.duplicate(true)
	example={"records":[{"type":1,"unlock":0,"family":2}]}
	check(not advance_case() and current==before and events.is_empty() and clock_calls==0 and random_calls==0,"Invalid modifier families reject before all lifecycle services")
