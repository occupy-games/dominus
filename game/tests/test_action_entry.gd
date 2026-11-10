extends SceneTree

const Entry = preload("res://simulation/source_action_entry.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func execute(example: Dictionary,content: Dictionary,resume: bool) -> Dictionary:
	var actor := {"step":19,"entry_done":true,"has_channel":bool(example.get("has_channel",true)),"clip":99,"orientation":Terrain.f32(float(example.get("orientation",0.75))),"orientation_rate":Terrain.f32(float(example.get("orientation_rate",0.5))),"clip_duration":99.0,"clip_phase":3.0,"clip_time":7.25}
	var entry := {"update_type":int(example.get("update_type",0)),"loop":bool(example.get("loop",false))}
	if example.has("action"):
		entry=Entry.find(content,int(example["action"]),int(example["index"]))
		check(not entry.is_empty(),"Every captured source row must resolve through original action/index identities")
	if resume:
		var codec := preload("res://infrastructure/world_store.gd").new()
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"actor":actor,"entry":entry}))))
		actor=Entry.restore(saved["actor"])
		entry=saved["entry"]
	var unchanged: Dictionary=entry.duplicate(true)
	var log: Array=[]
	var services := {
		"resolve":func(input: Dictionary,local: Dictionary,profile: int) -> int:
			log.append(["resolve",int(input["step"]),bool(input["entry_done"]),profile])
			if example.has("resolve_loop"): local["loop"]=bool(example["resolve_loop"])
			return int(example.get("clip",14)),
		"duration":func(clip: int) -> float:
			log.append(["duration",clip])
			return float(example.get("duration",2.5)),
		"orientation":func(value: float,rate: float) -> void: log.append(["orientation",value,rate]),
		"animate":func(clip: int,loop: bool,speed: float,blend: float) -> void: log.append(["animate",clip,loop,speed,blend])}
	var result := Entry.enter(actor,int(example.get("index",0)),int(example.get("profile",4)),entry,content["rules"],services)
	result["actor"]=actor
	result["log"]=log
	check(entry==unchanged,"Source clip resolution must not mutate the original state entry")
	var expected: Dictionary=example["expected"].duplicate(true)
	for key: String in ["orientation","orientation_rate","clip_duration","clip_phase","clip_time"]: expected["actor"][key]=Terrain.f32(float(expected["actor"][key]))
	for item: Array in expected["log"]:
		if item[0]=="orientation":
			for i in range(1,3): item[i]=Terrain.f32(float(item[i]))
	check(Numbers.canonical_numbers(result)==Numbers.canonical_numbers(expected),"Original %s entry state, call order and presentation intents must match"%example["name"])
	var before: Dictionary=actor.duplicate(true)
	check(Entry.enter(actor,0,0,entry,content["rules"],{}).is_empty() and actor==before,"Unavailable entry services must reject before clearing timings")
	return result


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_action_entry.json"))
	var content := preload("res://infrastructure/action_entry.gd").load_content(str(fixture["executable_sha256"]),str(fixture["source_sha256"]))
	check(Entry.valid_content(content),"The source entry configuration must load with executable/table provenance")
	for example: Dictionary in fixture["cases"]:
		check(Numbers.canonical_numbers(execute(example,content,false))==Numbers.canonical_numbers(execute(example,content,true)),"Original %s entry must preserve exact-number continuation"%example["name"])
	print("Original action entry: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
