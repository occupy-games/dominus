extends RefCounted
## Original 0x10065a10 state selection with supplied validity and random stream.
## Selecting a state does not enter it, move a follower or start active work.

const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["capacity","iteration_limit","rng_multiplier","rng_increment","rng_shift","rng_mask"]:
		if not Schedule.integer_between(rules.get(key),0,4294967295): return false
	var divisor: Variant=rules.get("random_divisor")
	return rules["capacity"]>0 and rules["capacity"]<=20 and rules["iteration_limit"]>0 and rules["iteration_limit"]<=100 and rules["rng_shift"]<=31 and (divisor is int or divisor is float) and is_finite(float(divisor)) and divisor>0


static func valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("name") is String: return false
	for key: String in ["next","skip_to"]:
		if not Schedule.integer_between(entry.get(key),-1,2147483647): return false
	var probability: Variant=entry.get("skip_probability")
	return (probability is int or probability is float) and is_finite(float(probability)) and absf(float(probability))<=1000000


static func valid_content(content: Variant) -> bool:
	if not content is Dictionary or not valid_rules(content.get("rules")) or not valid_entry(content.get("default_state")) or not content.get("actions") is Array or content["actions"].size()>251: return false
	var identities := {}
	for action: Variant in content["actions"]:
		if not action is Dictionary or not Schedule.integer_between(action.get("id"),0,250) or identities.has(int(action["id"])) or not action.get("name") is String or action["name"].is_empty() or not action.get("states") is Array: return false
		identities[int(action["id"])]=true
		var indices := {}
		for entry: Variant in action["states"]:
			if not entry is Dictionary or not Schedule.integer_between(entry.get("index"),0,int(content["rules"]["capacity"])-1) or indices.has(int(entry["index"])) or not entry.get("available") is bool: return false
			indices[int(entry["index"])]=true
			if entry["available"] and not valid_entry(entry): return false
	return true


static func entries(content: Dictionary,identity: int) -> Array:
	if not valid_content(content): return []
	for action: Dictionary in content["actions"]:
		if int(action["id"])!=identity: continue
		var result: Array=[]
		for i in range(int(content["rules"]["capacity"])): result.append(content["default_state"].duplicate(true))
		for entry: Dictionary in action["states"]:
			if not entry["available"]: return []
			result[int(entry["index"])]={"name":entry["name"],"next":int(entry["next"]),"skip_to":int(entry["skip_to"]),"skip_probability":Terrain.f32(float(entry["skip_probability"]))}
		return result
	return []


static func random_word(stream: Dictionary,rules: Dictionary) -> int:
	stream["state"]=(int(stream["state"])*int(rules["rng_multiplier"])+int(rules["rng_increment"]))&0xffffffff
	return (int(stream["state"])>>int(rules["rng_shift"]))&int(rules["rng_mask"])


static func choose(states: Array,begin: int,rules: Dictionary,random: Callable,check: Callable) -> Dictionary:
	if not valid_rules(rules) or states.size()!=int(rules["capacity"]) or begin<0 or not random.is_valid() or not check.is_valid(): return {}
	for entry: Variant in states:
		if not valid_entry(entry): return {}
	var index := begin
	var attempts := 0
	var lost := false
	while index<int(rules["capacity"]):
		if index<0: return {} # Reading a previous action's bytes is unsupported.
		if attempts>=int(rules["iteration_limit"]):
			index=int(rules["capacity"])
			break
		var entry: Dictionary=states[index].duplicate(true)
		var probability := Terrain.f32(float(entry["skip_probability"]))
		var skip := false
		if probability>0:
			var sample := Terrain.f32(float(int(random.call()))/float(rules["random_divisor"]))
			skip=sample<probability
		if not skip:
			var verdict: Variant=check.call(index,entry)
			if not verdict is Dictionary or not verdict.get("valid") is bool or not verdict.get("lost") is bool: return {}
			lost=lost or bool(verdict["lost"])
			if verdict["valid"]: break
		var destination := int(entry["skip_to"])
		if destination<0: destination=int(entry["next"])
		index=index+1 if destination<0 else destination
		attempts+=1
	return {"index":0 if lost else index}
