extends SceneTree

const Repair = preload("res://simulation/source_temple_repair.gd")
const Numbers = preload("res://simulation/progression.gd")
var example: Dictionary
var current: Dictionary
var events: Array=[]
var failures := 0


func stored_numbers(value: Variant) -> Variant:
	if value is float: return preload("res://simulation/source_terrain.gd").f32(value)
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(stored_numbers(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key]=stored_numbers(value[key])
		return result
	return value


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),int(current["phase"])])
	match name:
		"currency": return int(str(example.get("currency",{}).get(args[0],10)))
		"spending_enabled": return example.get("spending_enabled",true)
		"is_dock","is_pit","is_settlement","is_ark": return example.get(name,false)
		"hook":
			if args[0]=="templebuilding" and example.has("hook_food_cost"): current["food_cost"]=int(example["hook_food_cost"])
		"ark_followers": return example.get("followers",[]).duplicate(true)
		"notification_context": return 12345
		"completion_visual":
			if example.get("clear_reward_during_visual",false): current["reward"]=0
	return null


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_repair.json")))
	var rules := preload("res://infrastructure/temple_repair.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	check(not rules.is_empty(),"Temple repair requires original executable and balance provenance")
	if rules.is_empty(): quit(1); return
	var content := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(content["story"]["temple_repair_rules"]==rules,"Original work rules must reach the private source campaign")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for case: Dictionary in fixture["cases"]:
		example=stored_numbers(case)
		var configured: Dictionary=rules.duplicate(true)
		configured["exponent"]=example.get("exponent",rules["exponent"])
		for with_save: bool in [false,true]:
			current=Repair.restore(example["state"])
			check(not current.is_empty(),"Original controlled temple state must restore "+example["name"])
			if with_save:
				var loaded: Variant=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(current))))
				current=Repair.restore(loaded)
			events=[]
			var value := false
			match example["action"]:
				"can_pay": value=Repair.can_pay(current,configured,service)
				"currency_allowed": value=Repair.currency_allowed(current,int(example["kind"]),configured,service)
				"begin": value=Repair.begin(current,configured,service)
				"work": value=Repair.advance_work(current,configured,example.get("totals",{"workers":1,"contributors":1,"skill_sum":1.}),float(example.get("delta",.1)),int(example.get("mode",0)),int(example.get("player",0)),service)
			var expected: Dictionary=example["expected"]
			check(value==expected["value"],"Original %s outcome must match"%example["name"])
			check(Numbers.canonical_numbers(current)==Numbers.canonical_numbers(expected["state"]),"Original %s state: %s / %s"%[example["name"],current,expected["state"]])
			check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]),"Original %s service order: %s / %s"%[example["name"],events,expected["events"]])
	var invalid: Dictionary=fixture["cases"][0]["state"].duplicate(true)
	invalid["progress"]=NAN
	check(Repair.restore(invalid).is_empty(),"Nonfinite saved work must reject")
	events=[]
	check(not Repair.begin({},rules,service) and events.is_empty(),"Invalid work must reject before hooks or payment")
	print("Original temple repair: %d cases, save restoration, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
