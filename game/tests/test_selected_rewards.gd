extends SceneTree

const Rewards = preload("res://simulation/source_rewards.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var state: Dictionary
var events: Array=[]
var example: Dictionary
var step: Dictionary
var random_calls := 0
var active_unlocks: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		if failures<10: push_error(message)


func profile(name: String,default: Variant=null) -> Variant:
	return step.get(name,example.get(name,default))


func service(name: String,args: Array) -> Variant:
	if name=="claim_clock": return profile("clock",{"seconds":123,"millis":[123000,0]}).duplicate(true)
	events.append([name,args.duplicate(true),state["queue"]["queue"].size()])
	match name:
		"era": return profile("era",1)
		"is_discovery": return profile("is_discovery",true)
		"unlocked": return args[0] in active_unlocks
		"acquired": active_unlocks.append_array(example.get("acquisition_unlocks",{}).get("@"+str(int(args[0])),[]))
		"context": return 12345
		"mission_type": return profile("mission_type",1)
		"currency": return 1
		"mission_spawn": return {"position":profile("spawn_position",[3.0,4.0,5.0]),"extra":profile("spawn_extra",[0.0,0.0,0.0])}
	return null


func word() -> int:
	var words: Array=example["words"]
	var value := int(words[random_calls%words.size()])
	random_calls+=1
	return value


func fixture_path() -> String:
	return "res://tests/fixtures/source_selected_rewards.json"


func check_name() -> String:
	return "Original selected rewards"


func extra_checks(_rules: Dictionary) -> void:
	pass


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string(fixture_path())))
	var queue := preload("res://infrastructure/reward_queue.gd").content(fixture["executable_sha256"],fixture["source_sha256"])
	var research := preload("res://infrastructure/card_research.gd").content(fixture["executable_sha256"],fixture["source_sha256"],"initialworldsetup6")
	var dispatch := preload("res://infrastructure/reward_dispatch.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	var selection := preload("res://infrastructure/sticker_selection.gd").bound_rules(fixture["executable_sha256"],fixture["source_sha256"])
	check(not selection.is_empty(),"Composed selector requires original numeric source identities")
	var base := {"queue":queue["rules"],"research":research["rules"],"dispatch":dispatch,"selection":selection,"availability":{"unregistered_limit":268435455}}
	if fixture.get("source_era",false): base["era"]=preload("res://infrastructure/era_progression.gd").rules(fixture["executable_sha256"],fixture["source_sha256"])
	var temple_rules := {}
	if fixture.get("source_temple",false): temple_rules=preload("res://infrastructure/temple_repair.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening["story"]["bound_sticker_selection_rules"]==selection,"The private campaign must receive matching source selector bindings")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for case: Dictionary in fixture["cases"]:
		example=case
		transitions+=example["steps"].size()
		var rules := base.duplicate(true)
		var unlock_content := {}
		if fixture.get("source_unlock_dispatch",false):
			unlock_content=preload("res://infrastructure/unlock_dispatch.gd").content(fixture["executable_sha256"],fixture["source_sha256"],example["scope"])
			check(not unlock_content.is_empty(),"Composed rewards require the authored dependency graph")
			rules["unlock"]=unlock_content["rules"]
		for name: String in example.get("configuration",{}): rules["selection"]["configuration"][name]=example["configuration"][name]
		for with_save: bool in [false,true]:
			state=Rewards.initial()
			state["research_context"]["cache_valid"]=true # Explicit controlled native cache.
			if example.has("era_cache"): state["research_context"]=example["era_cache"].duplicate(true)
			state["availability"]=Availability.restore(example["availability"])
			if fixture.get("source_unlock_dispatch",false):
				check(Rewards.prepare_unlocks(state,unlock_content),"Composed source unlock graph must prepare")
				if example.has("unlock_state"):
					state["unlock_dispatch"]=preload("res://simulation/source_unlock_dispatch.gd").restore(example["unlock_state"])
					for dependency: Dictionary in unlock_content["dependencies"]: check(preload("res://simulation/source_unlock_dispatch.gd").register(state["unlock_dispatch"],int(dependency["unlock"]),int(dependency["condition"]),int(dependency["phase"])),"Controlled source gate state must retain actual registration")
				check(state["unlock_dispatch"]==example["prepared_unlocks"],"Prepared acquisition dependencies must match original registration")
			state["queue"]["delay"]=1.0
			random_calls=0
			active_unlocks=example.get("unlocks",[]).duplicate()
			var records: Dictionary=example["records"]
			var temple: Dictionary=example.get("temple",{}).duplicate(true)
			if example.has("source"):
				records=Rewards.prepare_catalog(state,example["source"],records["special"],records["stories"])
				check(not records.is_empty(),"Source reward catalog must prepare before redemption")
				if records.is_empty(): continue
				var bound: Dictionary=example["prepared"]
				var plain_records := records.duplicate(true)
				plain_records.erase("registry")
				plain_records.erase("detail_registry")
				check(state["availability"]==bound["availability"] and plain_records==bound["records"] and records["registry"]==bound["registry"] and records["detail_registry"]==bound["details"],"Prepared source catalog must match original registration before its first reward")
			for i in range(example["steps"].size()):
				if with_save:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"rewards":state,"random_calls":random_calls,"unlocks":active_unlocks,"temple":temple}))))
					state=Rewards.restore(saved["rewards"])
					random_calls=int(saved["random_calls"])
					active_unlocks=saved["unlocks"].duplicate()
					if fixture.get("source_temple",false): temple=preload("res://simulation/source_temple_repair.gd").restore(saved["temple"])
					check(not state.is_empty(),"Selected reward state must restore at every boundary")
				step=example["steps"][i]
				var availability_events: Array=[]
				events=[]
				var value: Variant=false
				match step["action"]:
					"force_unlock": value=Rewards.force_unlock(state,rules,int(step["id"]),service("claim_clock",[]),service,availability_events)
					"temple_pending": value=Rewards.temple_pending(state,temple,records,rules,temple_rules,int(profile("mode",0)),word,service,availability_events)
					"claim": value=Rewards.claim_unlock(state,rules,int(step["id"]),service("claim_clock",[]),service)
					"expire": value=Rewards.expire_unlocks(state,rules,service("claim_clock",[]),step.get("force",false),service)
					"query_era": value=Rewards.current_era(state,rules,service)
					"set_unlocks": active_unlocks=step["unlocks"].duplicate(); value=true
					"invalidate_era": state["research_context"]["cache_valid"]=false; value=true
					"dispatch": value=Rewards.request(state,records,rules,int(step["reward"]),int(step.get("source_id",1012)),int(step.get("flags",0)),int(step.get("reason",8)),int(step.get("override",0)),int(profile("mode",0)),word,service,availability_events)
					"chest","temple": value=Rewards.from_site(state,records,rules,int(step["reward"]),1012,0,step["action"]=="temple",int(profile("mode",0)),word,service,availability_events)
					"take": value=Rewards.take(state,rules,int(step.get("kind",0)),12,int(profile("mode",0)),100.0,service)
					"consume": value=Rewards.consume(state,records,rules,int(profile("mode",0)),int(profile("player",0)),word,service,availability_events)
					"assign": value=Rewards.assign_card(state,records,rules,int(records["cards"][0]["id"]),int(step["sticker"]),false,service,availability_events)
					"complete": value=Rewards.complete_card(state,records,rules,int(records["cards"][0]["id"]),int(profile("player",0)),service,availability_events)
				var actual := {"value":value,"state":state["queue"],"dispatch":state["dispatch"],"availability":state["availability"],"research_context":state["research_context"],"events":events,"availability_events":availability_events,"random_calls":random_calls}
				if fixture.get("source_unlock_dispatch",false): actual["unlock_state"]=state["unlock_dispatch"].duplicate(true)
				elif fixture.get("source_era",false): actual["unlocks"]=active_unlocks.duplicate()
				if fixture.get("source_temple",false): actual["temple"]=temple.duplicate(true)
				var expected: Dictionary=example["states"][i]
				if Numbers.canonical_numbers(actual)!=Numbers.canonical_numbers(expected):
					var different: Array=[]
					for field: String in actual:
						if Numbers.canonical_numbers(actual[field])!=Numbers.canonical_numbers(expected[field]): different.append(field)
					if failures==0:
						var output := FileAccess.open("res://../build/selected-reward-mismatch.json",FileAccess.WRITE)
						output.store_string(JSON.stringify({"case":example["name"],"step":i,"actual":actual,"expected":expected},"  "))
					check(false,"Original selected reward %s step %d differs in %s"%[example["name"],i,different])
	var invalid := base.duplicate(true)
	invalid["selection"]["kinds"]["@17"]="Reward_ChestSticker"
	check(not Rewards.valid_rules(invalid),"An unknown selector identity cannot be aliased to an original reward")
	extra_checks(base)
	print("%s: %d cases, %d transitions, save continuation, %d failures"%[check_name(),fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
