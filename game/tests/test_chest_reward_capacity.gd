extends "res://tests/test_chest_lifetime.gd"

const Availability = preload("res://simulation/source_availability.gd")
var capacity: Dictionary
var capacity_rules: Dictionary
var capacity_events: Array=[]


func service(name: String,handle: int,args: Array) -> Variant:
	if name=="reward_available":
		events.append([name,handle,args.duplicate(true)])
		return Availability.available(capacity,args[0],capacity_rules,capacity_events)!=0
	return super.service(name,handle,args)


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_chest_reward_capacity.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Composed reward capacity requires original provenance")
	if content.is_empty(): quit(1); return
	capacity_rules=content["availability_rules"]
	var rules: Dictionary=content["lifetime_rules"]
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for raw: Dictionary in fixture["cases"]:
		example=raw
		transitions+=example["steps"].size()
		for with_save: bool in [false,true]:
			chests=Lifetime.restore(stored_numbers(example["chests"]))["chests"]
			capacity=Availability.restore(example["availability"])
			unlocks=example.get("unlocks",[]).duplicate(true)
			opened_count=0
			grants=[]
			for index in range(example["steps"].size()):
				step=example["steps"][index]
				events=[]
				capacity_events=[]
				status_calls=0
				var output: Variant=perform(rules)
				var expected: Dictionary=stored_numbers(example["states"][index])
				var sorted_unlocks: Array=unlocks.duplicate()
				sorted_unlocks.sort()
				var actual := {"output":output,"chests":chests,"events":events,"unlocks":sorted_unlocks,"opened_count":opened_count,"availability":capacity,"availability_events":capacity_events}
				check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(expected),"Original composed %s transition %d must match: %s / %s"%[example["name"],index,actual,expected])
				if with_save:
					var encoded: Variant=JSON.parse_string(JSON.stringify(codec.encode_numbers(actual)))
					var saved: Dictionary=codec.decode_numbers(encoded)
					chests=Lifetime.restore(saved["chests"])["chests"]
					capacity=Availability.restore(saved["availability"])
					unlocks=saved["unlocks"]
					opened_count=int(saved["opened_count"])
	print("Original chest reward capacity: %d cases, %d transitions, save continuation, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
