extends "res://tests/test_temple_terrain.gd"

const Frame = preload("res://simulation/source_temple_frame.gd")
var ground_data: Dictionary={}
var queries: Array=[]
var frame_rules: Dictionary={}
var phase_rules: Dictionary={}
var footprint_rules: Dictionary={}


func ground(x: int,z: int) -> float:
	var value := float(ground_data.get("values",{}).get("%d,%d"%[x,z],ground_data.get("default",0)))
	queries.append([x,z,value])
	return value


func world_ground(x: float,z: float,flag: int) -> float:
	service("world_ground",[x,z,flag])
	return float(example.get("world_ground",6.0))


func service(name: String,args: Array) -> Variant:
	var value: Variant=super.service(name,args)
	if name=="is_boat": return bool(example.get("boat",false))
	if name=="motion_locked": return bool(example.get("motion_locked",false))
	return value


func advance_case() -> bool:
	ground_data=example.get("ground",{})
	queries=[]; events=[]
	return Frame.advance(current,frame_rules,phase_rules,footprint_rules,int(example.get("workers",0)),float(example.get("delta",.1)),ground,world_ground,service)


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_frame.json"


func test_name() -> String:
	return "Original temple pre-work frame"


func additional_checks() -> void:
	pass


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string(fixture_path()))))
	var Content = preload("res://infrastructure/temple_terrain.gd")
	frame_rules=Content.frame_rules(fixture["executable_sha256"])
	phase_rules=Content.load_rules(fixture["executable_sha256"])
	footprint_rules=Content.footprint_rules(fixture["executable_sha256"])
	check(not frame_rules.is_empty() and not phase_rules.is_empty() and not footprint_rules.is_empty(),"The composed source frame must have verified metadata")
	check(Content.frame_rules("wrong").is_empty(),"Unmatched executable provenance must reject frame constants")
	if frame_rules.is_empty() or phase_rules.is_empty() or footprint_rules.is_empty(): quit(1); return
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("temple_frame_rules")==frame_rules,"The source campaign must receive the actual frame constants")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=Frame.restore(case["state"])
			if saved: current=Frame.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			check(advance_case(),"Valid native temple frame "+str(case["name"]))
			compare(case["expected"],"Native frame "+str(case["name"]))
			check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(case["expected"]["queries"]),"Native frame footprint sample order "+str(case["name"]))
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Frame.restore(sequence["initial"])
			for index in range(sequence["steps"].size()):
				if index==save_at: current=Frame.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
				example=sequence["steps"][index]
				check(advance_case(),"A saved temple frame must continue")
				compare(example["expected"],"Frame sequence")
				check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(example["expected"]["queries"]),"Restored frame footprint samples")
				if save_at==0: steps+=1
	current=Frame.restore(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	example={"workers":-1,"delta":.1}
	check(not advance_case() and current==before and events.is_empty() and queries.is_empty(),"An invalid worker count must reject before state or service changes")
	example={"workers":1,"delta":-1}
	check(not advance_case() and current==before and events.is_empty() and queries.is_empty(),"A negative frame delta must reject before state or service changes")
	for changes: Dictionary in [{"work_presence":NAN},{"height":INF},{"motion_handle":-1},{"cooldown":1e40},{"handle":65535}]:
		var invalid := before.duplicate(true)
		invalid.merge(changes,true)
		check(Frame.restore(invalid).is_empty(),"Invalid frame state must not restore")
	additional_checks()
	print("%s: %d native cases, %d sequence steps, saved continuation, %d failures"%[test_name(),fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
