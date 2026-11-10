extends SceneTree

const Influence = preload("res://simulation/source_influence.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func raster(state: Dictionary,field: int,bounds: Array) -> String:
	var bytes := PackedByteArray()
	for z in range(int(bounds[1]),int(bounds[3])):
		for x in range(int(bounds[0]),int(bounds[2])): bytes.append(Influence.byte_at(state,field,x,z))
	return bytes.hex_encode()


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_influence.json"))
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/influence-rules.json"))
	var rules := preload("res://infrastructure/source_influence.gd").load_rules(fixture["executable_sha256"],metadata["source_sha256"])
	check(Influence.valid_rules(rules),"Source influence constants must load with matching provenance")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var samples := 0
	for example: Dictionary in fixture["cases"]:
		var state := Influence.initial()
		for index in range(example["commands"].size()):
			var command: Dictionary=example["commands"][index]
			var expected: Dictionary=example["states"][index]
			check(Influence.circle(state,command,rules)==expected["changed"],"Original %s circle identity/change result must match"%example["name"])
			for field: int in [4,6]:
				check(raster(state,field,example["bounds"])==expected["fields"][str(field)],"Every native %s field %d byte must match at step %d"%[example["name"],field,index])
				samples+=(int(example["bounds"][2])-int(example["bounds"][0]))*(int(example["bounds"][3])-int(example["bounds"][1]))
			check(Influence.valid(state),"Registered source influence must retain valid plain state")
			var saved: Variant=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(Influence.export_state(state)))))
			var restored := Influence.restore(saved)
			check(restored==state,"Influence byte fields and uint64 string identities must survive save transport")
			if not restored.is_empty(): check(not Influence.circle(restored,command,rules) if not command.get("force",false) else Influence.circle(restored,command,rules),"Restored source circle cache must preserve the native no-change guard")
		var detached := state.duplicate(true)
		var before := raster(state,4,example["bounds"])
		Influence.write_byte(detached,4,int(example["bounds"][0]),int(example["bounds"][1]),255)
		check(raster(state,4,example["bounds"])==before,"Detached influence bytes must not alter their simulation owner")
		var invalid := state.duplicate(true)
		invalid["fields"]["4"]["1024"]=PackedByteArray()
		check(Influence.restore(invalid).is_empty(),"Out-of-map influence tiles must reject")
		invalid=state.duplicate(true)
		invalid["circles"][0]["radius"]=NAN
		check(Influence.restore(invalid).is_empty(),"Non-finite circle state must reject")
	for example: Dictionary in fixture["gates"]:
		var state := Influence.initial()
		Influence.write_byte(state,4,160,120,int(example["fields"][0]))
		Influence.write_byte(state,6,160,120,int(example["fields"][1]))
		check(Influence.allows(state,160,120,false,rules)==example["build"] and Influence.allows(state,160,120,true,rules)==example["power"],"Original construction versus power gate must match for %s"%[example["fields"]])
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := preload("res://simulation/world.gd").new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	check(not preload("res://simulation/influence.gd").contains(world._state,155,85),"Initial source influence must await its first fixed update")
	for tick in range(21): world.step()
	var initial_capture: Dictionary={}
	for example: Dictionary in fixture["cases"]:
		if example["name"]=="source_initial_areas": initial_capture=example
	var bounds: Array=initial_capture["bounds"]
	var original: Dictionary=initial_capture["states"][-1]["fields"]
	var normal: PackedByteArray=original["4"].hex_decode()
	var powers: PackedByteArray=original["6"].hex_decode()
	var mismatches := 0
	for z in range(int(bounds[1]),int(bounds[3])):
		for x in range(int(bounds[0]),int(bounds[2])):
			var index := (z-int(bounds[1]))*(int(bounds[2])-int(bounds[0]))+x-int(bounds[0])
			var allowed: bool=float(maxi(normal[index],powers[index]))*float(rules["decode_scale"])>=float(rules["threshold"])
			if preload("res://simulation/influence.gd").contains(world._state,float(x),float(z))!=allowed: mismatches+=1
	check(mismatches==0,"Private campaign action gates must match every original initial-area raster sample")
	check(preload("res://simulation/influence.gd").contains(world._state,308,327),"Source power-only Astari influence must permit god-power targeting")
	check(not preload("res://simulation/influence.gd").contains(world._state,155,277),"Locked source expansion areas must remain unavailable")
	world._state["progression"]["script_unlocks"]={"Expansion_3a":true}
	for tick in range(21): world.step()
	check(preload("res://simulation/influence.gd").contains(world._state,155,277),"Source script unlocks must expand the private campaign's actionable area")
	var restored := preload("res://simulation/world.gd").new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Injected source influence rules must survive campaign persistence")
	check(restored._state["opening"]["definition"]["influence_rules"].is_read_only(),"Presentation/query snapshots must retain immutable source constants")
	var saved := world.export_state()
	saved["state"]["opening"]["definition"]["influence_rules"]["threshold"]=NAN
	check(not restored.restore(saved,RandomNumberGenerator.new()),"Corrupted saved influence constants must reject")
	print("Original influence raster: %d circles, %d gates, %d bytes, %d failures"%[fixture["cases"].size(),fixture["gates"].size(),samples,failures])
	quit(1 if failures else 0)
