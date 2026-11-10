extends SceneTree

const Temple = preload("res://simulation/source_temple_terrain.gd")
const Numbers = preload("res://simulation/progression.gd")
var current: Dictionary={}
var example: Dictionary={}
var events: Array=[]
var failures := 0


func source_floats(value: Variant) -> Variant:
	if value is float: return preload("res://simulation/source_terrain.gd").f32(value)
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(source_floats(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key]=source_floats(value[key])
		return result
	return value


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),int(current["phase"]),float(current["progress"]),float(current["timer"])])
	if name=="is_settlement": return bool(example.get("is_settlement",false))
	return null


func compare(expected: Dictionary,label: String) -> void:
	check(Numbers.canonical_numbers(current)==Numbers.canonical_numbers(expected["state"]),label+" state: "+str(current)+" / "+str(expected["state"]))
	check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]),label+" service ordering: "+str(events)+" / "+str(expected["events"]))


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_terrain.json"))))
	var rules := preload("res://infrastructure/temple_terrain.gd").load_rules(fixture["executable_sha256"])
	check(not rules.is_empty(),"Original terrain rules must resolve with matching executable provenance")
	check(preload("res://infrastructure/temple_terrain.gd").load_rules("wrong").is_empty(),"Mismatched temple terrain provenance must reject")
	if rules.is_empty(): quit(1); return
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("temple_terrain_rules")==rules,"Source campaign definitions must receive the verified terrain rules separately from presentation")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=Temple.restore(case["state"])
			if saved: current=Temple.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			check(not current.is_empty(),"Original terrain state must restore "+str(case["name"]))
			events=[]
			check(Temple.advance(current,rules,float(case.get("delta",.1)),service),"Valid original terrain transition must run")
			compare(case["expected"],str(case["name"]))
	var transitions := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Temple.restore(sequence["initial"])
			example={"is_settlement":true}
			for index in range(sequence["steps"].size()):
				if index==save_at: current=Temple.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
				current["obstruction"]=int(sequence["steps"][index]["obstruction"])
				events=[]
				check(Temple.advance(current,rules,.25,service),"Restored terrain sequence must advance")
				compare(sequence["steps"][index]["expected"],"Saved terrain sequence")
				if save_at==0: transitions+=1
	current=Temple.restore(fixture["cases"][0]["state"])
	var before := current.duplicate(true)
	events=[]
	check(not Temple.advance(current,rules,-1,service) and current==before and events.is_empty(),"Invalid delta cannot invoke footprint, effect or audio services")
	for changes: Dictionary in [{"timer":NAN},{"required":0},{"footprint_width":0},{"phase":9},{"audio_handle":4294967295}]:
		var invalid := before.duplicate(true)
		invalid.merge(changes,true)
		check(Temple.restore(invalid).is_empty(),"Invalid saved temple terrain state must reject")
	print("Original temple terrain: %d cases, %d sequence steps, save continuation, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
