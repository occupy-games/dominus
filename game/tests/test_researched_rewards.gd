extends SceneTree

const Rewards = preload("res://simulation/source_rewards.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Queue = preload("res://simulation/source_reward_queue.gd")
const Research = preload("res://simulation/source_card_research.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var state: Dictionary
var events: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		if failures<12: push_error(message)


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true),state["queue"]["queue"].size()])
	if name=="context": return 12345
	if name=="mission_type": return 1
	return null


func observe(name: String,args: Array) -> void:
	events.append([name,args.duplicate(true),state["queue"]["queue"].size()])


func word() -> int:
	push_error("Research cannot consume an extra random word")
	failures+=1
	return 0


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_researched_rewards.json")))
	var queue := preload("res://infrastructure/reward_queue.gd").content(fixture["executable_sha256"],fixture["source_sha256"])
	var research := preload("res://infrastructure/card_research.gd").content(fixture["executable_sha256"],fixture["source_sha256"],"initialworldsetup6")
	var dispatch := preload("res://infrastructure/reward_dispatch.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	var rules := {"queue":queue["rules"],"research":research["rules"],"dispatch":dispatch,"availability":{"unregistered_limit":268435455}}
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening["story"]["card_research_rules"]==research["rules"] and opening["story"]["source_research_cards"]==research["cards"],"The source campaign must receive its own recovered research catalog")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for example: Dictionary in fixture["cases"]:
		transitions+=example["steps"].size()
		for with_save: bool in [false,true]:
			state=Rewards.initial()
			state["research_context"]["cache_valid"]=true # Explicit controlled native cache, invalidated on completion.
			state["availability"]=Availability.restore(example["availability"])
			state["queue"]["delay"]=1.0
			var records: Dictionary=example["records"]
			for i in range(example["steps"].size()):
				if with_save:
					state=Rewards.restore(codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state)))))
					check(not state.is_empty(),"Shared queue/research inventory must restore before each step")
				var step: Dictionary=example["steps"][i]
				var availability_events: Array=[]
				events=[]
				var value: Variant=false
				match step["action"]:
					"admit": value=Queue.admit(state["queue"],state["availability"],records,rules["queue"],rules["availability"],int(records["cards"][0]["id"]),0,int(step.get("flags",3)),8,1012,0,service,availability_events)
					"take": value=Rewards.take(state,rules,0,12,0,100.0,service)
					"consume": value=Rewards.consume(state,records,rules,0,int(example.get("player",0)),word,service,availability_events)
					"temple": value=Rewards.from_site(state,records,rules,int(step["reward"]),1012,0,true,0,word,service,availability_events,observe)
					"assign": value=Rewards.assign_card(state,records,rules,int(records["cards"][0]["id"]),int(step["sticker"]),step.get("allow_internal",false),service,availability_events)
					"complete": value=Rewards.complete_card(state,records,rules,int(records["cards"][0]["id"]),int(example.get("player",0)),service,availability_events)
				var actual := {"value":value,"state":state["queue"],"dispatch":state["dispatch"],"availability":state["availability"],"research_context":state["research_context"],"events":events,"availability_events":availability_events,"random_calls":0}
				check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(example["states"][i]),"Original researched reward %s step %d: %s / %s"%[example["name"],i,actual,example["states"][i]])
	state=Rewards.initial()
	var before := state.duplicate(true)
	check(not Rewards.consume(state,{"cards":[{"id":50}],"stickers":[],"special":[]},rules,0,0,word,service,[]) and state==before,"Unresolved research catalogs must reject before changing shared inventory")
	var legacy := state.duplicate(true)
	legacy.erase("research_context")
	var migrated := Rewards.restore(legacy)
	check(not migrated.is_empty() and not migrated["research_context"]["cache_valid"],"Older shared reward saves must invalidate a missing derived research cache")
	migrated["research_context"]["cache_valid"]=1
	check(Rewards.restore(migrated).is_empty(),"Malformed persisted research context must reject")
	print("Original researched rewards: %d cases, %d transitions, save continuation, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
