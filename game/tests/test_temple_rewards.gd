extends "res://tests/test_unlocked_rewards.gd"


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_rewards.json"


func check_name() -> String:
	return "Original temple rewards"


func extra_checks(base: Dictionary) -> void:
	super.extra_checks(base)
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/unlock-dispatch.json"))
	var source := preload("res://infrastructure/unlock_dispatch.gd").content(metadata["executable_sha256"],metadata["source_sha256"],example["scope"])
	var rules := base.duplicate(true)
	rules["unlock"]=source["rules"]
	var temple_rules := preload("res://infrastructure/temple_repair.gd").load_rules(metadata["executable_sha256"],metadata["source_sha256"])
	var temple: Dictionary=example["temple"].duplicate(true)
	temple["reward_pending"]=1
	temple["reward_ready"]=true
	var before := state.duplicate(true)
	var original := temple.duplicate(true)
	var output: Array=[]
	var cursor := random_calls
	events=[]
	check(not Rewards.temple_pending(state,temple,example["records"],rules,temple_rules,0,word,bad_clock,output),"Invalid claim time must reject before consuming a temple's pending reward")
	check(state==before and temple==original and events.is_empty() and output.is_empty() and random_calls==cursor,"Rejected temple delivery must preserve flags, inventory and the source RNG")
	check(not Rewards.force_unlock(state,rules,17,{"seconds":-1,"millis":[0,0]},service,output) and state==before,"Invalid marker input must reject before registering stock limits")
	temple["reward"]="Pack_BigTreasure1"
	original=temple.duplicate(true)
	check(not Rewards.temple_pending(state,temple,example["records"],rules,temple_rules,0,word,service,output) and temple==original and state==before,"An unresolved textual reward must not be coerced to numeric zero or consume pending flags")
