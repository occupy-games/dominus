extends SceneTree

const Lifetime = preload("res://simulation/source_chest_lifetime.gd")
const Numbers = preload("res://simulation/progression.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0
var example: Dictionary
var step: Dictionary
var chests: Array=[]
var events: Array=[]
var unlocks: Array=[]
var opened_count := 0
var status_calls := 0
var grants: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func stored_numbers(value: Variant) -> Variant:
	if value is float: return Terrain.f32(float(value))
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(stored_numbers(item))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key]=stored_numbers(value[key])
		return result
	return value


func profile(key: String,default: Variant=null) -> Variant:
	return step.get(key,example.get(key,default))


func service(name: String,handle: int,args: Array) -> Variant:
	events.append([name,handle,args.duplicate(true)])
	match name:
		"ground": return float(profile("ground",6))
		"sculpt": return {"active":bool(profile("sculpt_active",false)),"height":float(profile("sculpt_height",20))}
		"influence": return bool(profile("influence",true))
		"mission_mode": return int(profile("mission_mode",0))
		"reward_available": return bool(profile("reward_available",true))
		"reward_status":
			var values: Variant=profile("reward_status",false)
			var result: bool=bool(values[mini(status_calls,values.size()-1)]) if values is Array else bool(values)
			status_calls+=1
			return result
		"reward_type_a","reward_type_b","mode2_ready","mode2_available": return bool(profile(name,false))
		"unlocked": return args[0] in unlocks
		"unlock":
			if not args[0] in unlocks: unlocks.append(args[0])
		"increment_opened": opened_count+=1
		"grant":
			grants.append([handle,args.duplicate(true)])
			if profile("unlock_during_grant",false) and not "CHEST_BONUS_1" in unlocks: unlocks.append("CHEST_BONUS_1")
	return null


func perform(rules: Dictionary) -> Variant:
	var action: String=step.get("action","advance")
	if action=="advance": return Lifetime.advance(chests,rules,float(step.get("delta",.1)),int(profile("mode",0)),int(example.get("authored_words",0)),service)
	var selected: Dictionary={}
	for chest: Dictionary in chests:
		if int(chest["handle"])==int(step.get("handle",chests[0]["handle"])): selected=chest; break
	if action=="exposed": return Lifetime.exposed(selected,rules,service)
	return Lifetime.begin_open(selected,rules,service)


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_chest_lifetime.json")))
	var content := preload("res://infrastructure/storm_chests.gd").load_content(fixture["executable_sha256"],fixture["source_sha256"])
	check(not content.is_empty(),"Original lifetime metadata must match source provenance")
	if content.is_empty(): quit(1); return
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition["story"]["chest_lifetime_rules"]==content["lifetime_rules"],"Authored campaign must receive original chest timing and reward gates")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for raw: Dictionary in fixture["cases"]:
		example=raw
		transitions+=example["steps"].size()
		var rules: Dictionary=content["lifetime_rules"].duplicate(true)
		rules.merge(example.get("rules",{}),true)
		for with_save: bool in [false,true]:
			var loaded := Lifetime.restore(stored_numbers(example["chests"]))
			check(loaded["ok"],"Native case %s must start from valid plain state"%example["name"])
			chests=loaded["chests"]
			unlocks=example.get("unlocks",[]).duplicate(true)
			opened_count=0
			grants=[]
			for index in range(example["steps"].size()):
				step=example["steps"][index]
				events=[]
				status_calls=0
				var output: Variant=perform(rules)
				var expected: Dictionary=stored_numbers(example["states"][index])
				var sorted_unlocks: Array=unlocks.duplicate(true)
				sorted_unlocks.sort()
				check(Numbers.canonical_numbers(output)==Numbers.canonical_numbers(expected["output"]),"Native %s step %d output must match: %s / %s"%[example["name"],index,output,expected["output"]])
				check(Numbers.canonical_numbers(chests)==Numbers.canonical_numbers(expected["chests"]),"Native %s step %d must preserve phase, height, elapsed time and pool order"%[example["name"],index])
				check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]),"Native %s step %d service order must match: %s / %s"%[example["name"],index,events,expected["events"]])
				check(sorted_unlocks==expected["unlocks"] and opened_count==int(expected["opened_count"]),"Native %s step %d unlocks and opening counter must match"%[example["name"],index])
				if with_save:
					var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"chests":chests,"unlocks":unlocks,"opened_count":opened_count,"grants":grants}))))
					var restored := Lifetime.restore(saved["chests"])
					check(restored["ok"] and Numbers.canonical_numbers(restored["chests"])==Numbers.canonical_numbers(chests),"Every lifetime boundary must restore before continuing")
					chests=restored["chests"]
					unlocks=saved["unlocks"]
					opened_count=int(saved["opened_count"])
					grants=Numbers.canonical_numbers(saved["grants"])
			if example["name"]=="full_lifetime" or example["name"]=="no_repeated_reward": check(grants.size()==1,"The source reward transition must grant once across repeated ticks and restoration")
	# The validated player command composes the same original influence,
	# phase/exposure and opening helpers; rejected repeats cannot reset time.
	example={}
	step={}
	chests=Lifetime.restore(stored_numbers(fixture["cases"][0]["chests"]))["chests"]
	var rules: Dictionary=content["lifetime_rules"]
	step={"influence":false}
	var before := chests.duplicate(true)
	check(not Lifetime.try_open(chests[0],rules,service) and chests==before,"Out-of-influence opening must reject without mutation")
	step={}
	check(Lifetime.try_open(chests[0],rules,service),"An exposed chest in influence must accept the ordinary opening command")
	chests[0]["core"]["source_slots"]["58"]=.5
	before=chests.duplicate(true)
	check(not Lifetime.try_open(chests[0],rules,service) and chests==before,"Repeated player input must not restart an opening chest")
	var invalid := before.duplicate(true)
	invalid.append(invalid[0].duplicate(true))
	check(not Lifetime.restore(invalid)["ok"],"Duplicate pool identities must reject on restore")
	invalid=before.duplicate(true)
	invalid[0]["core"]["source_slots"]["58"]=-1.0
	check(not Lifetime.restore(invalid)["ok"],"Invalid saved lifetime timing must reject")
	var invalid_rules := rules.duplicate(true)
	invalid_rules["open_seconds"]=NAN
	events=[]
	check(not Lifetime.advance(chests,invalid_rules,.1,0,0,service)["ok"] and events.is_empty(),"Invalid rules must reject before queries or reward side effects")
	check(not Lifetime.advance(chests,rules,-.1,0,0,service)["ok"],"Negative time must reject")
	print("Original chest lifetime: %d cases, %d transitions, save continuation, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
