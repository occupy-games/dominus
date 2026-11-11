extends SceneTree

const Fields = preload("res://simulation/source_map_fields.gd")
const Raster = preload("res://simulation/source_influence.gd")
const TimerRule = preload("res://simulation/source_land_effect_timer.gd")
const Progression = preload("res://simulation/progression.gd")

var codec := preload("res://infrastructure/world_store.gd").new()
var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)


func observe(raster: Dictionary, probes: Array, changed: Array) -> Dictionary:
	var reads: Array=[]
	for probe: Array in probes:
		reads.append(Fields.read(raster,probe[0],probe[1],probe[2]))
	var layers := {}
	for kind: String in raster["fields"]:
		if not raster["fields"][kind].is_empty():
			var tiles: Array=[]
			for tile: String in raster["fields"][kind]:
				tiles.append(int(tile))
			tiles.sort()
			layers[kind]=tiles
	return {"anchor":raster["land_effect_clock"],"changed":changed,"reads":reads,"layers":layers,
		"serial":raster["field_notifications"]["serial"],"cells":raster["field_notifications"]["cells"]}


func _initialize() -> void:
	var fixture: Dictionary=Progression.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_land_effect_timer.json")))
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/beautify.json"))
	var count := 0
	for test: Dictionary in fixture["cases"]:
		var raster := Raster.initial()
		raster["field_notifications"]={"serial":test["serial"],"cells":[]}
		if test.has("anchor"):
			raster["land_effect_clock"]=test["anchor"]
		for item: Array in test["bytes"]:
			Fields.write_byte(raster,item[0],item[1],item[2],item[3])
		for step: Dictionary in test["steps"]:
			var label := "%s at %s ms"%[test["name"],step["now"]]
			var changed := TimerRule.advance(raster,step["now"],test["period"],step.get("override",-1.0),source["rules"]["timer"])
			var actual: Dictionary=Progression.canonical_numbers(observe(raster,test["probes"],changed))
			var expected: Dictionary=step["expected"]
			for key: String in expected:
				check(actual[key]==expected[key],label+" must reproduce original "+key)
			var saved := JSON.stringify(codec.encode_numbers(Raster.export_state(raster)))
			var restored := Raster.restore(Progression.canonical_numbers(codec.decode_numbers(JSON.parse_string(saved))))
			check(not restored.is_empty() and Raster.export_state(restored)==Raster.export_state(raster),label+" must round trip the exact timer state")
			if not restored.is_empty():
				raster=restored
			count+=1
	print("Original land effect timer: %d native transitions, save continuation, %d failures"%[count,failures])
	quit(1 if failures else 0)
