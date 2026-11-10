extends SceneTree

const Unlocks = preload("res://simulation/source_unlock_dispatch.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var events: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		if failures<12: push_error(message)


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true)])
	return null


func fixture_path() -> String:
	return "res://tests/fixtures/source_unlock_dispatch.json"


func check_name() -> String:
	return "Original unlock dispatch"


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string(fixture_path())))
	var content := preload("res://infrastructure/unlock_dispatch.gd").content(fixture["executable_sha256"],fixture["source_sha256"],"initialworldsetup6")
	check(not content.is_empty(),"Authored unlock definitions must retain matching executable/table provenance")
	check(preload("res://infrastructure/unlock_dispatch.gd").content("wrong-hash",fixture["source_sha256"],"initialworldsetup6").is_empty(),"Mismatched unlock provenance must reject")
	if content.is_empty(): quit(1); return
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for case: Dictionary in fixture["cases"]:
		transitions+=case["steps"].size()
		for save_each: bool in [false,true]:
			var state := Unlocks.restore(case["state"])
			check(not state.is_empty(),"Original unlock state must restore: "+case["name"])
			for dependency: Dictionary in case["dependencies"]:
				check(Unlocks.register(state,int(dependency["unlock"]),int(dependency["condition"]),int(dependency["phase"])),"Original dependency must register: "+case["name"])
			check(state==case["prepared"],"Original raw/string registration must agree: "+case["name"])
			var rules: Dictionary=case.get("rules",content["rules"])
			for i in range(case["steps"].size()):
				if save_each:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(state))))
					state=Unlocks.restore(saved)
					check(not state.is_empty(),"Unlock continuation must restore: "+case["name"])
				var step: Dictionary=case["steps"][i]
				events=[]
				var value: Variant=true
				match step["action"]:
					"register": value=Unlocks.register(state,int(step["unlock"]),int(step["condition"]),int(step["phase"]))
					"claim": value=Unlocks.claim(state,rules,int(step["id"]),int(step.get("seconds",0)),step.get("now",[0,0]),service)
					"propagate": value=Unlocks.propagate(state,int(step["id"]),service)
					"rebuild": value=Unlocks.rebuild(state,rules,int(step.get("seconds",123)),step.get("now",[0,0]),service)
					"expire": value=Unlocks.expire(state,rules,int(step.get("seconds",123)),step.get("now",[0,0]),step.get("force",false),service)
					"remaining": value=Unlocks.remaining(state,int(step["id"]),step.get("now",[0,0]),step.get("sse2",false))
					"unlocked": value=Unlocks.unlocked(state,int(step["id"]))
					"can_unlock": value=Unlocks.can_unlock(state,int(step["id"]))
				var expected: Dictionary=case["states"][i]
				check(value==expected["value"],"Original unlock result: %s step %d: %s != %s"%[case["name"],i,value,expected["value"]])
				check(state==expected["state"],"Original unlock storage: %s step %d"%[case["name"],i])
				check(events==expected["events"],"Original unlock callback order: %s step %d"%[case["name"],i])
	var state := Unlocks.prepare(content["dependencies"])
	check(not state.is_empty(),"All authored source rows must prepare in a detached factory")
	var before := state.duplicate(true)
	check(not Unlocks.register(state,7,7,1) and state==before,"A cyclic source graph must reject before mutation")
	var malformed := state.duplicate(true)
	malformed["rows"][0]["compound"]=int(malformed["rows"][0]["compound"])^1
	check(Unlocks.restore(malformed).is_empty(),"Corrupt saved dependency hashes must reject")
	malformed=state.duplicate(true)
	malformed["received"]["@01"]=true
	check(Unlocks.restore(malformed).is_empty(),"Noncanonical saved unlock identities must reject")
	events=[]
	check(not Unlocks.claim(state,content["rules"],3,-1,[0,0],service) and state==before and events.is_empty(),"Malformed claim inputs must reject atomically")
	var legacy := Unlocks.initial()
	legacy["first_seen"]={"@2058":3,"@10":4,"@1034":5}
	legacy.erase("first_seen_order")
	var migrated := Unlocks.restore(legacy)
	check(migrated.get("first_seen_order")==["@2058","@10","@1034"] and not legacy.has("first_seen_order"),"Older saves must migrate persistent insertion order without mutating their input")
	malformed=migrated.duplicate(true)
	malformed["first_seen_order"]=["@10","@10","@1034"]
	check(Unlocks.restore(malformed).is_empty(),"Duplicate persistent-order identities must reject")
	var hidden_cycle := Unlocks.initial()
	hidden_cycle["rows"]=[{"unlock":1,"condition":2,"compound":preload("res://simulation/source_hash.gd").pair(2,1),"phase":3},{"unlock":2,"condition":1,"compound":preload("res://simulation/source_hash.gd").pair(1,2),"phase":1}]
	before=hidden_cycle.duplicate(true)
	events=[]
	check(Unlocks.valid(hidden_cycle) and not Unlocks.rebuild(hidden_cycle,content["rules"],1,[0,0],service) and hidden_cycle==before and events.is_empty(),"A phase reset that would enable a native recursive cycle must reject before any effects")
	print("%s: %d cases, %d transitions, save continuation, %d failures"%[check_name(),fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
