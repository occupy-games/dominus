extends SceneTree

const Areas = preload("res://simulation/source_influence_areas.gd")
const Influence = preload("res://simulation/source_influence.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func snapshot(state: Dictionary,bounds: Array,events: Array) -> Dictionary:
	var fields := {}
	for field: int in [4,6]:
		var bytes := PackedByteArray()
		for z in range(int(bounds[1]),int(bounds[3])):
			for x in range(int(bounds[0]),int(bounds[2])): bytes.append(Influence.byte_at(state["raster"],field,x,z))
		fields[str(field)]=bytes.hex_encode()
	var dirty: Array=[]
	for index in range(1024):
		if state["dirty"].has(str(index)): dirty.append(index)
	return {"radii":state["radii"].duplicate(),"powers_only":state["powers_only"].duplicate(),"changed":state["changed"],"dirty":dirty,"events":events,"fields":fields}


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_influence_areas.json"))
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/influence-rules.json"))
	var original_rules := preload("res://infrastructure/source_influence.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	check(Areas.valid_rules(original_rules),"The source area controller must load original desktop rules")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var samples := 0
	for example: Dictionary in fixture["cases"]:
		var state := Areas.initial(example["areas"])
		var continued := {}
		for index in range(example["steps"].size()):
			var step: Dictionary=example["steps"][index]
			var rules := original_rules.duplicate(true)
			rules["expand"]=step.get("expand",original_rules["expand"])
			var unlocked := func(key: String) -> bool: return step.get("unlocks",[]).has(key)
			state["dirty"].clear()
			var events := Areas.advance(state,example["areas"],rules,unlocked,float(step.get("delta",0.1)),step.get("activated",[]),bool(step.get("force",false)),bool(step.get("rebuild",false)))
			var actual := snapshot(state,example["bounds"],events)
			var expected: Dictionary=example["states"][index]
			expected["radii"]=expected["radii"].map(func(value: Variant) -> float: return Terrain.f32(float(value)))
			expected["dirty"]=expected["dirty"].map(func(value: Variant) -> int: return int(value))
			for event: Dictionary in expected["events"]: event["argument"]=int(event["argument"])
			check(actual==expected,"Original %s area radii, flags, dirty regions, events and raster must match at step %d"%[example["name"],index])
			check(Areas.valid(state,example["areas"],rules),"Native area state must retain valid persistent data")
			if not continued.is_empty():
				continued["dirty"].clear()
				var continued_events := Areas.advance(continued,example["areas"],rules,unlocked,float(step.get("delta",0.1)),step.get("activated",[]),bool(step.get("force",false)),bool(step.get("rebuild",false)))
				check(continued==state and continued_events==events,"Restored %s area controller must continue identically"%example["name"])
			else:
				var saved: Variant=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(Areas.export_state(state)))))
				continued=Areas.restore(saved,example["areas"],rules)
				check(not continued.is_empty(),"In-progress area expansion must restore through the save codec")
			samples+=(int(example["bounds"][2])-int(example["bounds"][0]))*(int(example["bounds"][3])-int(example["bounds"][1]))*2
		var invalid := Areas.export_state(state)
		invalid["radii"][0]=float(example["areas"][0]["radius"])+1.0
		check(Areas.restore(invalid,example["areas"],original_rules).is_empty(),"Overgrown source-area radii must reject")
		invalid=Areas.export_state(state)
		invalid["dirty"]["1024"]=true
		check(Areas.restore(invalid,example["areas"],original_rules).is_empty(),"Outside dirty-area indices must reject")
	var broken := original_rules.duplicate(true)
	broken["expand_rate"]=NAN
	check(not Areas.valid_rules(broken) and not Influence.valid_rules(broken),"Corrupted area timing must reject at the campaign rule boundary")
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := preload("res://simulation/world.gd").new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	for tick in range(5): world.step()
	check(float(world._state["source_influence"]["radii"][0])>0 and float(world._state["source_influence"]["radii"][0])<50,"The real private campaign must advance desktop influence at fixed ticks")
	var detached := world.snapshot(false)
	detached["source_influence"]["radii"][0]=50.0
	check(float(world._state["source_influence"]["radii"][0])<50,"Presentation snapshots must not advance authoritative area radii")
	var store := preload("res://infrastructure/world_store.gd").new()
	store.database_path="res://../build/test-influence-expansion.sqlite"
	check(store.save_world(world.export_state()).get("ok",false),"In-progress campaign influence must save through SQLite")
	var loaded: Dictionary=store.load_world()
	var resumed := preload("res://simulation/world.gd").new()
	check(loaded.get("ok",false) and resumed.restore(loaded.get("data",{}),RandomNumberGenerator.new()),"Campaign influence radii, cache and byte fields must reload")
	var output: Array=[]
	var repeated: Array=[]
	for tick in range(25):
		output.append_array(world.step())
		repeated.append_array(resumed.step())
	check(world.export_state()==resumed.export_state() and output==repeated,"SQLite continuation during expansion must reproduce exact state and callback order")
	check(output.filter(func(event: Dictionary) -> bool: return event.get("type")=="source_callback" and event.get("name")=="influencechanged").size()==1,"The original influence completion callback must emit once after the areas settle")
	check(world.source_plot_eligible(161,119) and not world.source_plot_eligible(308,327),"Campaign plot queries must use distinct construction influence, preserving power-only Astari land")
	var invalid := world.export_state()
	invalid["state"]["source_influence"]["radii"][0]=51.0
	check(not resumed.restore(invalid,RandomNumberGenerator.new()),"Malformed campaign influence must reject before replacing live state")
	invalid=world.export_state()
	invalid["state"]["progression"]["rules"]["influence_areas"][0]["radius"]=NAN
	check(not resumed.restore(invalid,RandomNumberGenerator.new()),"Malformed saved area definitions must reject before native field queries")
	invalid=world.export_state()
	invalid["state"]["progression"]["rules"]["influence_areas"]="invalid"
	check(not resumed.restore(invalid,RandomNumberGenerator.new()),"An invalid saved area container must return a clean restore rejection")
	var tick_before: int=world._state["tick"]
	check(preload("res://simulation/influence.gd").contains(world._state,179,130),"The source default area must initially cover the reload probe")
	check(world.reconfigure([{"category":"influence","index":1,"field":"radius","value":10}]).get("ok",false) and world._state["tick"]==tick_before,"Live source area edits must apply without advancing fixed time")
	check(resumed.restore(world.export_state(),RandomNumberGenerator.new()),"A reduced source radius must remain immediately saveable after live reload")
	for tick in range(21): world.step(); resumed.step()
	check(not preload("res://simulation/influence.gd").contains(world._state,179,130),"Source field rebuild must remove stale permissions after an area shrinks")
	check(world.export_state()==resumed.export_state(),"Reloaded area configuration must preserve deterministic continuation")
	print("Original influence areas: %d cases, %d bytes, %d failures"%[fixture["cases"].size(),samples,failures])
	quit(1 if failures else 0)
