extends SceneTree

const Registry = preload("res://simulation/source_plot_registry.gd")
const Numbers = preload("res://simulation/progression.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_registry.json"))
	# Native slot fields are IEEE float32. JSON's decimal parser can move the
	# exact captured value by one double ULP; restore its original storage type.
	fixture["progress_rate"]=Terrain.f32(float(fixture["progress_rate"]))
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/plot-resize-rules.json"))
	var rules := preload("res://infrastructure/plot_resize.gd").load_rules(metadata["executable_sha256"])
	check(float(rules["progress_rate"])==float(fixture["progress_rate"]),"The injected lifetime rate must match original float32-promoted native data")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for example: Dictionary in fixture["cases"]:
		var state := Registry.initial()
		var continued := {}
		for plot: Dictionary in example.get("plots",[{"id":0,"x":160,"z":120,"size":4,"claimed":false}]):
			var id := Registry.allocate(state,float(plot["x"]),float(plot["z"]),int(plot["size"]),6.0)
			state["slots"][id]["claimed"]=plot["claimed"]
			state["slots"][id]["stored_size"]=int(plot["size"])
			state["slots"][id]["progress"]=float(example.get("progress",1.0))
		var bounds: Array=example["bounds"].duplicate()
		var loaded := func(x: int,z: int) -> bool: return x>=int(bounds[0]) and x<int(bounds[2]) and z>=int(bounds[1]) and z<int(bounds[3])
		var masks := {}
		for key: String in ["nonflat","scenery","blocked"]:
			masks[key]={}
			for point: Array in example.get(key,[]):masks[key][int(point[1])*1024+int(point[0])]=true
		var fields := func(x: int,z: int) -> Dictionary:
			var cell := z*1024+x
			return {"flat":loaded.call(x,z) and not masks["nonflat"].has(cell),"scenery":masks["scenery"].has(cell),"blocked":masks["blocked"].has(cell),
				"map_byte":0,"blight":0.0,"biome_allowed":true,"eligible":loaded.call(x,z)}
		var sizes: Array=[]
		for band in range(3):sizes.append([int(example.get("minimum",2)),int(example.get("maximum",8))])
		for step in range(example["steps"].size()):
			var command: Dictionary=example["steps"][step]
			if command.has("region"):
				if example["name"]=="empty" and step==0:
					var limits := {"sizes":sizes,"minimum":2,"maximum":8,"biomes":1}
					state["schedule"]={"limits":limits.duplicate(true),"dirty":{"133":true}}
					Registry.maintain(state,rules,limits,fields,loaded,func(_x: int,_z: int) -> int: return 0,func(_x: int,_z: int) -> float: return 6.0)
					check(state["schedule"]["dirty"].is_empty(),"Source schedule dispatch must run the complete region body and clear its bit")
				else: Registry.region(state,Vector2i(int(command["region"][0]),int(command["region"][1])),rules,sizes,fields,loaded,func(_x: int,_z: int) -> int: return 0,func(_x: int,_z: int) -> float: return 6.0)
				if not continued.is_empty(): Registry.region(continued,Vector2i(int(command["region"][0]),int(command["region"][1])),rules,sizes,fields,loaded,func(_x: int,_z: int) -> int: return 0,func(_x: int,_z: int) -> float: return 6.0)
			elif command.has("delta"):
				Registry.advance(state,float(command["delta"]),float(rules["progress_rate"]))
				if not continued.is_empty(): Registry.advance(continued,float(command["delta"]),float(rules["progress_rate"]))
			else:
				if command.has("bounds"): bounds.assign(command["bounds"])
				masks["nonflat"]={}
				for point: Array in command["nonflat"]: masks["nonflat"][int(point[1])*1024+int(point[0])]=true
			var actual := Registry.snapshot(state)
			var expected: Dictionary=example["states"][step]
			for plot: Dictionary in expected["plots"]:
				for field: String in ["x","z","height","progress"]: plot[field]=Terrain.f32(float(plot[field]))
			check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(expected),"Original %s plot registry at step %d must match"%[example["name"],step])
			check(Registry.valid(state),"The native %s plot registry must retain valid pool/ownership state at step %d"%[example["name"],step])
			if not continued.is_empty(): check(continued==state,"Restored %s registry must continue with identical identities, progress and ownership"%example["name"])
			else:
				continued=Registry.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state)))))
				check(not continued.is_empty(),"In-flight native plot state must restore through the save numeric codec")
			var detached := Registry.snapshot(state)
			if not detached["plots"].is_empty(): detached["plots"][0]["size"]=0
			check(Registry.snapshot(state)==actual,"Plot presentation snapshots must not mutate the authoritative registry")
		var invalid := state.duplicate(true)
		invalid["free"].append(0)
		check(Registry.restore(invalid).is_empty(),"Duplicate or excess free identities must reject")
		invalid=state.duplicate(true)
		invalid["owners"]["0"]=1024
		check(Registry.restore(invalid).is_empty(),"Foreign ownership cells must reject before restore")
		invalid=state.duplicate(true)
		invalid["slots"][int(state["active"][0])]["progress"]=NAN
		check(Registry.restore(invalid).is_empty(),"Non-finite lifetime progress must reject")
	print("Original plot registry: %d region cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
