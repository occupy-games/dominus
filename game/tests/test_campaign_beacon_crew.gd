extends SceneTree

const World = preload("res://simulation/world.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Footprint = preload("res://simulation/source_temple_footprint.gd")
const STAGING := Vector2i(169,251)
const APPROACH := Vector2i(132,319)
var failures := 0


func _initialize() -> void:
	create_timer(100).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(not content.is_empty(),"Load the authored Homeworld6 terrain and sites")
	if failures: finish(); return
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed=1017
	world.initialize({"campaign_data":content},rng)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"leash_step":2,"events_step":1,"messages":[]},true)
	opening["leash_level_card"]=content["story"]["leash_population_card"]["id"]
	opening["globals"]["onStartPlayTriggered"]=true
	state["belief"]=100000
	state["progression"]["script_unlocks"]={"Leash":true,"OreSpending":true,"Expansion_2_Ravine":true,"Expansion_3a":true,"Expansion_3b":true}
	for tick in range(80): world._advance_source_influence([])
	check_beacon(world)
	if not failures: check_coastal_beacon(world)
	if not failures: check_ark(world)
	finish()


func check_beacon(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var site: Dictionary=world.source_shrine_site("1017")
	var anchor := Vector2i(site["x"],site["z"])
	var clear := {"type":"tap_object","cell":anchor.y*int(state["width"])+anchor.x}
	for tap in range(4):
		if world.source_shrine_clear(site) or not world.inspect(clear)["ok"]: break
		world.step([clear])
	check(world.source_shrine_clear(site),"Clear the original rock from beacon 1017 through the tap command")
	if failures: return
	var player := Player.new()
	var anchor_height: int=world.height_at(anchor.x,anchor.y)
	check(not player.editable(world,state,anchor,anchor_height,anchor_height-1),"Self-play must respect the shrine's existing foundation")
	check(world.source_shrine_repair_plan(site,STAGING).is_empty(),"The original terrain must first need a connection")
	var route := player.sculpt_route(world,state,STAGING,APPROACH,16,world.height_at(APPROACH.x,APPROACH.y))
	check(route.size()>100,"Find the long route across the original expanded territory within the search budget")
	var cells := {STAGING:true}
	for step: Vector3i in route:
		var cell := Vector2i(step.x,step.y)
		check(not cells.has(cell),"A sculpted route must use only one height at each map cell")
		cells[cell]=true
	if failures: return
	for attempt in range(28):
		if not world.source_shrine_repair_plan(site,STAGING).is_empty(): break
		var gesture := player.route_gesture(world,route)
		if gesture.is_empty(): break
		world.step([gesture])
	check(not world.source_shrine_repair_plan(site,STAGING).is_empty(),"Sculpting the proposed route must allow a genuine construction approach")
	if failures: return
	var builders := add_followers(world,STAGING,9)
	var all := leash(site,builders)
	var belief: int=state["belief"]
	check(not world.inspect(all)["ok"],"Reject a ninth builder at the original eight-builder beacon")
	world.step([all])
	check(not site["started"] and state["belief"]==belief,"An oversized group must not start or charge the repair")
	var first := leash(site,builders.slice(0,7))
	var plan: Dictionary=world.inspect(first)
	check(plan["ok"] and plan.get("assignments",[]).size()==7,"The same beacon must accept seven builders across its four navigation entries")
	if failures: return
	world.step([first])
	var remaining := leash(site,builders.slice(7))
	check(not world.inspect(remaining)["ok"],"Count already assigned workers separately even when they share an entry")
	var eighth := leash(site,[builders[7]])
	check(world.inspect(eighth)["ok"],"Leave exactly one crew slot after the first seven")
	world.step([eighth])
	check(state["followers"].filter(func(person: Dictionary) -> bool: return person.get("repair_site")=="1017").size()==8 and not world.inspect(leash(site,[builders[8]]))["ok"],
		"The beacon must take its full source crew and refuse further assignments")


func check_coastal_beacon(world: RefCounted) -> void:
	var state: Dictionary=world._state
	for unlock: String in ["Expansion_5a","Expansion_5b","Expansion_6a","Expansion_6b","Expansion_6c"]:
		state["progression"]["script_unlocks"][unlock]=true
	for tick in range(80): world._advance_source_influence([])
	state["ore"]=100
	var site: Dictionary=world.source_shrine_site("1022")
	var staging := Vector2i(216,375)
	var approach := Vector2i(262,350)
	check(world.source_shrine_clear(site),"The original 100-ore beacon must start exposed")
	var player := Player.new()
	var route := player.sculpt_route(world,state,staging,approach,16,world.height_at(approach.x,approach.y),site)
	check(not route.is_empty(),"Find a ramp to the high coastal beacon")
	var rules: Dictionary=state["opening"]["definition"]["temple_footprint_rules"]
	var footprint: Dictionary=world.source_shrine_terrain_footprint(site)
	var area := Footprint.bounds(footprint,rules)
	var ceiling := floori(Footprint.clearance_threshold(footprint,rules))-19
	for cell: Vector3i in route:
		check(not area.has_point(Vector2i(cell.x,cell.y)) or cell.z<=ceiling,
			"The ramp must leave the original repair clearance above the beacon")
	if failures: return
	for attempt in range(30):
		if not world.source_shrine_repair_plan(site,staging).is_empty(): break
		var gesture := player.route_gesture(world,route)
		if gesture.is_empty(): break
		world.step([gesture])
	check(world.source_shrine_clear(site),"Applying the ramp drags must keep the beacon exposed")
	var repair: Dictionary=world.source_shrine_repair_plan(site,staging)
	check(repair.get("payment",{})=={"ore":100},"The connected approach must allow the original 100-ore repair")


func check_ark(world: RefCounted) -> void:
	var state: Dictionary=world._state
	state["progression"]["script_unlocks"]["Wayland_Ark_1"]=true
	for tick in range(80): world._advance_source_influence([])
	var site: Dictionary=world.source_shrine_site("1036")
	state["wheat"]=700
	state["ore"]=500
	var builders := add_followers(world,Vector2i(339,295),301)
	var full_crew := leash(site,builders.slice(0,300))
	var plan: Dictionary=world.inspect(full_crew)
	check(plan["ok"] and plan.get("assignments",[]).size()==300,"The original Ark must accept a construction plan for 300 builders")
	check(not world.inspect(leash(site,builders))["ok"],"An Ark order cannot exceed the original builder capacity")
	if failures: return
	var single := leash(site,[builders[0]])
	world.step([single,single])
	var hull: Dictionary=state["homes"].back()
	check(hull.get("shrine_id")=="1036" and state["wheat"]==0 and state["ore"]==0,"Charge the original Ark repair resources only once")
	if failures: return
	# Exercise boarding from the completion boundary, as in the crossing check.
	hull["progress"]=int(hull["build_ticks"])-1
	hull["temple_work"]=Terrain.f32(float(hull["progress"])*0.1)
	for tick in range(16):
		if site["complete"]: break
		world.step()
	check(site["complete"] and hull["residents"]==1,"The first builder must board when the Ark completes")
	if failures: return
	var boarding := leash(site,builders.slice(1,300))
	check(world.inspect(boarding)["ok"],"Allow the remaining 299 passengers to use the original Ark entries")
	check(not world.inspect(leash(site,builders.slice(1)))["ok"],"Reject boarding beyond the remaining passenger capacity")
	if failures: return
	world.step([boarding,boarding])
	check(world.source_ark_berths(site)==0,"The accepted group must reserve every berth once")
	for tick in range(220):
		if hull["residents"]==300: break
		world.step()
	check(hull["residents"]==300 and not world.inspect(leash(site,[builders[300]]))["ok"],
		"All 300 passengers must be able to board while the extra passenger waits ashore")


func add_followers(world: RefCounted,at: Vector2i,count: int) -> Array:
	var ids: Array=[]
	for index in range(count):
		var follower: Dictionary=world._agent(at.x,at.y,false)
		world._state["followers"].append(follower)
		ids.append(follower["id"])
	return ids


func leash(site: Dictionary,followers: Array) -> Dictionary:
	return {"type":"leash","followers":followers,"x":site["x"],"z":site["z"]}


func finish() -> void:
	print("Homeworld6 long beacon routes and full shrine crews: ",failures," failures")
	quit(1 if failures else 0)
