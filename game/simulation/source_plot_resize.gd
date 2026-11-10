extends RefCounted
## Native one-iteration plot layout choices. Registry/revisit ordering is separate.

const Existing = preload("res://simulation/source_existing_plots.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	if rules.has("progress_rate") and (not (rules["progress_rate"] is int or rules["progress_rate"] is float) or not is_finite(float(rules["progress_rate"])) or float(rules["progress_rate"])<=0): return false
	for key: String in ["growth","repair"]:
		var data: Variant=rules.get(key)
		if not (data is Array or data is PackedByteArray) or data.size()!=(768 if key=="growth" else 4096): return false
		for value: Variant in data:
			if not (value is int or value is float) or not is_finite(float(value)) or value!=int(value) or value<0 or value>63 or (int(value)&3)==3 or ((int(value)>>2)&3)==3 or (key=="growth" and int(value)>>4>2): return false
	return true


static func action(rules: Dictionary,kind: String,flags: Array,size: int,maximum: int) -> Dictionary:
	var index := 0
	for i in range(flags.size()):
		if flags[i]: index|=1<<i
	if kind=="growth": index+=256*clampi(maximum-size,0,2)
	var encoded := int(rules[kind][index])
	var mode := encoded>>4
	return {"dx":(encoded&3)-1,"dz":((encoded>>2)&3)-1,
		"delta":mode if kind=="growth" else [-2,-1,0,0][mode],"remove":kind=="repair" and mode==3}


static func owner_allows(plot: Dictionary,owner: Dictionary,special_id: int,include_empty: bool) -> bool:
	if owner.is_empty(): return include_empty or special_id!=-1
	if int(owner["id"])==special_id or owner["claimed"]: return false
	return int(owner["id"])==int(plot["id"]) or int(owner["size"])<int(plot["size"]) or int(plot["id"])==special_id


static func expansion_cell(plot: Dictionary,x: int,z: int,cell_at: Callable,special_id: int) -> bool:
	if x<0 or z<0 or x>=1024 or z>=1024: return false
	var cell: Dictionary=cell_at.call(x,z)
	if not Existing.cell_valid(plot,cell): return false
	var owner: Dictionary=cell["owner"]
	# Outer strips accept equal-size unclaimed neighbors; inner repair checks
	# require a strictly smaller neighbor unless it is this plot itself.
	if owner.is_empty(): return true
	return int(owner["id"])!=special_id and not owner["claimed"] and (int(owner["size"])<=int(plot["size"]) or int(plot["id"])==special_id)


static func expansion_flags(plot: Dictionary,cell_at: Callable,special_id: int=-1) -> Array:
	var x := int(Terrain.f32(float(plot["x"])))
	var z := int(Terrain.f32(float(plot["z"])))
	var size := int(plot["size"])
	var result: Array=[true,true,true,true]
	for offset in range(size):
		var points := [Vector2i(x-1,z+offset),Vector2i(x+size,z+offset),Vector2i(x+offset,z+size),Vector2i(x+offset,z-1)]
		for side in range(4):
			if result[side] and not expansion_cell(plot,points[side].x,points[side].y,cell_at,special_id): result[side]=false
	for point: Vector2i in [Vector2i(x-1,z+size),Vector2i(x+size,z+size),Vector2i(x-1,z-1),Vector2i(x+size,z-1)]:
		result.append(expansion_cell(plot,point.x,point.y,cell_at,special_id))
	return result


static func repair_flags(plot: Dictionary,cell_at: Callable,special_id: int=-1) -> Array:
	var x := int(Terrain.f32(float(plot["x"])))
	var z := int(Terrain.f32(float(plot["z"])))
	var size := int(plot["size"])
	var edges: Array=[true,true,true,true]
	var offset := 1
	while offset<size-1:
		var points := [Vector2i(x+offset,z+size-1),Vector2i(x+offset,z),Vector2i(x,z+offset),Vector2i(x+size-1,z+offset)]
		for side in range(4):
			var cell: Dictionary=cell_at.call(points[side].x,points[side].y)
			if not cell["flat"] or not owner_allows(plot,cell["owner"],special_id,false): edges[side]=false
		offset+=1
	for point: Vector2i in [Vector2i(x,z+size-1),Vector2i(x+size-1,z+size-1),Vector2i(x,z),Vector2i(x+size-1,z)]:
		var cell: Dictionary=cell_at.call(point.x,point.y)
		edges.append(cell["flat"] and owner_allows(plot,cell["owner"],special_id,false))
	var outer := expansion_flags(plot,cell_at,special_id)
	for side in range(4): edges.append(outer[side])
	return edges


static func layout_step(plot: Dictionary,cell_at: Callable,rules: Dictionary,minimum: int,maximum: int,special_id: int=-1) -> Dictionary:
	var next := plot.duplicate(true)
	var choice: Dictionary
	if Existing.owned_footprint_valid(plot,cell_at):
		if plot["claimed"]: return next
		choice=action(rules,"growth",expansion_flags(plot,cell_at,special_id),int(plot["size"]),maximum)
	elif not Existing.owned_footprint_valid(plot,cell_at,true):
		next["size"]=0
		return next
	else:
		choice=action(rules,"repair",repair_flags(plot,cell_at,special_id),int(plot["size"]),maximum)
	next["x"]=Terrain.f32(float(plot["x"])+float(choice["dx"]))
	next["z"]=Terrain.f32(float(plot["z"])+float(choice["dz"]))
	next["size"]=0 if choice["remove"] else int(plot["size"])+int(choice["delta"])
	if int(next["size"])<minimum:
		next["size"]=0
		# Native 0x10239792 restores its stored integer origin when a repaired
		# plot falls below the current available minimum size.
		next["x"]=float(plot["stored_x"])
		next["z"]=float(plot["stored_z"])
	if layout_changed(plot,next): next["claimed"]=false
	return next


static func layout_changed(plot: Dictionary,layout: Dictionary) -> bool:
	return int(plot["size"])!=int(layout["size"]) or float(plot["x"])!=float(layout["x"]) or float(plot["z"])!=float(layout["z"])


static func apply_layout(plots: Array,owners: Dictionary,index: int,layout: Dictionary) -> void:
	var id := int(plots[index]["id"])
	# Native unregister removes only cells still owned by this identity, so a
	# neighboring plot's existing ownership survives a shrink or destruction.
	for cell: int in owners.keys():
		if int(owners[cell]["id"])==id: owners.erase(cell)
	plots[index]=layout
	for z in range(int(float(layout["z"])),int(float(layout["z"]))+int(layout["size"])):
		for x in range(int(float(layout["x"])),int(float(layout["x"]))+int(layout["size"])): owners[z*1024+x]=layout


static func neighbor_lists(plot: Dictionary,cell_at: Callable,special_id: int=-1) -> Array:
	var lists: Array=[[],[],[],[],[],[],[],[]]
	var x := int(float(plot["x"]))
	var z := int(float(plot["z"]))
	var size := int(plot["size"])
	for side in range(4):
		var offset := 0
		while offset<size:
			var point: Vector2i=[Vector2i(x-1,z+offset),Vector2i(x+size,z+offset),Vector2i(x+offset,z+size),Vector2i(x+offset,z-1)][side]
			var owner: Dictionary=cell_at.call(point.x,point.y)["owner"] if point.x>=0 and point.y>=0 and point.x<1024 and point.y<1024 else {}
			if not owner.is_empty() and int(owner["id"])!=special_id and not owner["claimed"] and (int(owner["size"])<=size or int(plot["id"])==special_id):
				lists[side].append(int(owner["id"]))
				offset+=int(owner["size"])
			offset+=1
	var corners := [Vector2i(x-1,z+size),Vector2i(x+size,z+size),Vector2i(x-1,z-1),Vector2i(x+size,z-1)]
	for i in range(4):
		var point: Vector2i=corners[i]
		if point.x<0 or point.y<0 or point.x>=1024 or point.y>=1024: continue
		var owner: Dictionary=cell_at.call(point.x,point.y)["owner"]
		if owner.is_empty() or owner["claimed"] or int(owner["id"])==special_id: continue
		var horizontal := int(float(owner["x"]))+int(owner["size"])==x if i in [0,2] else int(float(owner["x"]))==x+size
		var vertical := int(float(owner["z"]))==z+size if i in [0,1] else int(float(owner["z"]))+int(owner["size"])==z
		if horizontal and vertical: lists[i+4].append(int(owner["id"]))
	return lists


static func revisit(plot: Dictionary,layout: Dictionary,cell_at: Callable,pending: Array,special_id: int=-1) -> Array:
	var queue: Array=pending.map(func(id: Variant) -> int: return int(id))
	if int(layout["size"])<=0 or not layout_changed(plot,layout): return queue
	var dx := int(float(layout["x"])-float(plot["x"]))
	var dz := int(float(layout["z"])-float(plot["z"]))
	var delta := int(layout["size"])-int(plot["size"])
	var order: Array=[]
	if delta==2: order=[0,4,2,5,1,7,3,6]
	elif delta==1:
		if dx==-1 and dz==0: order=[0,2,4]
		elif dx==0 and dz==0: order=[2,5,1]
		elif dx==0 and dz==-1: order=[1,7,3]
		else: order=[3,6,0]
	elif delta==0:
		if dx==-1: order=[0]
		elif dx==1: order=[1]
		elif dz==1: order=[2]
		elif dz==-1: order=[3]
	var lists := neighbor_lists(plot,cell_at,special_id)
	for side: int in order:
		for id: int in lists[side]:
			if not queue.has(id): queue.append(id)
	queue.append(int(plot["id"]))
	return queue
