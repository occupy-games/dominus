extends SceneTree

const Controller = preload("res://simulation/source_action_controller.gd")
const Sequence = preload("res://simulation/source_action_sequence.gd")
const References = preload("res://simulation/source_target_references.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func reference(spec: Dictionary) -> Dictionary:
	return {"identity":int(spec.get("identity",16777217)),"entity":int(spec.get("entity",0)),"position":spec.get("position",[-1.0,-1.0]).duplicate(),"flag":true}


func execute(example: Dictionary,definition: Dictionary,resume: bool) -> Dictionary:
	var data: Dictionary=definition.duplicate(true)
	var identity := int(example.get("action",103))
	for action: Dictionary in data["action_controller"]["actions"]:
		if int(action["id"])!=identity: continue
		if example.has("looping"): action["looping"]=bool(example["looping"])
		for row: Dictionary in action["states"]:
			var override: Dictionary=example.get("overrides",{}).get(str(int(row["index"])),{})
			for key: String in ["end_skip","terminable","face_end"]:
				if override.has(key): row[key]=override[key]
	for row: Dictionary in data["action_entry"]["records"]:
		if int(row["action"])!=identity: continue
		var override: Dictionary=example.get("overrides",{}).get(str(int(row["index"])),{})
		for key: String in ["update_type","loop"]:
			if override.has(key): row[key]=override[key]
	for action: Dictionary in data["action_sequences"]["actions"]:
		if int(action["id"])!=identity: continue
		for row: Dictionary in action["states"]:
			var override: Dictionary=example.get("overrides",{}).get(str(int(row["index"])),{})
			for key: String in ["next","skip_to","skip_probability"]:
				if override.has(key): row[key]=override[key]
	var actor := {"step":int(example.get("begin",0)),"entry_done":true,"has_channel":bool(example.get("has_channel",true)),"clip":99,"orientation":0.75,"orientation_rate":0.5,"clip_duration":99.0,"clip_phase":3.0,"clip_time":7.25,
		"action":identity,"phase":int(example.get("phase",3)),"voice":int(example.get("voice",0)),"profile":int(example.get("profile",4)),"failed":bool(example.get("failed",false)),"native_slot":3,"gate_slot":7,"path_time":9.0,"position":example.get("position",[157.0,119.0,6.0]).duplicate(),
		"target":{} if example.get("null_target",false) else reference(example.get("target",{})),"cached_target":reference(example["cached"]) if example.has("cached") else {}}
	var context := {"houses":{"0":{"identity":int(example.get("house_identity",16777217)),"state":int(example.get("house_state",0)),"completion_state":int(example.get("completion_state",0))}},"plots":{}}
	var stream := {"state":int(example.get("seed",1))}
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"actor":actor,"stream":stream,"context":context}))))
		actor=Controller.restore(saved["actor"])
		stream=saved["stream"]
		context=saved["context"]
	var calls := {"log":[],"queries":[],"random_calls":0}
	var services := {
		"random_word":func() -> int:
			calls["random_calls"]+=1
			return Sequence.random_word(stream,data["action_sequences"]["rules"]),
		"check":func(index: int,_entry: Dictionary) -> Dictionary:
			calls["queries"].append(index)
			return {"valid":bool(example.get("checks",{}).get(str(index),true)),"lost":false},
		"resolve":func(input: Dictionary,_entry: Dictionary,profile: int) -> int:
			calls["log"].append(["resolve",int(input["step"]),bool(input["entry_done"]),profile])
			return int(example.get("clip",14)),
		"duration":func(clip: int) -> float:
			calls["log"].append(["duration",clip])
			return 2.5,
		"orientation":func(value: float,rate: float) -> void: calls["log"].append(["orientation",value,rate]),
		"animate":func(clip: int,loop: bool,speed: float,blend: float) -> void: calls["log"].append(["animate",clip,loop,speed,blend]),
		"end_sound":func(voice: int) -> void: calls["log"].append(["end_sound",voice]),
		"request_decision":func(input: Dictionary) -> void: calls["log"].append(["decision",int(input["step"]),int(input["phase"]),input["target"].get("identity")]),
		"reset_navigation":func() -> void: calls["log"].append(["reset_navigation"]),
		"target_position":func(_target: Dictionary) -> Array: return example.get("target_position",[160.0,122.0,6.0]),
		"face":func(direction: Array) -> void: calls["log"].append(["face",direction[0],direction[1],direction[2]])}
	var result := Controller.advance(actor,bool(example.get("first",false)),data,context,services)
	check(not result.is_empty(),"Original %s advancement must be available"%example["name"])
	result.merge(calls)
	result["actor"]=actor
	result["random_state"]=int(stream["state"])
	var expected: Dictionary=example["expected"].duplicate(true)
	for key: String in ["orientation","orientation_rate","clip_duration","clip_phase","clip_time","path_time"]: expected["actor"][key]=Terrain.f32(float(expected["actor"][key]))
	for i in range(3): expected["actor"]["position"][i]=Terrain.f32(float(expected["actor"]["position"][i]))
	for key: String in ["target","cached_target"]:
		if not expected["actor"][key].is_empty(): expected["actor"][key]=References.restore(expected["actor"][key])
	for item: Array in expected["log"]:
		if item[0] in ["orientation","face"]:
			for i in range(1,item.size()): item[i]=Terrain.f32(float(item[i]))
	check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(expected),"Original %s action/state advancement, reference effects and call order must match"%example["name"])
	if result.get("result",false):
		var before: Dictionary=actor.duplicate(true)
		check(Controller.advance(actor,false,data,context,{}).is_empty() and actor==before,"Missing advancement services must reject before changing state")
	return result


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_action_controller.json"))
	var executable := str(fixture["executable_sha256"])
	var source := str(fixture["source_sha256"])
	var definition := {"action_controller":preload("res://infrastructure/action_controller.gd").load_content(executable,source),"action_sequences":preload("res://infrastructure/action_sequences.gd").load_content(executable,source),"action_entry":preload("res://infrastructure/action_entry.gd").load_content(executable,source),"target_reference_rules":preload("res://infrastructure/target_references.gd").load_rules(executable)}
	check(Controller.valid_content(definition["action_controller"]),"Original controller flags must load with source provenance")
	check(Numbers.canonical_numbers(definition["action_controller"]["default_state"])==Numbers.canonical_numbers(fixture["default_state"]),"Controller fallback fields must match the actual native state constructor")
	for example: Dictionary in fixture["cases"]:
		var result := execute(example,definition,false)
		check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(execute(example,definition,true)),"Original %s advancement must preserve exact-number continuation"%example["name"])
		if example["name"]=="cached_same":
			var codec := preload("res://infrastructure/world_store.gd").new()
			var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(result["actor"]))))
			var restored := Controller.restore(saved)
			check(Numbers.canonical_numbers(restored)==Numbers.canonical_numbers(result["actor"]),"The completed controller transition must restore with its invalid target and cleared path state")
			restored["target"]["position"][0]=12.0
			check(result["actor"]["target"]["position"][0]==-1.0,"Restoring an actor must detach its target values")
			restored["target"]=reference({"identity":1})
			var unchanged: Dictionary=restored.duplicate(true)
			check(Controller.advance(restored,false,definition,{},{ }).is_empty() and restored==unchanged,"Unported reference kinds must stay unavailable without partial state changes")
	print("Original action controller: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
