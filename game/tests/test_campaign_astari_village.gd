extends SceneTree

const World = preload("res://simulation/world.gd")
const Astari = preload("res://simulation/campaign_astari.gd")
const Fountain = preload("res://simulation/campaign_fountain.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func festival_step(world: RefCounted,tick: int) -> Array:
	var events: Array=[]
	world._state["tick"]=tick
	Astari.advance(world,world._state,world._random,events)
	return events


func result(events: Array) -> int:
	for event: Dictionary in events:
		if event["type"]=="campaign_astari_festival_ended": return int(event["converted"])
	return 0


func run() -> void:
	var source:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var rules: Dictionary=source.get("story",{}).get("astari_village",{})
	check(rules.get("population")==250 and rules.get("interval")==3600 and rules.get("length")==120,
		"The original population and desktop festival timing must mount")
	if failures: finish(); return
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=1201
	world.initialize({"campaign_data":source},random)
	var state: Dictionary=world._state
	var p: Dictionary=state["progression"]
	var village: Dictionary=state["astari_village"]
	var core: Dictionary=village["homes"][0]
	var house: Dictionary=village["homes"][1]
	check(core["anchor_x"]==307 and core["anchor_z"]==330 and core["span"]==6 and core["depth"]==8 and core["residents"]==230,
		"The bespoke six by eight settlement must retain its 230 assigned occupants")
	check(house["anchor_x"]==316 and house["anchor_z"]==331 and house["residents"]==5 and world._occupied(316,331),
		"The source dwellings must reserve their real village positions")
	check(world.inspect_building(house["id"]).get("occupants")==5 and not world.inspect({"type":"collect","home_id":house["id"]})["ok"],
		"The player can inspect a rival house without taking its belief")
	check(festival_step(world,100).is_empty(),"The festival must wait for its original Fountain advance")
	p["discovered"].append(Fountain.CARD)
	p["completed"].append(Fountain.CARD)
	p["happiness"]={"player":0.0,"astari":0.7}
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	var home_id: int=state["next_id"]
	state["next_id"]+=1
	var home: Dictionary={"id":home_id,"x":160,"z":135,"span":4,"anchor_x":162,"anchor_z":137,"work_x":159,"work_z":137,
		"capacity":100,"residents":100,"progress":1,"build_ticks":1,"stored":0,"builder":-1,"stalled":false}
	state["homes"].append(home)
	for follower: Dictionary in state["followers"]:
		follower.merge({"indoors_home":home_id,"state":"indoors","x":159.0,"z":137.0},true)
	for index in range(98):
		var follower:=world._agent(159,137,false)
		follower.merge({"indoors_home":home_id,"state":"indoors","female":index%2==0},true)
		state["followers"].append(follower)
	world._spatial_revision+=1
	var opened:=festival_step(world,101)
	check(opened.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_astari_festival_started"),
		"The first festival starts after completing the original advance")
	check(village["festival"].get("until")==1301 and village["performers"].size()==40 and Astari.population(state)==250,
		"The 120-second festival materializes forty villagers with conserved population")
	var start: Vector2=Astari.point(village["performers"][0])
	for tick in range(102,160): festival_step(world,tick)
	check(Astari.point(village["performers"][0]).distance_to(start)>2.0,"The festival crowd walks on the original terrain")
	var save:=world.export_state()
	var restored:=World.new()
	check(restored.restore(save,RandomNumberGenerator.new()),"An active festival and its participants must survive reload")
	if failures: finish(); return
	var outcome:=festival_step(world,1301)
	check(result(outcome)==-4 and state["followers"].size()==96 and home["residents"]==96 and Astari.population(state)==254,
		"The native loss formula transfers four housed followers to the happier Astari")
	check(result(festival_step(restored,1301))==-4 and Astari.population(restored._state)==254,
		"Reload preserves the original conversion outcome and population")
	var next_festival: int=village["next_festival"]
	check(next_festival==37301 and festival_step(world,next_festival-1).is_empty(),"The next festival starts one desktop hour after the previous one ends")
	p["happiness"].merge({"player":1.0,"astari":-0.9},true)
	festival_step(world,next_festival)
	var gains:=festival_step(world,int(village["festival"]["until"]))
	check(result(gains)==16 and Astari.population(state)==238 and state["followers"].size()==112,
		"The native positive conversion formula admits sixteen villagers when player happiness wins")
	check(not p.get("script_unlocks",{}).get("winAstari",false),"Partial conversion must leave the rival village independent")
	finish()


func finish() -> void:
	print("Homeworld6 Astari village: %d failures"%failures)
	quit(failures)
