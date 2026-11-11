extends SceneTree

const World = preload("res://simulation/world.gd")
const Raids = preload("res://simulation/campaign_astari_raids.gd")
const Finger = preload("res://simulation/campaign_finger.gd")
const Content = preload("res://infrastructure/campaign_opening_content.gd")
const Progression = preload("res://simulation/progression.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func fixture(source: Dictionary) -> RefCounted:
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=325
	world.initialize({"width":40},random)
	var state: Dictionary=world._state
	var rules:=source.duplicate(true)
	rules["origins"]={"1013":[8,15],"1014":[7,15]}
	state["terrain"].fill(3)
	state["followers"].clear()
	state["sheep"].clear()
	state["opening"]={"definition":{"astari_raids":rules,"raw_floor":state["terrain"]},"submerged_levels":{},"protected":[]}
	state["progression"]={"powers":[Finger.POWER],"completed":[],"rules":{}}
	return world


func house(state: Dictionary,x: int,z: int,settlement: bool,allegiance: int=0) -> int:
	var id: int=state["next_id"]
	state["next_id"]+=1
	state["homes"].append({"id":id,"x":x,"z":z,"span":2,"settlement_core":settlement,"allegiance":allegiance,"builder":-1})
	return id


func advance(world: RefCounted,tick: int,events: Array=[]) -> Array:
	world._state["tick"]=tick
	Raids.advance(world,world._state,world._random,events)
	return events


func count_event(events: Array,type: String) -> int:
	return events.filter(func(event: Dictionary) -> bool: return event["type"]==type).size()


func run() -> void:
	var content:=Content.definition()
	var source: Dictionary=Progression.canonical_numbers(content.get("story",{}).get("astari_raids",{}))
	check(source.get("count")==5 and source.get("radii")==[16,64,256] and source.get("origins",{}).get("1013")==[197,240]
		and source.get("origins",{}).get("1023")==[309,211] and source.get("near_distance")==8,
		"Homeworld6 loads the original wave, search, beacon positions and bow pose cutoff")
	if failures: finish(); return

	var no_settlement:=fixture(source)
	var state: Dictionary=no_settlement._state
	house(state,12,15,false)
	house(state,17,15,true,1)
	Raids.shrine_repaired(state,"1013")
	check(count_event(advance(no_settlement,1),"campaign_astari_raid")==0 and state["enemies"].is_empty(),
		"The timer starts with no wave when there are only ordinary homes and enemy settlements")

	var world:=fixture(source)
	state=world._state
	house(state,12,15,false)
	house(state,15,19,true,1)
	var target_id:=house(state,27,15,true)
	house(state,32,30,true)
	var defender: Dictionary=world._agent(22,15,false)
	var tenant: Dictionary=world._agent(14,15,false)
	tenant["state"]="indoors"
	state["followers"].append_array([defender,tenant])
	Raids.shrine_repaired(state,"1013")
	Raids.shrine_repaired(state,"1014")
	var events:=advance(world,1)
	var raid: Dictionary=state["opening"]["astari_raid"]
	check(count_event(events,"campaign_astari_raid")==1 and events[0].get("id")==target_id and raid["origin"]=="1014",
		"The first wave targets the nearest player settlement from the last repaired beacon")
	check(state["enemies"].size()==5 and state["enemies"].all(func(archer: Dictionary) -> bool:
		return absf(float(archer["x"])-7.0)<1.3 and absf(float(archer["z"])-15.0)<1.3 and archer["allegiance"]==1),
		"Five hostile followers spawn with source jitter")
	if failures: finish(); return
	var origins: Array=state["enemies"].map(Raids.point)
	var hits: Array=[]
	for tick in range(2,260):
		for event: Dictionary in advance(world,tick):
			if event["type"]=="campaign_astari_arrow_hit": hits.append(event)
		if hits.size()>=2: break
	check(hits.size()>=2 and hits[0].get("id")==defender["id"] and hits[0].get("health")==50 and hits[1].get("health")==0,
		"Scouting leads to two 50-point arrows and removes the defeated follower")
	check(tenant["health"]==100 and not state["followers"].has(defender) and raid["casualties"].size()==1,
		"Indoors followers are safe and a defeated follower no longer counts towards population")
	check(origins[0].distance_to(Raids.point(state["enemies"][0]))>2,"Scouts advance along a navigable route")
	var saved:=state.duplicate(true)
	check(Raids.valid_state(saved,{}),"An in-progress raid is valid save data")
	saved["enemies"][0]["id"]=saved["next_id"]
	check(not Raids.valid_state(saved,{}),"A raid with an unallocated actor ID fails validation")
	state["enemies"].clear()

	for poll in range(1,41):
		check(count_event(advance(world,1+poll*300),"campaign_astari_raid")==0,"A repeat waits for the poll after the countdown reaches one")
	check(count_event(advance(world,12301),"campaign_astari_raid")==1 and state["enemies"].size()==5,
		"The source 1200-second countdown repeats on the 1230-second poll")
	state["enemies"].clear()
	state["progression"]["completed"].append(Finger.CARD)
	advance(world,12302,[{"type":"campaign_astari_festival_started","tutorial":true}])
	check(count_event(advance(world,13501),"campaign_astari_raid")==0,"The festival raid waits 120 seconds")
	check(count_event(advance(world,13502),"campaign_astari_raid")==1,"The festival callback launches a separate wave")
	state["enemies"].clear()
	raid["remaining"]=1
	Raids.prepare_load(state)
	check(count_event(advance(world,13503),"campaign_astari_raid")==1,"Loading resumes with the native immediate timer poll")
	state["enemies"].clear()
	state["opening"]["ark_progress"]={"conquered":true}
	raid["remaining"]=1
	check(count_event(advance(world,13803),"campaign_astari_raid")==0 and state["enemies"].is_empty(),"Conquered Astari send no further wave")
	finish()


func finish() -> void:
	print("Homeworld6 Astari raids: %d failures"%failures)
	quit(failures)
