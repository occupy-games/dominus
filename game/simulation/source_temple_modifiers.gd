extends RefCounted
## Original per-temple upgrade masks. Slots advance for every source row of
## that family, including rows for a different temple or a locked upgrade.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_records(records: Variant) -> bool:
	if not records is Array or records.size()>128: return false
	var counts := [0,0]
	for record: Variant in records:
		if not record is Dictionary or not Numbers.integer_between(record.get("type"),1,4294967295) or not Numbers.integer_between(record.get("unlock"),0,4294967295) or not Numbers.integer_between(record.get("family"),0,1): return false
		counts[int(record["family"])]+=1
	return counts[0]<=64 and counts[1]<=64


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not Numbers.integer_between(state.get("generic_type"),1,4294967295): return false
	for key: String in ["x","z"]:
		var value: Variant=state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000 or Terrain.f32(float(value))!=float(value): return false
	for key: String in ["follower_modifiers","house_modifiers"]:
		var words: Variant=state.get(key)
		if not words is Array or words.size()!=2: return false
		for word: Variant in words:
			if not Numbers.integer_between(word,0,4294967295): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	result["generic_type"]=int(result["generic_type"])
	for key: String in ["x","z"]: result[key]=float(result[key])
	for key: String in ["follower_modifiers","house_modifiers"]:
		for i in range(2): result[key][i]=int(result[key][i])
	return result


static func any_active(state: Dictionary) -> bool:
	for key: String in ["follower_modifiers","house_modifiers"]:
		if int(state[key][0])!=0 or int(state[key][1])!=0: return true
	return false


static func refresh(state: Dictionary,records: Array,unlocked: Callable,service: Callable) -> bool:
	if not valid(state) or not valid_records(records) or not unlocked.is_valid() or not service.is_valid(): return false
	var had_any := any_active(state)
	state["follower_modifiers"]=[0,0]; state["house_modifiers"]=[0,0]
	var slots := [0,0]
	for record: Dictionary in records:
		var family := int(record["family"])
		var slot := int(slots[family])
		if int(record["type"])==int(state["generic_type"]) and bool(unlocked.call(int(record["unlock"]))):
			var field := "follower_modifiers" if family==0 else "house_modifiers"
			state[field][slot>>5]=int(state[field][slot>>5])|(1<<(slot&31))
		slots[family]+=1
	# The source invalidates only the first transition from no modifiers to
	# any modifiers, not every bit change and not the transition back to zero.
	if not had_any and any_active(state): service.call("invalidate_modifiers_at",[int(float(state["x"])),int(float(state["z"]))])
	return true
