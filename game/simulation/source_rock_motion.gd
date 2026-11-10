extends RefCounted
## Original rock-only dirty refresh and twelve-slot height motion pool.

const Terrain = preload("res://simulation/source_terrain.gd")
const Rocks = preload("res://simulation/authored_rocks.gd")
const CAPACITY := 12


static func initial() -> Dictionary:
	var slots: Array=[]
	var free: Array=[]
	for index in range(CAPACITY): slots.append({}); free.append(index)
	return {"slots":slots,"free":free,"active":[],"heights":{},"revision":0}


static func request(motion: Dictionary,cell: int,current: float) -> void:
	var slot := -1
	for index: int in motion["active"]:
		if int(motion["slots"][index]["cell"])==cell: slot=index; break
	if slot<0:
		# Native 0x102613b8..0x10261465 reuses slot zero when full. It does
		# not append another motion or change that slot's position in the list.
		if motion["free"].is_empty(): slot=0
		else:
			slot=int(motion["free"].pop_front())
			motion["active"].push_front(slot)
	motion["slots"][slot]={"cell":cell,"start":Terrain.f32(current),"elapsed":0.0}


static func refresh(state: Dictionary,tiles: Dictionary,target: Callable) -> void:
	var motion: Dictionary=state["rock_motion"]
	var sea := float(state["opening"]["definition"]["rock_motion_config"]["sea_height"])
	var ordered: Array=tiles.keys()
	ordered.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y<b.y or a.y==b.y and a.x<b.x)
	var width := int(state["width"])
	for tile: Vector2i in ordered:
		for z in range(tile.y*32,mini(width-1,tile.y*32+32)):
			for x in range(tile.x*32,mini(width-1,tile.x*32+32)):
				var rock := Rocks.at(state,z*width+x)
				if rock.is_empty() or not Rocks.alive(state,int(rock["cell"])): continue
				var cell := int(rock["cell"])
				var height := Terrain.f32(float(motion["heights"].get(str(cell),float(rock["source_y"])+sea)))
				if height!=Terrain.f32(float(target.call(cell))): request(motion,cell,height)


static func release(motion: Dictionary,index: int) -> void:
	motion["active"].erase(index)
	motion["slots"][index]={}
	motion["free"].push_front(index)


static func advance(motion: Dictionary,delta: float,duration: float,target: Callable,alive: Callable) -> void:
	for index: int in motion["active"].duplicate():
		var entry: Dictionary=motion["slots"][index]
		var cell := int(entry["cell"])
		if not alive.call(cell): release(motion,index); continue
		var elapsed := Terrain.f32(float(entry["elapsed"])+Terrain.f32(delta))
		var height := Terrain.f32(float(target.call(cell)))
		entry["elapsed"]=elapsed
		var next := height if elapsed>duration else Terrain.f32(height*elapsed/duration+(1.0-elapsed/duration)*float(entry["start"]))
		if float(motion["heights"].get(str(cell),entry["start"]))!=next: motion["revision"]+=1
		motion["heights"][str(cell)]=next
		if elapsed>duration: release(motion,index)


static func valid_config(config: Variant) -> bool:
	if not config is Dictionary or config.get("capacity")!=CAPACITY: return false
	for key: String in ["duration","sea_height"]:
		var value: Variant=config.get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return false
	return config["duration"]>0 and config["duration"]<=3600 and config["sea_height"]>=0 and config["sea_height"]<=80


static func valid(motion: Variant,rocks: Array,duration: float) -> bool:
	if not motion is Dictionary or not motion.get("slots") is Array or motion["slots"].size()!=CAPACITY or not motion.get("active") is Array or not motion.get("free") is Array or not motion.get("heights") is Dictionary: return false
	if not is_integer(motion.get("revision"),0,9223372036854775807): return false
	var known := {}
	for rock: Dictionary in rocks: known[str(int(rock["cell"]))]=true
	var used := {}
	var cells := {}
	for index: Variant in motion["active"]+motion["free"]:
		if not is_integer(index,0,CAPACITY-1) or used.has(int(index)): return false
		used[int(index)]=true
	if used.size()!=CAPACITY: return false
	var active := {}
	for index: Variant in motion["active"]: active[int(index)]=true
	for index in range(CAPACITY):
		var entry: Variant=motion["slots"][index]
		if not entry is Dictionary: return false
		if not active.has(index):
			if not entry.is_empty(): return false
			continue
		if not is_integer(entry.get("cell"),0,1024*1024-1) or not known.has(str(int(entry["cell"]))) or cells.has(int(entry["cell"])): return false
		cells[int(entry["cell"])]=true
		for key: String in ["start","elapsed"]:
			var value: Variant=entry.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>(duration if key=="elapsed" else 80): return false
	for key: Variant in motion["heights"]:
		if not key is String or not known.has(key): return false
		var value: Variant=motion["heights"][key]
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>80: return false
	return true


static func is_integer(value: Variant,minimum: int,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=minimum and value<=maximum and value==int(value)
