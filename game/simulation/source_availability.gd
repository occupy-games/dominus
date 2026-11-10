extends RefCounted
## Original stock/acquisition capacity and owned counts. Missing native limits
## initialize plain table entries and diagnostic intents, without doing I/O.

const Schedule = preload("res://simulation/source_plot_schedule.gd")
const MASK := 4294967295
const REGISTRIES := ["stock_registered","acquisition_registered"]
const COUNTERS := ["stock_limits","acquisition_limits","acquired","spent"]


static func initial() -> Dictionary:
	var result := {}
	for key: String in REGISTRIES+COUNTERS: result[key]={}
	return result


static func valid_key(value: Variant) -> bool:
	if value is String: return not value.is_empty() and value.length()<=256 and not value.to_utf8_buffer().has(0)
	return Schedule.integer_between(value,0,MASK)


static func key(value: Variant) -> String:
	return str(value) if value is String else "@"+str(int(value))


static func valid_rules(rules: Variant) -> bool:
	return rules is Dictionary and Schedule.integer_between(rules.get("unregistered_limit"),0,MASK)


static func read(state: Dictionary,table: String,id: String) -> int:
	if not state[table].has(id): state[table][id]=0
	return int(state[table][id])


static func register(state: Dictionary,value: Variant,stock: int,acquisition: int) -> bool:
	if not valid_key(value) or not Schedule.integer_between(stock,0,MASK) or not Schedule.integer_between(acquisition,0,MASK): return false
	var id := key(value)
	# The source checks stock registration only. It cannot repair an existing
	# stock entry with a missing acquisition entry or overwrite edited limits.
	if state["stock_registered"].get(id,false): return true
	state["stock_registered"][id]=true
	state["acquisition_registered"][id]=true
	state["stock_limits"][id]=mini(stock,acquisition)
	state["acquisition_limits"][id]=acquisition
	read(state,"acquired",id)
	read(state,"spent",id)
	return true


static func limit(state: Dictionary,id: String,kind: String,rules: Dictionary,events: Array) -> int:
	if not state[kind+"_registered"].get(id,false):
		events.append({"type":"unregistered_limit","kind":kind,"key":id})
		state[kind+"_limits"][id]=int(rules["unregistered_limit"])
		state[kind+"_registered"][id]=true
	return read(state,kind+"_limits",id)


static func available(state: Dictionary,value: Variant,rules: Dictionary,events: Array) -> int:
	if not valid_key(value) or not valid_rules(rules): return 0
	var id := key(value)
	# The original reads acquisition before stock. Its subtractions and final
	# minimum are unsigned 32-bit operations, including over-limit states.
	var acquisition := limit(state,id,"acquisition",rules,events)
	var stock := limit(state,id,"stock",rules,events)
	var acquired := read(state,"acquired",id)
	var again := read(state,"acquired",id)
	var spent := read(state,"spent",id)
	var acquisition_left := (acquisition-acquired)&MASK
	var stock_left := (stock-((again-spent)&MASK))&MASK
	return mini(acquisition_left,stock_left)


static func owned(state: Dictionary,value: Variant) -> int:
	if not valid_key(value): return 0
	var id := key(value)
	return (read(state,"acquired",id)-read(state,"spent",id))&MASK


static func acquired(state: Dictionary,value: Variant) -> int:
	if not valid_key(value): return 0
	return read(state,"acquired",key(value))


static func can_acquire(state: Dictionary,value: Variant,count: int,rules: Dictionary,events: Array) -> bool:
	if not valid_key(value) or not valid_rules(rules) or not Schedule.integer_between(count,0,MASK): return false
	var id := key(value)
	var first := read(state,"acquired",id)
	var again := read(state,"acquired",id)
	var spent := read(state,"spent",id)
	if ((again-spent+count)&MASK)>limit(state,id,"stock",rules,events): return false
	return ((first+count)&MASK)<=limit(state,id,"acquisition",rules,events)


static func acquire(state: Dictionary,value: Variant,count: int,rules: Dictionary,events: Array,exempt: Array=[]) -> bool:
	if not valid_key(value) or not valid_rules(rules) or not Schedule.integer_between(count,0,MASK): return false
	if value in exempt: return true
	if not can_acquire(state,value,count,rules,events): return false
	var id := key(value)
	state["acquired"][id]=(read(state,"acquired",id)+count)&MASK
	return true


static func spend(state: Dictionary,value: Variant,count: int,exempt: Array=[]) -> bool:
	if not valid_key(value) or not Schedule.integer_between(count,0,MASK): return false
	if value in exempt: return true
	var id := key(value)
	if ((read(state,"acquired",id)-read(state,"spent",id))&MASK)<count: return false
	state["spent"][id]=(read(state,"spent",id)+count)&MASK
	return true


static func valid(state: Variant) -> bool:
	if not state is Dictionary: return false
	for table: String in REGISTRIES+COUNTERS:
		if not state.get(table) is Dictionary or state[table].size()>1000000: return false
		for id: Variant in state[table]:
			if not id is String or not valid_key(id): return false
			if table in REGISTRIES:
				if not state[table][id] is bool: return false
			elif not Schedule.integer_between(state[table][id],0,MASK): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var state: Dictionary=saved.duplicate(true)
	for kind: String in ["stock","acquisition"]:
		for id: String in state[kind+"_registered"]:
			if state[kind+"_registered"][id] and not state[kind+"_limits"].has(id): state[kind+"_limits"][id]=0
	for table: String in COUNTERS:
		for id: String in state[table]: state[table][id]=int(state[table][id])
	return state
