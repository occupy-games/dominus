extends SceneTree

const Availability = preload("res://simulation/source_availability.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_availability.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Availability rules require matching original provenance")
	if content.is_empty(): quit(1); return
	var rules: Dictionary=content["availability_rules"]
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["availability_rules"]==rules,"Campaign must receive original capacity defaults")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var queries := 0
	for example: Dictionary in fixture["cases"]:
		queries+=example["steps"].size()
		for with_save: bool in [false,true]:
			var state := Availability.restore(example["state"])
			check(not state.is_empty(),"Original controlled state must be valid: "+example["name"])
			for index in range(example["steps"].size()):
				var step: Dictionary=example["steps"][index]
				var events: Array=[]
				var value := 0
				match step.get("action","available"):
					"owned": value=Availability.owned(state,step["key"])
					"acquired": value=Availability.acquired(state,step["key"])
					_: value=Availability.available(state,step["key"],rules,events)
				var expected: Dictionary=example["states"][index]
				check(value==int(expected["value"]),"Original %s query %d value: %s / %s"%[example["name"],index,value,expected["value"]])
				check(Numbers.canonical_numbers(state)==Numbers.canonical_numbers(expected["state"]),"Original %s query %d table mutations"%[example["name"],index])
				check(events==expected["events"],"Original %s query %d diagnostic order"%[example["name"],index])
				if with_save:
					var encoded: Variant=JSON.parse_string(JSON.stringify(codec.encode_numbers(state)))
					state=Availability.restore(codec.decode_numbers(encoded))
					check(not state.is_empty(),"Every query must survive save restoration")
	var original := Availability.initial()
	var detached := Availability.restore(original)
	var events: Array=[]
	Availability.available(detached,"Reward_ChestSticker",rules,events)
	check(original==Availability.initial(),"Queries over detached state cannot mutate authoritative state")
	for invalid: Variant in [null,{},-1,4294967296,"",true,1.5]:
		if invalid is Dictionary:
			check(Availability.restore(invalid).is_empty(),"Incomplete state must be rejected")
		else: check(not Availability.valid_key(invalid),"Invalid resource identity must be rejected")
	for table: String in Availability.COUNTERS:
		var invalid := Availability.initial()
		invalid[table]["broken"]=-1
		check(Availability.restore(invalid).is_empty(),"Invalid unsigned counter must be rejected")
	print("Original reward availability: %d cases, %d queries, save continuation, %d failures"%[fixture["cases"].size(),queries,failures])
	quit(1 if failures else 0)
