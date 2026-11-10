extends RefCounted
## Original 32x32 dirty-region mask, availability invalidation and scan order.
## Region geometry is an injected pure simulation operation.


static func initial() -> Dictionary:
	return {"limits":{},"dirty":{}}


static func mark(state: Dictionary,x: int,z: int) -> void:
	if x<0 or z<0 or x>=1024 or z>=1024: return
	var tile := Vector2i(x/32,z/32)
	for row in range(maxi(0,tile.y-1),mini(32,tile.y+2)):
		for column in range(maxi(0,tile.x-1),mini(32,tile.x+2)): state["dirty"][str(row*32+column)]=true


static func same_limits(previous: Dictionary,current: Dictionary) -> bool:
	if previous.is_empty(): return false
	for field: String in ["minimum","maximum","biomes"]:
		if int(previous[field])!=int(current[field]): return false
	for band in range(3):
		for bound in range(2):
			if int(previous["sizes"][band][bound])!=int(current["sizes"][band][bound]): return false
	return true


static func dispatch(state: Dictionary,limits: Dictionary,region: Callable) -> void:
	if not same_limits(state["limits"],limits):
		state["limits"]=limits.duplicate(true)
		for index in range(1024): state["dirty"][str(index)]=true
	# Iterate the native mask in row order, rather than dictionary insertion
	# order. A region can mark later regions during this same pass.
	for index in range(1024):
		var key := str(index)
		if not state["dirty"].has(key): continue
		region.call(Vector2i(index%32,index/32))
		state["dirty"].erase(key)


static func integer_between(value: Variant,minimum: int,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==int(value) and value>=minimum and value<=maximum


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not state.get("limits") is Dictionary or not state.get("dirty") is Dictionary: return false
	for key: Variant in state["dirty"]:
		if not key is String or not key.is_valid_int() or str(int(key))!=key or not integer_between(int(key),0,1023) or not state["dirty"][key] is bool or not state["dirty"][key]: return false
	var limits: Dictionary=state["limits"]
	if limits.is_empty(): return true
	if not integer_between(limits.get("minimum"),1,10000) or not integer_between(limits.get("maximum"),0,16) or not integer_between(limits.get("biomes"),0,15): return false
	if not limits.get("sizes") is Array or limits["sizes"].size()!=3: return false
	for bounds: Variant in limits["sizes"]:
		if not bounds is Array or bounds.size()!=2 or not integer_between(bounds[0],1,10000) or not integer_between(bounds[1],0,16): return false
		if int(bounds[1])>0 and int(bounds[0])>int(bounds[1]): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var state: Dictionary=saved.duplicate(true)
	if not state["limits"].is_empty():
		for field: String in ["minimum","maximum","biomes"]: state["limits"][field]=int(state["limits"][field])
		for bounds: Array in state["limits"]["sizes"]:
			for index in range(2): bounds[index]=int(bounds[index])
	return state
