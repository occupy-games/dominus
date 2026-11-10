extends "res://tests/test_temple_terrain.gd"

const Footprint = preload("res://simulation/source_temple_footprint.gd")
var footprint_rules: Dictionary={}
var site: Dictionary={}
var ground_data: Dictionary={}
var queries: Array=[]


func ground(x: int,z: int) -> float:
	var value := float(ground_data.get("values",{}).get("%d,%d"%[x,z],ground_data.get("default",0)))
	queries.append([x,z,value])
	return value


func service(name: String,args: Array) -> Variant:
	return super.service(name,args)


func _initialize() -> void:
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_footprint.json"))))
	var rules := preload("res://infrastructure/temple_terrain.gd").load_rules(fixture["executable_sha256"])
	footprint_rules=preload("res://infrastructure/temple_terrain.gd").footprint_rules(fixture["executable_sha256"])
	check(not rules.is_empty() and not footprint_rules.is_empty(),"Composed temple terrain rules must have matching provenance")
	check(preload("res://infrastructure/temple_terrain.gd").footprint_rules("wrong").is_empty(),"Footprint constants must reject mismatched provenance")
	if rules.is_empty() or footprint_rules.is_empty(): quit(1); return
	for case: Dictionary in fixture["cases"]:
		site=case["site"].duplicate(true)
		ground_data=case["ground"]
		queries=[]
		var count := Footprint.count(site,footprint_rules,ground)
		check(count==int(case["expected"]["count"]),"Native footprint count "+str(case["name"]))
		check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(case["expected"]["queries"]),"Native footprint bounds and row-major samples "+str(case["name"]))
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["composed"]:
		example=case
		site=case["site"].duplicate(true)
		ground_data=case["ground"]
		for saved: bool in [false,true]:
			current=Temple.restore(case["state"])
			if saved: current=Temple.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current)))))
			queries=[]; events=[]
			check(Temple.advance_with_footprint(current,site,rules,footprint_rules,float(case.get("delta",.1)),ground,service),"Original composed footprint transition must advance")
			compare(case["expected"],str(case["name"]))
			check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(case["expected"]["queries"]),"Composed native footprint sample order")
	var transitions := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()+1):
			current=Temple.restore(sequence["initial"])
			site=sequence["site"].duplicate(true)
			example={"is_settlement":true}
			for index in range(sequence["steps"].size()):
				if index==save_at:
					var restored: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"temple":current,"site":site}))))
					current=Temple.restore(restored["temple"])
					site=restored["site"]
				ground_data=sequence["steps"][index]["ground"]
				queries=[]; events=[]
				check(Temple.advance_with_footprint(current,site,rules,footprint_rules,.25,ground,service),"Saved footprint transition must advance")
				compare(sequence["steps"][index]["expected"],"Saved composed terrain")
				check(Numbers.canonical_numbers(queries)==Numbers.canonical_numbers(sequence["steps"][index]["expected"]["queries"]),"Saved composed native footprint samples")
				if save_at==0: transitions+=1
	var before := site.duplicate(true)
	queries=[]
	for changes: Dictionary in [{"x":NAN},{"z":1000001},{"height":INF},{"footprint_width":1025},{"footprint_width":-1}]:
		var invalid := before.duplicate(true)
		invalid.merge(changes,true)
		check(Footprint.count(invalid,footprint_rules,ground)==-1 and queries.is_empty(),"Invalid footprint must reject before querying terrain")
	var unchanged := current.duplicate(true)
	site["footprint_width"]=int(current["footprint_width"])+1
	events=[]
	check(not Temple.advance_with_footprint(current,site,rules,footprint_rules,.25,ground,service) and current==unchanged and events.is_empty() and queries.is_empty(),"Mismatched composed footprints cannot change phases or call effects")
	print("Original temple footprint: %d scans, %d composed cases, %d sequence steps, save continuation, %d failures"%[fixture["cases"].size(),fixture["composed"].size(),transitions,failures])
	quit(1 if failures else 0)
