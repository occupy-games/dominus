extends RefCounted
## Original 0x100441c0/0x10044250 intrusive house-pool order, as plain data.
## Capacity is injected; it is not inferred from these controlled comparisons.

const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func initial(capacity: int) -> Dictionary:
	if capacity<1 or capacity>65535: return {}
	var free: Array=[]
	for id in range(capacity): free.append(id)
	return {"capacity":capacity,"active":[],"free":free,"slots":{}}


static func allocate(pool: Dictionary) -> int:
	if pool["free"].is_empty(): return -1
	var id := int(pool["free"].pop_front())
	pool["active"].push_front(id)
	# The native allocator changes links only. In particular it does not clear
	# the old type/owner before the factory's matching-house rotation scan.
	return id


static func release(pool: Dictionary,id: int) -> int:
	var index: int=pool["active"].find(id)
	if index<0: return -1
	var following := int(pool["active"][index+1]) if index+1<pool["active"].size() else -1
	pool["active"].remove_at(index)
	pool["free"].push_front(id)
	return following


static func snapshot(pool: Dictionary) -> Dictionary:
	return {"count":pool["active"].size(),"active":pool["active"].duplicate(),"free":pool["free"].duplicate()}


static func valid(pool: Variant) -> bool:
	if not pool is Dictionary or not Schedule.integer_between(pool.get("capacity"),1,65535) or not pool.get("active") is Array or not pool.get("free") is Array or not pool.get("slots") is Dictionary: return false
	if pool["active"].size()+pool["free"].size()!=int(pool["capacity"]): return false
	var seen := {}
	for list: Array in [pool["active"],pool["free"]]:
		for value: Variant in list:
			if not Schedule.integer_between(value,0,int(pool["capacity"])-1) or seen.has(int(value)): return false
			seen[int(value)]=true
	for key: Variant in pool["slots"]:
		if not key is String or not key.is_valid_int() or key!=str(int(key)) or not Schedule.integer_between(int(key),0,int(pool["capacity"])-1) or not pool["slots"][key] is Dictionary: return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var pool: Dictionary=saved.duplicate(true)
	pool["capacity"]=int(pool["capacity"])
	for key: String in ["active","free"]:
		for i in range(pool[key].size()): pool[key][i]=int(pool[key][i])
	return pool
