extends "res://tests/test_selected_rewards.gd"


func fixture_path() -> String:
	return "res://tests/fixtures/source_unlocked_rewards.json"


func check_name() -> String:
	return "Original unlocked rewards"


func bad_clock(name: String,args: Array) -> Variant:
	if name=="claim_clock": return {"seconds":-1,"millis":[0,0]}
	events.append([name,args])
	return null


func extra_checks(base: Dictionary) -> void:
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/unlock-dispatch.json"))
	var source := preload("res://infrastructure/unlock_dispatch.gd").content(metadata["executable_sha256"],metadata["source_sha256"],example["scope"])
	var rules := base.duplicate(true)
	rules["unlock"]=source["rules"]
	state["queue"]["queue"]=[{"kind":0,"reason":8,"source_id":1012,"reward":int(example["records"]["cards"][0]["id"]),"flags":2,"taken":true,"display":false}]
	var before := state.duplicate(true)
	var cursor := random_calls
	events=[]
	var availability_events: Array=[]
	check(not Rewards.consume(state,example["records"],rules,0,0,word,bad_clock,availability_events),"An invalid injected claim clock must reject redemption before consumption")
	check(state==before and random_calls==cursor and events.is_empty() and availability_events.is_empty(),"Rejected redemption cannot pop inventory, emit effects or consume RNG")
	check(not Rewards.request(state,example["records"],rules,17,1012,0,8,0,0,word,bad_clock,availability_events) and state==before and random_calls==cursor,"Invalid clocks must reject reward dispatch before mutations too")
	var cyclic := source.duplicate(true)
	cyclic["dependencies"]=[{"unlock":7,"condition":7,"phase":1}]
	check(not Rewards.prepare_unlocks(state,cyclic) and state==before,"Rejected dependency preparation cannot replace existing progress")
	var detached := Rewards.restore(state)
	detached["unlock_dispatch"]["received"].clear()
	check(state==before,"Restored acquisition state must detach all mutable dependency storage")
