extends RefCounted
## Source region maintenance, LIFO revisits, new allocation and plot-slot lifetime.
## Terrain/AOI/biome fields are injected by authoritative simulation adapters.

const Resize = preload("res://simulation/source_plot_resize.gd")
const Plots = preload("res://simulation/source_plots.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const CAPACITY := 1024


static func initial() -> Dictionary:
	var slots: Array=[]
	var free: Array=[]
	for id in range(CAPACITY): slots.append({}); free.append(id)
	return {"slots":slots,"active":[],"free":free,"owners":{},"schedule":Schedule.initial()}


static func allocate(state: Dictionary,x: float,z: float,size: int,height: float) -> int:
	if state["free"].is_empty(): return -1
	var id := int(state["free"].pop_front())
	var plot := {"id":id,"x":Terrain.f32(x),"z":Terrain.f32(z),"size":size,"height":Terrain.f32(height),"claimed":false,
		"stored_size":0,"stored_x":int(x),"stored_z":int(z),"progress":0.0}
	state["slots"][id]=plot
	state["active"].push_front(id)
	register(state,plot)
	return id


static func register(state: Dictionary,plot: Dictionary) -> void:
	for z in range(int(float(plot["z"])),int(float(plot["z"]))+int(plot["size"])):
		for x in range(int(float(plot["x"])),int(float(plot["x"]))+int(plot["size"])): state["owners"][str(z*1024+x)]=int(plot["id"])


static func unregister(state: Dictionary,plot: Dictionary) -> void:
	for z in range(int(float(plot["z"])),int(float(plot["z"]))+int(plot["size"])):
		for x in range(int(float(plot["x"])),int(float(plot["x"]))+int(plot["size"])):
			var key := str(z*1024+x)
			if state["owners"].has(key) and int(state["owners"][key])==int(plot["id"]): state["owners"].erase(key)


static func cell(state: Dictionary,fields: Callable,x: int,z: int) -> Dictionary:
	var result: Dictionary=fields.call(x,z).duplicate(false)
	var owner := int(state["owners"].get(str(z*1024+x),-1))
	result["owner"]={} if owner<0 else state["slots"][owner]
	return result


static func clear_capacity(fields: Callable,x: int,z: int,limit: int=Plots.MAX_SIZE) -> int:
	for size in range(1,limit+1):
		for offset in range(size):
			for point: Vector2i in [Vector2i(x+offset,z+size-1),Vector2i(x+size-1,z+offset)]:
				if point.x<0 or point.y<0 or point.x>=1023 or point.y>=1023: return size-1
				var data: Dictionary=fields.call(point.x,point.y)
				if not data["flat"] or data["scenery"] or data["blocked"]: return size-1
	return limit


static func region(state: Dictionary,tile: Vector2i,rules: Dictionary,sizes: Array,fields: Callable,loaded: Callable,band: Callable,height: Callable,special_id: int=-1,eligibility: Callable=Callable(),fresh_allowed: bool=true,capacity: Callable=Callable()) -> void:
	var pending: Array=[]
	for id: int in state["active"]:
		var plot: Dictionary=state["slots"][id]
		if int(plot["size"])>0 and float(plot["x"])>tile.x*32-32 and float(plot["x"])<tile.x*32+32 and float(plot["z"])>tile.y*32-32 and float(plot["z"])<tile.y*32+32: pending.append(id)
	var cell_at := func(x: int,z: int) -> Dictionary: return cell(state,fields,x,z)
	while not pending.is_empty():
		var id := int(pending.pop_back())
		var plot: Dictionary=state["slots"][id]
		var root := Vector2i(int(float(plot["x"])),int(float(plot["z"])))
		var data: Dictionary=fields.call(root.x,root.y)
		var evaluated := plot.duplicate(false)
		evaluated["origin_byte"]=int(data["map_byte"])
		evaluated["biome_allowed"]=data["biome_allowed"]
		var location := int(band.call(root.x,root.y))
		var next := Resize.layout_step(evaluated,cell_at,rules,int(sizes[location][0]),int(sizes[location][1]),special_id)
		pending=Resize.revisit(plot,next,cell_at,pending,special_id)
		if Resize.layout_changed(plot,next):
			unregister(state,plot)
			next.erase("origin_byte")
			next.erase("biome_allowed")
			next["progress"]=0.0
			state["slots"][id]=next
			register(state,next)
	# A caller can prove the entire fresh-origin window ineligible from its
	# authoritative field tiles. Existing plots still receive maintenance.
	if not fresh_allowed: return
	var occupied := {}
	for key: String in state["owners"]: occupied[int(key)]=true
	if not capacity.is_valid():
		var largest := 0
		for bounds: Array in sizes: largest=maxi(largest,int(bounds[1]))
		capacity=func(x: int,z: int) -> int: return clear_capacity(fields,x,z,largest)
	var eligible := eligibility if eligibility.is_valid() else func(x: int,z: int) -> bool: return fields.call(x,z)["eligible"]
	var fresh := Plots.new_region(tile,1024,sizes,loaded,capacity,band,eligible,occupied,state["free"].size())
	for plot: Dictionary in fresh: allocate(state,float(plot["x"]),float(plot["z"]),int(plot["size"]),float(height.call(plot["x"],plot["z"])))


static func maintain(state: Dictionary,rules: Dictionary,limits: Dictionary,fields: Callable,loaded: Callable,band: Callable,height: Callable,special_id: int=-1,eligibility: Callable=Callable(),fresh_region: Callable=Callable(),capacity: Callable=Callable()) -> void:
	Schedule.dispatch(state["schedule"],limits,func(tile: Vector2i) -> void:
		region(state,tile,rules,limits["sizes"],fields,loaded,band,height,special_id,eligibility,bool(fresh_region.call(tile)) if fresh_region.is_valid() else true,capacity))


static func advance(state: Dictionary,delta: float,rate: float) -> void:
	for id: int in state["active"].duplicate():
		var plot: Dictionary=state["slots"][id]
		if float(plot["progress"])<1.0:
			plot["progress"]=minf(1.0,Terrain.f32(float(plot["progress"])+Terrain.f32(delta)*rate))
		elif int(plot["size"])==0:
			state["active"].erase(id)
			state["slots"][id]={}
			state["free"].push_front(id)
		else:
			plot["stored_size"]=int(plot["size"])
			plot["stored_x"]=int(float(plot["x"]))
			plot["stored_z"]=int(float(plot["z"]))


static func snapshot(state: Dictionary) -> Dictionary:
	var result := {"plots":[],"free":state["free"].duplicate(),"owners":state["owners"].duplicate()}
	for id: int in state["active"]:
		var plot: Dictionary=state["slots"][id].duplicate(true)
		plot.erase("origin_byte")
		plot.erase("biome_allowed")
		result["plots"].append(plot)
	return result


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not state.get("slots") is Array or state["slots"].size()!=CAPACITY: return false
	if not state.get("active") is Array or not state.get("free") is Array or not state.get("owners") is Dictionary or not Schedule.valid(state.get("schedule")): return false
	if state["active"].size()+state["free"].size()!=CAPACITY: return false
	var identities := {}
	for list: String in ["active","free"]:
		for value: Variant in state[list]:
			if not Schedule.integer_between(value,0,CAPACITY-1) or identities.has(int(value)): return false
			identities[int(value)]=true
			var plot: Variant=state["slots"][int(value)]
			if not plot is Dictionary: return false
			if list=="free":
				if not plot.is_empty(): return false
				continue
			if not Schedule.integer_between(plot.get("id"),int(value),int(value)) or not plot.get("claimed") is bool: return false
			for field: String in ["size","stored_size","stored_x","stored_z"]:
				if not Schedule.integer_between(plot.get(field),0,16 if field in ["size","stored_size"] else 1023): return false
			for field: String in ["x","z","height","progress"]:
				var number: Variant=plot.get(field)
				if not (number is int or number is float) or not is_finite(float(number)) or Terrain.f32(float(number))!=float(number): return false
			if float(plot["progress"])<0 or float(plot["progress"])>1 or float(plot["height"])<0: return false
			for axis: String in ["x","z"]:
				if not Schedule.integer_between(plot[axis],0,1023) or int(plot[axis])+int(plot["size"])>1024: return false
	var owners := {}
	for value: Variant in state["active"]:
		var plot: Dictionary=state["slots"][int(value)]
		for z in range(int(plot["z"]),int(plot["z"])+int(plot["size"])):
			for x in range(int(plot["x"]),int(plot["x"])+int(plot["size"])):
				var key := str(z*1024+x)
				if owners.has(key): return false
				owners[key]=int(value)
	if owners.size()!=state["owners"].size(): return false
	for key: String in owners:
		if not state["owners"].has(key) or not Schedule.integer_between(state["owners"][key],int(owners[key]),int(owners[key])): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var state: Dictionary=saved.duplicate(true)
	state["schedule"]=Schedule.restore(saved["schedule"])
	# Integer JSON tokens are decoded as doubles by Godot. Normalize identities
	# before Array.erase/has and free-list reuse, which use exact variant types.
	for list: String in ["active","free"]: state[list]=state[list].map(func(id: Variant) -> int: return int(id))
	for id: int in state["active"]:
		for field: String in ["id","size","stored_size","stored_x","stored_z"]: state["slots"][id][field]=int(state["slots"][id][field])
	for key: String in state["owners"]: state["owners"][key]=int(state["owners"][key])
	return state
