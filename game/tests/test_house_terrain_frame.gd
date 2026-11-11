extends "res://tests/test_building_foundation.gd"

const Frame = preload("res://simulation/source_house_terrain_frame.gd")
const Content = preload("res://infrastructure/house_terrain_frame.gd")
const EVENT_FIELDS = [
	"state","progress","damage_timer","variant","uneven_count","restore_requested",
	"appearance_dirty","completed_dirty","post_complete_timer","created_clock",
]

var foundation_rules: Dictionary
var codec := preload("res://infrastructure/world_store.gd").new()


func service(name: String,args: Array) -> Variant:
	var fields: Array=[]
	for key: String in EVENT_FIELDS:
		fields.append(current[key])
	events.append([name,args.duplicate(true),fields])
	match name:
		"terrain_overlay":
			return bool(example.get("overlay_available",false))
		"construction_target":
			for key: String in example.get("target_changes",{}):
				current[key]=Frame.Terrain.f32(float(example["target_changes"][key]))
			return example.get("target",5.0)
		"work_exponent":
			return Frame.Terrain.f32(float(example.get("exponent",0.7)))
		"clock":
			return example.get("clock",0x123456789ab)
	return null


func advance_case(rules: Dictionary) -> bool:
	events=[]
	var delta := float(example.get("delta",0.25))
	if example.get("frame",true):
		return Frame.advance(current,rules,foundation_rules,delta,service,overlay,ground)
	return Frame.advance_state(current,rules,delta,service)


func compare_case(expected: Dictionary,_rules: Dictionary,label: String) -> void:
	compare(expected,label)
	if not expected["bounds"].is_empty():
		var region := Foundation.bounds(current,foundation_rules)
		check([region.position.x,region.position.y,region.size.x,region.size.y]==expected["bounds"],label+" native foundation bounds")


func restore_after_save(state: Dictionary) -> Dictionary:
	var serialized := JSON.stringify(codec.encode_numbers(state))
	return Frame.restore(codec.decode_numbers(JSON.parse_string(serialized)))


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_house_terrain_frame.json")
	var fixture: Dictionary=source_floats(Numbers.canonical_numbers(JSON.parse_string(raw)))
	var rules := Content.rules(fixture["executable_sha256"])
	foundation_rules=preload("res://infrastructure/building_foundation.gd").rules(fixture["executable_sha256"])
	check(not rules.is_empty() and not foundation_rules.is_empty(),"House frame and foundation rules must match executable provenance")
	check(Content.rules("wrong").is_empty(),"House frame rules must reject mismatched executable provenance")
	if failures:
		quit(1)
		return
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("house_terrain_rules")==rules,"Source campaign must receive the original house frame rules")
	for case: Dictionary in fixture["cases"]:
		example=case
		for saved: bool in [false,true]:
			current=restore_after_save(case["state"]) if saved else Frame.restore(case["state"])
			var label := str(case["name"])
			check(advance_case(rules),"Valid original house frame "+label)
			compare_case(case["expected"],rules,label)
	var steps := 0
	for sequence: Dictionary in fixture["sequences"]:
		for save_at in range(sequence["steps"].size()):
			current=Frame.restore(sequence["initial"])
			for index in range(sequence["steps"].size()):
				if index==save_at:
					current=restore_after_save(current)
				example=sequence["steps"][index]
				current.merge(example["inputs"],true)
				var label := "House frame step %d, save at %d"%[index,save_at]
				check(advance_case(rules),label+" must advance")
				compare_case(example["expected"],rules,label)
				if save_at==0:
					steps+=1
	var baseline := Frame.restore(fixture["cases"][0]["state"])
	for changes: Dictionary in [{"nav_size":0},{"size":3},{"handle":65535},{"damage_timer":NAN}]:
		current=baseline.duplicate(true)
		current.merge(changes,true)
		var before := current.duplicate(true)
		example={}
		check(Frame.restore(current).is_empty(),"Invalid house frame state must reject restoration")
		check(not advance_case(rules) and events.is_empty(),"Invalid house frame state must reject before services")
		if not changes.has("damage_timer"):
			check(current==before,"Invalid house frame state must reject before mutation")
	current=baseline.duplicate(true)
	example={"delta":-1.0}
	check(not advance_case(rules) and current==baseline and events.is_empty(),"Negative delta must reject before mutation")
	current=baseline.duplicate(true)
	example={"target":1.0e-100,"frame":false}
	check(not advance_case(rules) and current==baseline,"Construction target must stay positive after float32 storage")
	print("Original house terrain/work frame: %d native cases, %d sequence steps, saved continuation, %d failures"%[fixture["cases"].size(),steps,failures])
	quit(1 if failures else 0)
