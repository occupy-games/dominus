extends RefCounted
## Original 0x1025e210 / 0x1025e5e0 flat, clear square capacity.
## A plot occupies quads: size N needs (N+1)^2 equal dry vertices.
## Claims, influence, biome eligibility and native allocation order are separate.

const MAX_SIZE := 16
const MAX_PLOTS := 1024


static func map_byte_allows(value: int) -> bool:
	return value<=64 or value>=128


static func capacity(terrain: PackedByteArray,width: int,x: int,z: int,obstructed: Callable,limit: int=MAX_SIZE) -> int:
	if width<=1 or terrain.size()!=width*width or x<0 or z<0 or x>=width-1 or z>=width-1: return 0
	var height := terrain[z*width+x]
	if height<=0: return 0
	var maximum := mini(clampi(limit,0,MAX_SIZE),mini(width-1-x,width-1-z))
	# Incremental perimeter scans avoid rescanning the interior. Native masks
	# erode the same flat/clear quads and stop at the original size cap.
	for size in range(1,maximum+1):
		for offset in range(size+1):
			if terrain[(z+size)*width+x+offset]!=height or terrain[(z+offset)*width+x+size]!=height: return size-1
		for offset in range(size):
			if obstructed.call(x+offset,z+size-1) or obstructed.call(x+size-1,z+offset): return size-1
	return maximum


static func intersects_query(origin: Vector2,size: int,center: Vector2,radius: float) -> bool:
	# Native plot registration uses its half-size as spatial radius. The Lua
	# GetFirstPlotInRadius wrapper requests that object radii participate.
	if size<=0 or radius<0: return false
	var half := float(size)*0.5
	return (origin+Vector2(half,half)).distance_to(center)<=radius+half


static func new_region(tile: Vector2i,width: int,sizes: Array,loaded: Callable,clear_capacity: Callable,location: Callable,eligible: Callable,occupied: Dictionary={},available: int=MAX_PLOTS) -> Array:
	# Original 0x102397f5 fresh-allocation phase for one dirty region. Its caller
	# owns existing-plot resizing/claims and provides authoritative cell gates.
	# Bounds overlap adjacent tiles by 32 cells, exactly as in the native scan.
	var result: Array=[]
	if width<=0 or sizes.size()!=3 or available<=0: return result
	var largest := 0
	var smallest := MAX_SIZE+1
	for limits: Array in sizes:
		if limits.size()!=2: return []
		if int(limits[1])>0:
			largest=maxi(largest,int(limits[1]))
			smallest=mini(smallest,int(limits[0]))
	if smallest<=0 or largest>MAX_SIZE or smallest>largest: return result
	var reserved := occupied.duplicate(false)
	var origins: Array[Vector3i]=[]
	for z in range(maxi(0,tile.y*32-32),mini(width,tile.y*32+32)):
		for x in range(maxi(0,tile.x*32-32),mini(width,tile.x*32+32)):
			if reserved.has(z*width+x) or not loaded.call(x,z): continue
			var capacity := int(clear_capacity.call(x,z))
			if capacity>=smallest and eligible.call(x,z): origins.append(Vector3i(x,z,capacity))
	# Terrain, loading and influence stay fixed during allocation. Reservations
	# change as plots are assigned, so the size and footprint passes keep their
	# original order and recheck occupancy against the current reservations.
	for size: int in range(largest,smallest-1,-1):
		var half: int=size/2
		for origin: Vector3i in origins:
			var x:=origin.x
			var z:=origin.y
			if origin.z<size or reserved.has(z*width+x): continue
			var band := int(location.call(x+half,z+half))
			if band<0 or band>=sizes.size() or size<int(sizes[band][0]) or size>int(sizes[band][1]): continue
			var valid := true
			for dz in range(size):
				for dx in range(size):
					var cell := (z+dz)*width+x+dx
					if reserved.has(cell) or not eligible.call(x+dx,z+dz): valid=false; break
				if not valid: break
			if not valid: continue
			result.append({"id":result.size(),"x":x,"z":z,"size":size})
			for dz in range(size):
				for dx in range(size): reserved[(z+dz)*width+x+dx]=true
			if result.size()==mini(MAX_PLOTS,available): return result
	return result
