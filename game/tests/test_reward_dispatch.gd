extends SceneTree

const Dispatch = preload("res://simulation/source_reward_dispatch.gd")
const Repair = preload("res://simulation/source_temple_repair.gd")
const Numbers = preload("res://simulation/progression.gd")
var example: Dictionary
var state: Dictionary
var counts: Dictionary
var events: Array=[]
var random_calls := 0
var failures := 0
var temple: Dictionary={}
var dispatch_rules: Dictionary


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func word() -> int:
	var words: Array=example.get("words",[0])
	var result := int(words[random_calls%words.size()])
	random_calls+=1
	return result


func service(name: String,args: Array) -> Variant:
	var event := [name,args.duplicate(true),state["pack_count"],state["pack_index"]]
	if not temple.is_empty(): event.append([temple["phase"],temple["reward_pending"],temple["reward_ready"]])
	events.append(event)
	match name:
		"card_acquired": return counts.get(str(args[0]),0)
		"grant":
			if example.get("credit_updates_count",false): counts[str(args[0])]=(int(counts.get(str(args[0]),0))+1)&4294967295
		"select_sticker": return example.get("selected_sticker",0)
		"select_event_reward": return example.get("selected_event",0)
		"is_discovery": return example.get("is_discovery",true)
		"notification_context":
			if example.has("context_source_id"): temple["source_id"]=int(example["context_source_id"])
		"unlock":
			if example.has("unlock_reward"): temple["reward"]=int(example["unlock_reward"])
			if example.has("unlock_source_id"): temple["source_id"]=int(example["unlock_source_id"])
		"grant_temple": return Dispatch.from_site(state,example["records"],dispatch_rules,int(args[0]),int(args[1]),int(args[2]),true,word,service)
	return null


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_reward_dispatch.json")))
	var rules := preload("res://infrastructure/reward_dispatch.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	check(not rules.is_empty(),"Reward dispatch requires original executable and balance provenance")
	if rules.is_empty(): quit(1); return
	dispatch_rules=rules
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=case
		var configured := rules.duplicate(true)
		configured["story_chance"]=example.get("story_chance",rules["story_chance"])
		for with_save: bool in [false,true]:
			state=Dispatch.restore(example.get("state",{"stories_acquired":[],"pack_count":0,"pack_index":0}))
			counts=example.get("counts",{}).duplicate(true)
			if with_save: state=Dispatch.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state)))))
			events=[]
			random_calls=0
			var action: String=example.get("action","dispatch")
			var ok := false
			if action=="dispatch":
				ok=Dispatch.dispatch(state,example["records"],configured,int(example["reward"]),int(example.get("source_id",1012)),int(example.get("flags",0)),int(example.get("reason",8)),int(example.get("override",0)),word,service)
			else: ok=Dispatch.from_site(state,example["records"],configured,int(example["reward"]),int(example.get("source_id",1012)),int(example.get("flags",0)),action=="temple",word,service)
			check(ok,"Original reward inputs must be accepted "+example["name"])
			state["stories_acquired"].sort()
			var actual := {"state":state,"events":events,"random_calls":random_calls,"counts":counts}
			check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(example["expected"]),"Original %s reward dispatch: %s / %s"%[example["name"],actual,example["expected"]])
	var repair_rules := preload("res://infrastructure/temple_repair.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	for case: Dictionary in fixture["pending_cases"]:
		example=case
		for with_save: bool in [false,true]:
			temple=Repair.restore(example["temple"])
			check(not temple.is_empty(),"Original deferred temple state must restore "+example["name"])
			state={"stories_acquired":[],"pack_count":0,"pack_index":0}
			counts={}
			random_calls=0
			for expected: Dictionary in example["expected"]:
				if with_save:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"state":state,"temple":temple,"counts":counts}))))
					state=Dispatch.restore(saved["state"])
					temple=Repair.restore(saved["temple"])
					counts=saved["counts"]
				events=[]
				var granted := Repair.dispatch_pending(temple,repair_rules,service)
				check(granted==events.any(func(event: Array) -> bool: return event[0]=="grant_temple"),"The pending result must reflect the actual original grant branch")
				state["stories_acquired"].sort()
				var actual := {"state":state,"temple":temple,"events":events,"random_calls":random_calls,"counts":counts}
				check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(expected),"Original deferred %s dispatch: %s / %s"%[example["name"],actual,expected])
	temple={}
	for sequence: Dictionary in fixture["story_sequences"]:
		example={"records":sequence["records"],"words":sequence["words"]}
		for with_save: bool in [false,true]:
			state=Dispatch.restore(sequence["initial"])
			counts={}
			random_calls=0
			for expected: Dictionary in sequence["steps"]:
				if with_save:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"state":state,"random_calls":random_calls}))))
					state=Dispatch.restore(saved["state"])
					random_calls=int(saved["random_calls"])
				events=[]
				check(Dispatch.dispatch(state,sequence["records"],rules,int(sequence["kind"]),1012,0,8,0,word,service),"Original Homeworld6 story rewards must continue")
				state["stories_acquired"].sort()
				var actual := {"state":state,"events":events,"random_calls":random_calls,"counts":counts}
				check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(expected),"Original Homeworld6 %s story sequence must match after each grant and save"%sequence["name"])
	state={"stories_acquired":[],"pack_count":0,"pack_index":0}
	var cyclic := {"stories":[],"packs":[{"id":1,"slots":[{"count":1,"reward":1},{"count":0,"reward":0},{"count":0,"reward":0},{"count":0,"reward":0},{"count":0,"reward":0}]}],"cards":[],"stickers":[]}
	events=[]
	random_calls=0
	check(not Dispatch.dispatch(state,cyclic,rules,1,0,0,0,0,word,service) and events.is_empty() and random_calls==0,"A cyclic supplied pack must reject before RNG or grants")
	check(Dispatch.restore({"stories_acquired":[1,1],"pack_count":0,"pack_index":0}).is_empty(),"Duplicate saved story identities must reject")
	print("Original reward dispatch: %d cases, %d deferred temple cases, save restoration, %d failures"%[fixture["cases"].size(),fixture["pending_cases"].size(),failures])
	quit(1 if failures else 0)
