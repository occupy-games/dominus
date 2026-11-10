extends SceneTree

const Selection = preload("res://simulation/source_sticker_selection.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var example: Dictionary
var events: Array=[]
var counters: Dictionary
var random_calls := 0
var remaining_calls: Dictionary={}


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func random_word() -> int:
	var words: Array=example.get("words",[0])
	var result := int(words[random_calls%words.size()])
	random_calls+=1
	return result


func service(name: String,index: int,args: Array) -> Variant:
	events.append([name,index,args.duplicate(true)])
	match name:
		"era": return example["era"]
		"card_complete": return example["cards"][index].get("complete",false)
		"card_remaining":
			var value: Variant=example["cards"][index].get("remaining",0)
			if value is Array: value=value[mini(int(remaining_calls.get(index,0)),value.size()-1)]
			remaining_calls[index]=int(remaining_calls.get(index,0))+1
			return int(value)
		"acquired": return Availability.acquired(counters,args[0])
		"owned": return Availability.owned(counters,args[0])
	return null


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_sticker_selection.json")))
	var rules := preload("res://infrastructure/sticker_selection.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	check(not rules.is_empty(),"Original sticker selection rules require matching source provenance")
	if rules.is_empty(): quit(1); return
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["sticker_selection_rules"]==rules,"Authored campaign must receive original sticker selection rules")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for raw: Dictionary in fixture["cases"]:
		example=raw
		var configured: Dictionary=rules.duplicate(true)
		configured["configuration"].merge(example.get("config",{}),true)
		for with_save: bool in [false,true]:
			counters=Availability.initial()
			for table: String in example.get("counters",{}): counters[table]=example["counters"][table].duplicate(true)
			if with_save:
				var payload := {"counters":counters,"rules":configured,"cards":example["cards"],"stickers":example["stickers"]}
				var loaded: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(payload))))
				counters=Availability.restore(loaded["counters"])
				configured=Numbers.canonical_numbers(loaded["rules"])
				example=example.duplicate(true)
				example["cards"]=Numbers.canonical_numbers(loaded["cards"])
				example["stickers"]=Numbers.canonical_numbers(loaded["stickers"])
			events=[]
			random_calls=0
			remaining_calls={}
			var before := example.duplicate(true)
			var value: Variant=Selection.select(example["kind"],example["cards"],example["stickers"],configured,int(example.get("override",0)),random_word,service)
			var expected: Dictionary=example["expected"]
			check(value==expected["value"],"Original %s sticker: %s / %s"%[example["name"],value,expected["value"]])
			check(random_calls==int(expected["random_calls"]),"Original %s random sequence length: %s / %s"%[example["name"],random_calls,expected["random_calls"]])
			check(events==expected["events"],"Original %s query order: %s / %s"%[example["name"],events,expected["events"]])
			check(counters==expected["counters"],"Original %s acquired/owned table defaults"%example["name"])
			check(example==before,"Selection must not mutate input descriptors or grant inventory")
	events=[]
	check(Selection.select("Reward_ChestSticker",[],[],{},0,random_word,service)==0 and events.is_empty(),"Invalid rules must reject before state queries")
	var invalid := rules.duplicate(true)
	invalid["configuration"]["StickerChance_TotallyRandomPcnt"]=NAN
	check(not Selection.valid_rules(invalid),"Nonfinite configuration must reject")
	print("Original sticker selection: %d cases, save restoration, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
