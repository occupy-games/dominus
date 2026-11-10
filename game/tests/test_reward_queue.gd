extends SceneTree

const Queue = preload("res://simulation/source_reward_queue.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Numbers = preload("res://simulation/progression.gd")
const Dispatch = preload("res://simulation/source_reward_dispatch.gd")
const Rewards = preload("res://simulation/source_rewards.gd")
var example: Dictionary
var step: Dictionary
var state: Dictionary
var research: Dictionary
var events: Array
var random_calls := 0
var failures := 0
var available: Dictionary
var dispatch: Dictionary
var dispatch_rules: Dictionary
var limits := {"unregistered_limit":268435455}
var availability_events: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func profile(name: String,default: Variant=null) -> Variant:
	return step.get(name,example.get(name,default))


func word() -> int:
	var words: Array=example.get("words",[0])
	var result := int(words[random_calls%words.size()])
	random_calls+=1
	return result


func service(name: String,args: Array) -> Variant:
	if name in ["pack_count","pack_index"]: return dispatch.get(name,0)
	events.append([name,args.duplicate(true),state["queue"].size()])
	match name:
		"research_remaining": return maxi(0,int(profile("research_remaining",0))-int(research.get(str(args[0]),0)))
		"research_complete": return profile("research_complete",false)
		"research_credit": research[str(args[0])]=int(research.get(str(args[0]),0))+int(args[2])
		"mission_type": return profile("mission_type",1)
		"mission_spawn": return {"position":profile("spawn_position",[3.0,4.0,5.0]),"extra":profile("spawn_extra",[0.0,0.0,0.0])}
		"select_sticker": return example.get("selected_sticker",0)
		"select_event_reward": return example.get("selected_event",0)
		"card_acquired": return Availability.acquired(available,int(args[0]))
	return null


func observe(name: String,args: Array) -> void:
	events.append([name,args.duplicate(true),state["queue"].size()])


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_reward_queue.json")))
	var content := preload("res://infrastructure/reward_queue.gd").content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Reward queue requires original executable and balance provenance")
	if content.is_empty(): quit(1); return
	var base: Dictionary=content["rules"]
	dispatch_rules=preload("res://infrastructure/reward_dispatch.gd").load_rules(fixture["executable_sha256"],fixture["source_sha256"])
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for case: Dictionary in fixture["cases"]:
		example=case
		var rules := base.duplicate(true)
		for field: String in ["auto_claim","delay","totem_upgrade"]: rules[field]=example.get(field,base[field])
		for with_save: bool in [false,true]:
			var fresh := Queue.initial()
			fresh["delay"]=1.0
			state=Queue.restore(example.get("state",fresh))
			check(not state.is_empty(),"Original reward queue must restore "+example["name"])
			available=Availability.restore(example.get("availability",Availability.initial()))
			dispatch=Dispatch.restore(example.get("dispatch_state",{"stories_acquired":[],"pack_count":int(example.get("pack_count",0)),"pack_index":int(example.get("pack_index",0))}))
			research={}
			random_calls=0
			for i in range(example["steps"].size()):
				step=example["steps"][i]
				if with_save:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"rewards":{"queue":state,"dispatch":dispatch,"availability":available},"research":research,"random_calls":random_calls}))))
					var restored := Rewards.restore(saved["rewards"])
					check(not restored.is_empty(),"Composed rewards must restore at every transition")
					state=restored["queue"]
					available=restored["availability"]
					dispatch=restored["dispatch"]
					research=saved["research"]
					random_calls=int(saved["random_calls"])
				events=[]
				availability_events=[]
				var value: Variant=false
				match step["action"]:
					"admit": value=Queue.admit(state,available,example["records"],rules,limits,int(step.get("reward",50)),int(step.get("kind",0)),int(step.get("flags",2)),int(step.get("reason",8)),int(step.get("source_id",1012)),int(profile("mode",0)),service,availability_events)
					"consume": value=Rewards.consume({"queue":state,"dispatch":dispatch,"availability":available},example["records"],{"queue":rules,"dispatch":dispatch_rules,"availability":limits},int(profile("mode",0)),int(profile("player",0)),word,service,availability_events)
					"take": value=Rewards.take({"queue":state,"dispatch":dispatch,"availability":available},{"queue":rules,"dispatch":dispatch_rules,"availability":limits},int(step.get("kind",0)),int(step.get("reason",12)),int(profile("mode",0)),float(profile("population",100.0)),service)
					"select": value=Queue.select(state,rules,int(step.get("kind",0)),int(step.get("reason",12)),int(profile("mode",0)),float(profile("population",100.0)),service)
					"can_acquire": value=Availability.can_acquire(available,int(step["reward"]),int(step["count"]),limits,availability_events)
					"acquire": value=Availability.acquire(available,int(step["reward"]),int(step["count"]),limits,availability_events,rules["exempt"])
					"spend": value=Availability.spend(available,int(step["reward"]),int(step["count"]),rules["exempt"])
					"dispatch","chest","temple":
						var catalogs := {"stories":example["records"].get("stories",[]),"packs":example["records"].get("packs",[]),"cards":example["records"]["cards"].duplicate(true),"stickers":example["records"]["stickers"],"special":example["records"]["special"]}
						for card_: Dictionary in catalogs["cards"]:
							if not card_.has("silent"): card_["silent"]=0
						var combined := {"availability":available,"dispatch":dispatch,"queue":state}
						var combined_rules := {"availability":limits,"dispatch":dispatch_rules,"queue":rules}
						if step["action"]=="dispatch": value=Rewards.request(combined,catalogs,combined_rules,int(step["reward"]),int(step.get("source_id",1012)),int(step.get("flags",0)),int(step.get("reason",8)),int(step.get("override",0)),int(profile("mode",0)),word,service,availability_events,observe)
						else: value=Rewards.from_site(combined,catalogs,combined_rules,int(step["reward"]),int(step.get("source_id",1012)),int(step.get("flags",0)),step["action"]=="temple",int(profile("mode",0)),word,service,availability_events,observe)
				var actual := {"value":value,"state":state,"dispatch":dispatch,"availability":available,"availability_events":availability_events,"events":events,"random_calls":random_calls,"research":research}
				var expected: Dictionary=example["states"][i]
				check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(expected),"Original %s step %d queue: %s / %s"%[example["name"],i,actual,expected])
		transitions+=example["steps"].size()
	events=[]
	state=Queue.initial()
	var before := state.duplicate(true)
	check(not Queue.admit(state,Availability.initial(),{},base,limits,50,0,2,8,1012,0,service,[]) and state==before and events.is_empty(),"Unresolved catalogs must reject before currency, queue or inventory mutations")
	var invalid := Queue.initial()
	invalid["queue"]=[{"kind":0,"reason":8,"source_id":1,"reward":50,"flags":0,"taken":1,"display":true}]
	check(Queue.restore(invalid).is_empty(),"Malformed saved reward flags must reject")
	print("Original reward queue: %d cases, %d transitions, save continuation, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
