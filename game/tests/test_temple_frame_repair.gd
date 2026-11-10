extends "res://tests/test_temple_frame.gd"

var repair_rules: Dictionary={}


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_frame_repair.json"


func test_name() -> String:
	return "Original temple frame and repair"


func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path()))
	var research: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/research-rules.json"))
	repair_rules=preload("res://infrastructure/temple_repair.gd").load_rules(data["executable_sha256"],research["source_sha256"])
	check(not repair_rules.is_empty(),"Composed temple repair rules require matching source provenance")
	if repair_rules.is_empty(): quit(1); return
	super._initialize()


func service(name: String,args: Array) -> Variant:
	var value: Variant=super.service(name,args)
	if name in ["is_dock","is_pit","is_ark"]: return bool(example.get(name,false))
	if name=="ark_followers": return example.get("followers",[]).duplicate(true)
	if name=="notification_context": return 12345
	if name=="completion_visual" and example.get("clear_reward_during_visual",false): current["reward"]=0
	return value


func advance_case() -> bool:
	ground_data=example.get("ground",{})
	queries=[]; events=[]
	var count := int(example.get("workers",1))
	var totals: Dictionary=example.get("totals",{"workers":count,"contributors":count,"skill_sum":1.0})
	var result := Frame.advance_repair(current,frame_rules,phase_rules,footprint_rules,repair_rules,totals,float(example.get("delta",.1)),int(example.get("mode",0)),int(example.get("player",0)),ground,world_ground,service)
	var complete := false
	for event: Array in events:
		if event[0]=="hook" and event[1][0]==repair_rules["complete_hook"]: complete=true
	check(result["completed"]==complete,"The composed completion result must match the actual source completion hook")
	return result["ok"]


func additional_checks() -> void:
	var before := current.duplicate(true)
	current["start_block"]=int(current["transition_mode"])+1
	var invalid := current.duplicate(true)
	example={}
	check(not advance_case() and current==invalid and events.is_empty() and queries.is_empty(),"Conflicting names for the same native state slot must reject before mutation")
	current=before
	example={"totals":{"workers":1,"contributors":1,"skill_sum":NAN}}
	check(not advance_case() and current==before and events.is_empty() and queries.is_empty(),"Invalid repair totals cannot partially advance the earlier terrain frame")
