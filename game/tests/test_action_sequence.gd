extends SceneTree

const Sequence = preload("res://simulation/source_action_sequence.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func execute(example: Dictionary,content: Dictionary,resume: bool) -> Dictionary:
	var states: Array=[]
	if example.has("action"): states=Sequence.entries(content,int(example["action"]))
	else:
		for i in range(int(content["rules"]["capacity"])): states.append(content["default_state"].duplicate(true))
	for key: String in example.get("overrides",{}): states[int(key)].merge(example["overrides"][key],true)
	var stream := {"state":int(example.get("seed",1))}
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"states":states,"stream":stream}))))
		states=saved["states"]
		stream=saved["stream"]
	var before: Array=states.duplicate(true)
	var calls := {"queries":[],"random_calls":0}
	var random := func() -> int:
		calls["random_calls"]+=1
		return Sequence.random_word(stream,content["rules"])
	var predicate := func(index: int,entry: Dictionary) -> Dictionary:
		calls["queries"].append(index)
		entry.merge(example.get("mutate",{}).get(str(index),{}),true)
		return {"valid":bool(example.get("checks",{}).get(str(index),true)),"lost":example.get("lose_at",[]).any(func(value: Variant) -> bool: return int(value)==index)}
	var result := Sequence.choose(states,int(example.get("begin",0)),content["rules"],random,predicate)
	check(not result.is_empty(),"Original %s state selection must be available"%example["name"])
	check(states==before,"Native state checks must receive a detached by-value entry")
	result.merge(calls)
	result["random_state"]=int(stream["state"])
	check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(example["expected"]),"Original %s state selection, validity order and seeded random continuation must match"%example["name"])
	return result


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_action_sequence.json"))
	var content := preload("res://infrastructure/action_sequences.gd").load_content(str(fixture["executable_sha256"]),str(fixture["source_sha256"]))
	check(Sequence.valid_content(content),"Original action identities and controls must load with source provenance")
	for key: String in fixture["default"]: check(content["default_state"][key]==fixture["default"][key],"Unspecified state field %s must match the actual native constructor"%key)
	for example: Dictionary in fixture["cases"]:
		check(Numbers.canonical_numbers(execute(example,content,false))==Numbers.canonical_numbers(execute(example,content,true)),"Original %s must survive exact-number continuation"%example["name"])
	check(Sequence.entries(content,103)[0]["name"]=="Move" and Sequence.entries(content,108)[0]["name"]=="Move" and Sequence.entries(content,111)[0]["name"]=="Move","All three source build jobs must begin with their original movement state")
	for action: Dictionary in content["actions"]:
		if action["name"] in ["FountainCelebrate","AstariTaunt1"]: check(Sequence.entries(content,int(action["id"])).is_empty(),"Unresolved blank source controls must remain unavailable")
	var stream := {"state":1}
	check(Sequence.choose([],0,content["rules"],func() -> int: return Sequence.random_word(stream,content["rules"]),func(_index: int,_entry: Dictionary) -> Dictionary: return {"valid":true,"lost":false}).is_empty() and stream["state"]==1,"Malformed sequences must reject before consuming random state")
	print("Original action sequence: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
