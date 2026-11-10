extends RefCounted
## Deterministic observer/player for the authored opening. Emits ordinary commands;
## hypothetical route planning cannot edit terrain, move followers or advance story.

const DIRECTIONS := [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]
var last_sculpt_tick := -100
var camera_center := Vector2.INF
var planned_edits := 0
var diagnostic := ""
var serial := 0


func commands(world: RefCounted) -> Array:
	var state: Dictionary = world.snapshot(false)
	if not state.has("opening"): return []
	var opening: Dictionary = state["opening"]
	if not opening["error"].is_empty(): diagnostic=opening["error"]; return []
	var output: Array = []
	var center := Vector2.ZERO
	for follower: Dictionary in state["followers"]: center+=Vector2(follower["x"],follower["z"])
	center/=maxi(1,state["followers"].size())
	if camera_center==Vector2.INF or not opening["camera_locked"] and center.distance_to(camera_center)>5:
		camera_center=center
		output.append({"type":"campaign_view","projection":[1.0/32,0,0,0.5-center.x/32,0,1.0/32,0,0.5-center.y/32],"ended":true})
	for message: Dictionary in opening["messages"]:
		if message["callback"]!=null or int(message["id"])==4: output.append({"type":"campaign_ack","id":int(message["id"])})
	if opening["phase"]=="rescue":
		var rescue := {"type":"sculpt_drag","x":166,"z":58,"nx":0,"nz":-1,"layer":1,"distance":5,"dx":-3,"dz":-5,"radius":1}
		if world.inspect(rescue)["ok"]: output.append(rescue)
	elif opening["phase"]=="promised_land" and int(opening.get("promised_step",-1))==1:
		var cell := int(opening["activity_exception"])-preload("res://simulation/campaign_opening.gd").ROCK_ID_BASE
		var tap := {"type":"tap_object","cell":cell}
		if world.inspect(tap)["ok"]: output.append(tap)
	elif opening["phase"]=="trail" and not opening["movement_paused"] and int(state["tick"])-last_sculpt_tick>=10:
		var entry: Dictionary = opening["entries"][int(opening["checkpoint"])]
		var target := Vector2(entry["Target"]["x"],entry["Target"]["y"])
		var leader: Dictionary = state["followers"][0]
		for follower: Dictionary in state["followers"]:
			if Vector2(follower["x"],follower["z"]).distance_squared_to(target)<=Vector2(leader["x"],leader["z"]).distance_squared_to(target): leader=follower
		if leader["state"]=="waiting":
			var start := Vector2i(roundi(leader["x"]),roundi(leader["z"]))
			var destination := Vector2i(roundi(target.x),roundi(target.y))
			var path := sculpt_route(world,state,start,destination,8)
			if path.is_empty(): path=sculpt_route(world,state,start,destination,16)
			var gesture := route_gesture(world,path)
			if not gesture.is_empty():
				output.append(gesture)
				last_sculpt_tick=int(state["tick"])
				planned_edits+=1
			else: diagnostic="No legal terrain gesture for checkpoint %d from %s to %s (%d planned cells)."%[opening["checkpoint"],start,destination,path.size()]
	return output


func sculpt_route(world: RefCounted,state: Dictionary,start: Vector2i,target: Vector2i,margin: int) -> Array:
	var bounds := Rect2i(start.min(target)-Vector2i.ONE*margin,(start-target).abs()+Vector2i.ONE*(margin*2+1))
	var first := Vector3i(start.x,start.y,world.height_at(start.x,start.y))
	if first.z<=0: return []
	var heap: Array = []
	push(heap,[0.0,0,first])
	var previous := {first:first}
	var costs := {first:0.0}
	var closed := {}
	var cursor := 0
	while not heap.is_empty() and cursor<15000:
		var current: Vector3i = pop(heap)[2]
		if closed.has(current): continue
		closed[current]=true
		cursor+=1
		if Vector2i(current.x,current.y)==target:
			var path: Array = []
			while current!=first:
				path.push_front(current)
				current=previous[current]
			return path
		for direction: Vector2i in DIRECTIONS:
			var cell := Vector2i(current.x,current.y)+direction
			if not bounds.has_point(cell) or cell.x<1 or cell.y<1 or cell.x>=int(state["width"])-1 or cell.y>=int(state["width"])-1: continue
			var actual: int = world.height_at(cell.x,cell.y)
			var minimum := maxi(1,current.z-1)
			var maximum := mini(63,current.z+1)
			for height in range(minimum,maximum+1):
				if actual!=height and not editable(world,state,cell,actual,height): continue
				var next := Vector3i(cell.x,cell.y,height)
				var cost: float = costs[current]+1+absi(actual-height)*6
				if cost>=float(costs.get(next,INF)): continue
				costs[next]=cost
				previous[next]=current
				serial+=1
				push(heap,[cost+absi(cell.x-target.x)+absi(cell.y-target.y),serial,next])
	return []


func editable(world: RefCounted,state: Dictionary,cell: Vector2i,actual: int,height: int) -> bool:
	if not world.can_act_at(cell.x,cell.y): return false
	var opening: Dictionary = state["opening"]
	var band: Dictionary = opening["definition"]["coastal_free_band"]
	var index := cell.y*int(state["width"])+cell.x
	var raw: int = 19+actual if actual>0 else int(opening["submerged_levels"].get(str(index),opening["definition"]["raw_floor"][index]))
	return mini(raw,19+height)>=int(band["min"]) and maxi(raw,19+height)<=int(band["max"])


func route_gesture(world: RefCounted,path: Array) -> Dictionary:
	for cell: Vector3i in path:
		var actual: int = world.height_at(cell.x,cell.y)
		if actual==cell.z: continue
		for direction: Vector2i in DIRECTIONS:
			var neighbor := Vector2i(cell.x,cell.y)+direction
			var command: Dictionary
			if cell.z>actual and world.height_at(neighbor.x,neighbor.y)>=cell.z:
				command={"type":"sculpt_drag","x":neighbor.x,"z":neighbor.y,"nx":-direction.x,"nz":-direction.y,"layer":cell.z,"distance":1,"radius":0}
			elif cell.z<actual and world.height_at(neighbor.x,neighbor.y)<=cell.z:
				command={"type":"sculpt_drag","x":cell.x,"z":cell.y,"nx":direction.x,"nz":direction.y,"layer":cell.z+1,"distance":-1,"radius":0}
			else: continue
			if world.inspect(command)["ok"]: return command
	return {}


func push(heap: Array,item: Array) -> void:
	heap.append(item)
	var index := heap.size()-1
	while index>0:
		var parent := (index-1)/2
		if not before(heap[index],heap[parent]): break
		var swap: Array = heap[index]; heap[index]=heap[parent]; heap[parent]=swap
		index=parent


func pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return result
	heap[0]=last
	var index := 0
	while index*2+1<heap.size():
		var child := index*2+1
		if child+1<heap.size() and before(heap[child+1],heap[child]): child+=1
		if not before(heap[child],heap[index]): break
		var swap: Array = heap[index]; heap[index]=heap[child]; heap[child]=swap
		index=child
	return result


func before(a: Array,b: Array) -> bool:
	return a[0]<b[0] or a[0]==b[0] and a[1]<b[1]
