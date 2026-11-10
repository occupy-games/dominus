extends RefCounted
## Ordered source dependency graph and claims. Clocks and notification services
## are explicit simulation inputs; no renderer or host time participates.

const Hash = preload("res://simulation/source_hash.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Availability = preload("res://simulation/source_availability.gd")
const MASK := 4294967295
const CAPACITY := 16384


static func u32(value: Variant) -> bool:
	return Numbers.integer_between(value,0,MASK)


static func key(id: int) -> String:
	return "@"+str(id)


static func valid_key(value: Variant) -> bool:
	if not value is String or not value.begins_with("@") or not value.substr(1).is_valid_int(): return false
	var id := int(value.substr(1))
	return u32(id) and key(id)==value


static func initial() -> Dictionary:
	return {"rows":[],"registered":{},"unlocked":{},"propagated":{},"received":{},"first_seen":{},"first_seen_order":[],"timers":{}}


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("capacity")!=CAPACITY or not rules.get("dynamic_claims") is Array or rules["dynamic_claims"].size()!=50: return false
	if rules.get("ordinary_duration")!=-1.0 or rules.get("milliseconds_per_second")!=1000.0: return false
	for row: Variant in rules["dynamic_claims"]:
		if not row is Dictionary or not u32(row.get("id")) or not Numbers.integer_between(row.get("seconds"),-2147483648,2147483647): return false
	if not rules.get("strings") is Dictionary: return false
	for address: String in ["0x104cc9dc","0x104cc9c0"]:
		if not rules["strings"].get(address) is String: return false
	return true


static func valid_rows(rows: Variant) -> bool:
	if not rows is Array or rows.size()>CAPACITY: return false
	var graph := {}
	var indegrees := {}
	var pairs := {}
	for row: Variant in rows:
		if not row is Dictionary: return false
		for field: String in ["unlock","condition","compound","phase"]:
			if not u32(row.get(field)): return false
		var unlock := int(row["unlock"])
		var condition := int(row["condition"])
		if int(row["compound"])!=Hash.pair(condition,unlock): return false
		var pair_ := Vector2i(unlock,condition)
		if pairs.has(pair_): return false
		pairs[pair_]=true
		if int(row["phase"])>2: continue
		if not indegrees.has(condition): indegrees[condition]=0
		indegrees[unlock]=int(indegrees.get(unlock,0))+1
		if not graph.has(condition): graph[condition]=[]
		graph[condition].append(unlock)
	# Source phase-two rows still recurse. Cycles would never terminate in the
	# executable, so unsupported cyclic definitions reject before any claim.
	var pending: Array=[]
	for id: int in indegrees:
		if indegrees[id]==0: pending.append(id)
	var cursor := 0
	while cursor<pending.size():
		var id: int=pending[cursor]
		cursor+=1
		for next: int in graph.get(id,[]):
			indegrees[next]-=1
			if indegrees[next]==0: pending.append(next)
	return cursor==indegrees.size()


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not valid_rows(state.get("rows")): return false
	for name: String in ["registered","unlocked","propagated","received","first_seen","timers"]:
		if not state.get(name) is Dictionary or state[name].size()>CAPACITY: return false
		for id: Variant in state[name]:
			if not valid_key(id): return false
			var value: Variant=state[name][id]
			if name=="first_seen":
				if not u32(value): return false
			elif name=="timers":
				if not valid_time(value): return false
			elif not value is bool or not value: return false
	if state.has("first_seen_order"):
		var order: Variant=state["first_seen_order"]
		if not order is Array or order.size()!=state["first_seen"].size(): return false
		var seen := {}
		for id: Variant in order:
			if not valid_key(id) or seen.has(id) or not state["first_seen"].has(id): return false
			seen[id]=true
	return true


static func valid_time(words: Variant) -> bool:
	return words is Array and words.size()==2 and u32(words[0]) and u32(words[1])


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	if not result.has("first_seen_order"): result["first_seen_order"]=result["first_seen"].keys()
	for row: Dictionary in result["rows"]:
		for field: String in ["unlock","condition","compound","phase"]: row[field]=int(row[field])
	for id: String in result["first_seen"]: result["first_seen"][id]=int(result["first_seen"][id])
	for words: Array in result["timers"].values():
		for i in range(2): words[i]=int(words[i])
	return result


static func insert(set_: Dictionary,id: int) -> void:
	if set_.size()<CAPACITY: set_[key(id)]=true


static func register(state: Dictionary,unlock: int,condition: int,phase: int) -> bool:
	if not valid(state) or not u32(unlock) or not u32(condition) or not u32(phase): return false
	var candidate: Array=state["rows"].duplicate(true)
	var found := false
	for row: Dictionary in candidate:
		if row["unlock"]!=unlock or row["condition"]!=condition: continue
		if row["phase"]==1: row["phase"]=phase
		found=true
		break
	if not found: candidate.append({"unlock":unlock,"condition":condition,"compound":Hash.pair(condition,unlock),"phase":phase})
	if not valid_rows(candidate): return false
	state["rows"]=candidate
	return true


static func prepare(dependencies: Array) -> Dictionary:
	if dependencies.size()>CAPACITY: return {}
	var state := initial()
	var indices := {}
	for row: Variant in dependencies:
		if not row is Dictionary or not u32(row.get("unlock")) or not u32(row.get("condition")) or not u32(row.get("phase")): return {}
		var unlock := int(row["unlock"])
		var condition := int(row["condition"])
		var pair_ := Vector2i(unlock,condition)
		if indices.has(pair_):
			var existing: Dictionary=state["rows"][indices[pair_]]
			if existing["phase"]==1: existing["phase"]=int(row["phase"])
		else:
			indices[pair_]=state["rows"].size()
			state["rows"].append({"unlock":unlock,"condition":condition,"compound":Hash.pair(condition,unlock),"phase":int(row["phase"])})
	if not valid_rows(state["rows"]): return {}
	return state


static func unlocked(state: Dictionary,id: int) -> bool:
	return state["unlocked"].has(key(id))


static func can_unlock(state: Dictionary,id: int) -> bool:
	return state["registered"].has(key(id)) and not unlocked(state,id)


static func propagate_(state: Dictionary,event: int,service: Callable) -> void:
	# Explicit frames retain native depth-first/postorder callbacks without
	# depending on GDScript's call-stack limit for a long authored chain.
	var frames: Array=[[event,0,0]]
	while not frames.is_empty():
		var frame: Array=frames[-1]
		var index := int(frame[1])
		if index>=state["rows"].size(): frames.pop_back(); continue
		var row: Dictionary=state["rows"][index]
		if frame[2]==0 and int(row["phase"]) in [1,2] and row["condition"]==frame[0]:
			row["phase"]=2
			insert(state["propagated"],int(row["unlock"]))
			insert(state["unlocked"],int(row["unlock"]))
			frame[2]=1
			frames.append([int(row["unlock"]),0,0])
			continue
		if frame[2]==1: service.call("notify",[int(row["unlock"])])
		if frame[2]==2:
			service.call("notify",[int(row["condition"])])
		elif int(row["phase"])==0 and row["compound"]==frame[0]:
			row["phase"]=1
			if state["received"].has(key(int(row["condition"]))):
				frame[2]=2
				frames.append([int(row["condition"]),0,0])
				continue
		frame[1]=index+1
		frame[2]=0


static func propagate(state: Dictionary,event: int,service: Callable) -> bool:
	if not valid(state) or not u32(event) or not service.is_valid(): return false
	propagate_(state,event,service)
	return true


static func claim(state: Dictionary,rules: Dictionary,event: int,seconds: int,now: Array,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not u32(event) or not u32(seconds) or not valid_time(now) or not service.is_valid(): return false
	claim_(state,rules,event,seconds,now,service)
	return true


static func claim_(state: Dictionary,rules: Dictionary,event: int,seconds: int,now: Array,service: Callable) -> void:
	if not state.has("first_seen_order"): state["first_seen_order"]=state["first_seen"].keys()
	var duration := float(rules["ordinary_duration"])
	for row: Dictionary in rules["dynamic_claims"]:
		if row["id"]==event: duration=Terrain.f32(float(row["seconds"])); break
	var id := key(event)
	if duration>float(rules["ordinary_duration"]):
		service.call("log",[49,rules["strings"]["0x104cc9c0"],[event]])
		var millis := int(duration)*1000
		var low := int(now[0])+(millis&MASK)
		state["timers"][id]=[low&MASK,(int(now[1])+(millis>>32)+(low>>32))&MASK]
	else:
		if not state["first_seen"].has(id):
			service.call("log",[49,rules["strings"]["0x104cc9dc"],[event]])
			if state["first_seen"].size()<CAPACITY:
				state["first_seen"][id]=seconds
				state["first_seen_order"].append(id)
		insert(state["received"],event)
	propagate_(state,event,service)


static func force_claim_(state: Dictionary,inventory: Dictionary,rules: Dictionary,limits: Dictionary,event: int,seconds: int,now: Array,service: Callable,events: Array,exempt: Array) -> bool:
	# Original 0x1015cd60 rejects the registered-but-not-unlocked case. It does
	# not reject unknown markers or repeat claims. Registration precedes claim;
	# failed final acquisition does not change the wrapper's true result.
	if can_unlock(state,event): return false
	Availability.register(inventory,event,1,1)
	claim_(state,rules,event,seconds,now,service)
	Availability.acquire(inventory,event,1,limits,events,exempt)
	return true


static func valid_rebuild(state: Dictionary) -> bool:
	if not valid(state): return false
	var rows: Array=state["rows"].duplicate(true)
	for row: Dictionary in rows: row["phase"]=1
	return valid_rows(rows)


static func sync_seen(state: Dictionary,cursor: int,heads: Dictionary,next: Dictionary) -> int:
	var order: Array=state["first_seen_order"]
	while cursor<order.size():
		var id: String=order[cursor]
		var bucket := int(id.substr(1))&1023
		next[id]=heads.get(bucket,"")
		heads[bucket]=id
		cursor+=1
	return cursor


static func rebuild_(state: Dictionary,rules: Dictionary,seconds: int,now: Array,service: Callable) -> void:
	# Original 0x1015cdb0: undo effects and restore configuration before clearing
	# the four distinct sets. Persistent timestamps themselves are retained.
	service.call("reset_modifiers",[])
	service.call("reset_configuration",[])
	for name: String in ["registered","unlocked","propagated","received"]: state[name].clear()
	if not state.has("first_seen_order"): state["first_seen_order"]=state["first_seen"].keys()
	var heads := {}
	var next := {}
	var cursor := 0
	for bucket in range(1024):
		cursor=sync_seen(state,cursor,heads,next)
		var id: String=heads.get(bucket,"")
		while not id.is_empty():
			claim_(state,rules,int(id.substr(1)),seconds,now,service)
			cursor=sync_seen(state,cursor,heads,next)
			id=next[id]
	# This reset happens AFTER replay, including for previously inactive rows.
	for row: Dictionary in state["rows"]: row["phase"]=1


static func rebuild(state: Dictionary,rules: Dictionary,seconds: int,now: Array,service: Callable) -> bool:
	if not valid_rebuild(state) or not valid_rules(rules) or not u32(seconds) or not valid_time(now) or not service.is_valid(): return false
	rebuild_(state,rules,seconds,now,service)
	return true


static func next_timer(state: Dictionary,after: int) -> int:
	var result := -1
	for id: String in state["timers"]:
		var value := int(id.substr(1))
		if value>after and (result<0 or value<result): result=value
	return result


static func expire(state: Dictionary,rules: Dictionary,seconds: int,now: Array,force_rebuild: bool,service: Callable) -> bool:
	if not valid_rebuild(state) or not valid_rules(rules) or not u32(seconds) or not valid_time(now) or not service.is_valid(): return false
	var id := next_timer(state,-1)
	var removed := false
	while id>=0:
		var deadline: Array=state["timers"][key(id)]
		if int(deadline[1])<int(now[1]) or (int(deadline[1])==int(now[1]) and int(deadline[0])<=int(now[0])):
			state["timers"].erase(key(id))
			removed=true
			break
		id=next_timer(state,id)
	# The source removes at most one timer per call. Even other already-expired
	# entries are reapplied until the next update removes them in key order.
	if not removed and not force_rebuild: return true
	rebuild_(state,rules,seconds,now,service)
	id=next_timer(state,-1)
	while id>=0:
		propagate_(state,id,service)
		id=next_timer(state,id)
	return true


static func remaining(state: Dictionary,event: int,now: Array,sse2: bool=false) -> int:
	if not valid(state) or not u32(event) or not valid_time(now) or not state["timers"].has(key(event)): return -1
	var deadline: Array=state["timers"][key(event)]
	var low := int(deadline[0])-int(now[0])
	var high := (int(deadline[1])-int(now[1])-(1 if low<0 else 0))&MASK
	# The original query converts the wrapped difference as UNSIGNED 64-bit,
	# divides, truncates to 64 bits, then returns its low signed word. Retain
	# even the expired/wrapped behavior. Word division avoids double rounding.
	var seconds := (((high%1000)*4294967296+(low&MASK))/1000)&MASK
	# MSVCRT's alternate SSE2 conversion returns INT_MIN on 32-bit overflow;
	# its x87 fallback returns the low word of its 64-bit truncation instead.
	# Both modes are explicit, never inferred from a simulation host device.
	if sse2 and high>=500: return -2147483648
	return seconds if seconds<2147483648 else seconds-4294967296
