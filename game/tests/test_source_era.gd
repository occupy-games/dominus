extends SceneTree

const Era = preload("res://simulation/source_era.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var events: Array=[]
var unlocked: Array=[]
var global_cache: Dictionary
var step: Dictionary


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		if failures<10: push_error(message)


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true)])
	if name=="unlocked": return args[0] in unlocked
	if name=="period_changed" and step.get("invalidate_on_notification",false): global_cache["cache_valid"]=false
	return null


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_era.json")))
	var rules := preload("res://infrastructure/era_progression.gd").rules(fixture["executable_sha256"],fixture["source_sha256"])
	check(not rules.is_empty(),"Era rules require matching original executable and archive provenance")
	check(preload("res://infrastructure/era_progression.gd").rules("wrong",fixture["source_sha256"]).is_empty(),"Mismatched era provenance must reject")
	if rules.is_empty(): quit(1); return
	var codec := preload("res://infrastructure/world_store.gd").new()
	var queries := 0
	for example: Dictionary in fixture["cases"]:
		queries+=example["steps"].size()
		for with_save: bool in [false,true]:
			global_cache=Era.restore(example.get("global",example["state"]))
			var cache: Dictionary=Era.restore(example["state"]) if example.get("local",false) else global_cache
			unlocked=example["unlocks"].duplicate()
			for i in range(example["steps"].size()):
				step=example["steps"][i]
				if step.has("unlocks"): unlocked=step["unlocks"].duplicate()
				if step.get("invalidate",false): cache["cache_valid"]=false
				events=[]
				var value: Variant=null
				if step.get("action","era")=="era":
					check(Era.refresh(cache,global_cache,rules,service),"Original era cache must refresh")
					value=cache["era"]
				else: check(Era.refresh(cache,global_cache,rules,service),"Original raw cache refresh must succeed")
				var actual := {"value":value,"state":cache,"global_state":global_cache,"events":events}
				check(actual==example["states"][i],"Original era %s query %d: %s / %s"%[example["name"],i,actual,example["states"][i]])
				if with_save:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"global":global_cache,"cache":cache,"unlocked":unlocked}))))
					global_cache=Era.restore(saved["global"])
					cache=Era.restore(saved["cache"]) if example.get("local",false) else global_cache
					unlocked=saved["unlocked"].duplicate()
	check(Era.restore({"cache_valid":true})==Era.initial(),"Research-only saves must invalidate missing period and era values")
	check(Era.restore({"cache_valid":true,"period":1}).is_empty(),"Half-present era caches must reject")
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("era_rules",{})==rules,"The source campaign must receive the recovered period and era rules")
	var authoritative := Era.initial()
	var detached := Era.restore(authoritative)
	unlocked=["ERA_STICKER_2"]
	check(Era.era(detached,rules,service)==2 and authoritative==Era.initial(),"Detached era inspection cannot modify authoritative cache state")
	var Rewards = preload("res://simulation/source_rewards.gd")
	var reward_rules := {"era":rules,"availability":{"unregistered_limit":268435455},
		"queue":preload("res://infrastructure/reward_queue.gd").content(fixture["executable_sha256"],fixture["source_sha256"])["rules"],
		"dispatch":preload("res://infrastructure/reward_dispatch.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])}
	var rewards := Rewards.initial()
	rewards["research_context"]["cache_valid"]=true
	check(Rewards.current_era(rewards,reward_rules,service)==2 and Era.valid(rewards["research_context"]),"The reward owner must migrate an older research-only cache before reading its era")
	var saved_rewards := Rewards.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(rewards)))))
	events=[]
	check(Rewards.current_era(saved_rewards,reward_rules,service)==2 and events.is_empty(),"A restored valid reward-era cache must retain its values without repeating unlock queries")
	print("Original era cache: %d cases, %d queries, save continuation, %d failures"%[fixture["cases"].size(),queries,failures])
	quit(1 if failures else 0)
