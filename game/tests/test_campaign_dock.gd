extends SceneTree

const World = preload("res://simulation/world.gd")
const Progression = preload("res://simulation/progression.gd")
const Temples = preload("res://simulation/temple_rules.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)


func hint(world: RefCounted,id: int) -> bool:
	return world._state["opening"]["messages"].any(func(item: Dictionary) -> bool: return item["id"]==id)


func run() -> void:
	var definition:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var level: Dictionary=opening["definition"]["leash_population_card"]
	# Exercise the repair on the actual source coast. Set up the already
	# verified Leashing lesson handoff and place two actors on that coast.
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"leash_step":1,"leash_level_card":level["id"],"leash_mission_pending":true,"messages":[]},true)
	Progression.discover(state["progression"],level["id"])
	var pit:=world.source_shrine_site()
	pit["started"]=true
	Temples.complete(state["progression"],pit["id"])
	var dock:=world.source_dock_site()
	check(dock["id"]=="1002" and world.source_shrine_layer(dock)==22 and dock["build_ticks"]==600 and dock["build_capacity"]==5,"The Dock must use its original placement and construction fields")
	for tick in range(25): world._advance_source_influence([])
	for index in range(2):
		state["followers"][index].merge({"x":198.0+index,"z":181.0,"state":"idle","job":-1},true)
	state["belief"]=150
	world.step([{"type":"campaign_leash_lesson_completed"}])
	check(opening["leash_step"]==2 and hint(world,5208),"The source mission return must show the Dock instruction when the Pit has expanded influence")
	var ids: Array=state["followers"].map(func(item: Dictionary) -> int: return item["id"])
	var leash:={"type":"leash","followers":ids,"x":dock["x"],"z":dock["z"]}
	var claim:={"type":"campaign_activate_shrine","id":dock["id"]}
	var go:={"type":"campaign_dock_go","id":dock["id"]}
	check(not world.inspect(claim)["ok"] and not world.inspect(go)["ok"],"The Dock must stay unclaimable and cannot launch before repair")
	check(not world.inspect(leash)["ok"] and world.inspect(leash)["cost"]==200,"Belief must be checked for the complete group")
	world.step([leash])
	check(state["belief"]==150 and not dock["started"] and hint(world,5207),"An unaffordable leash must leave actors and belief unchanged and show the source cost hint")
	state["belief"]=500
	var walk:={"type":"leash","followers":[ids[1]],"x":199,"z":182}
	check(world.inspect(walk)["ok"],"An unlocked leash must accept a reachable ordinary land target")
	world.step([walk])
	for tick in range(70):
		if not state["followers"][1].has("leash_goal"): break
		world.step()
	check(state["followers"][1]["z"]==182 and state["belief"]==400 and not dock["started"],"A land leash must walk to the target without starting the Dock")
	check(world.inspect(leash)["ok"],"Both followers must be able to take distinct Dock approaches")
	world.step([leash])
	check(opening["leash_step"]==3 and dock["started"] and state["belief"]==200,"The accepted group must pay once and trigger the source construction stage")
	var saved:=world.export_state()
	var restored:=World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()) and restored.export_state()==saved,"The Dock job and both walking Builders must survive a save")
	world=restored
	dock=world.source_dock_site()
	for tick in range(900):
		if dock.get("repaired",false): break
		world.step()
	check(dock.get("repaired",false) and world.inspect(claim)["ok"] and not world.inspect(go)["ok"],"Only real completed work may expose the Dock's card")
	var events:=world.step([claim,claim])
	check(events.has({"type":"campaign_show_card","card":"Card_Events"}) and hint(world,5205),"Claim must open the original Voyages card and message")
	check(world._state["progression"]["reward_history"].get("Card_Events")==1,"The source reward must be granted once")
	var popup_save:=world.export_state()
	var continued:=World.new()
	check(continued.restore(popup_save,RandomNumberGenerator.new()),"A save during the Voyages card must reload")
	continued.prepare_loaded_opening()
	continued.step()
	check(hint(continued,5301) and continued.inspect(go)["ok"],"The source post-load callback must proceed to the Dock's Go lesson")
	world.step([{"type":"campaign_dismiss_level_card"}])
	check(hint(world,5301),"Dismissing the original card must ask the player to select the Dock")
	world.step([{"type":"campaign_select_dock","id":dock["id"]}])
	check(not hint(world,5301) and hint(world,5302),"Selecting the repaired Dock must switch to the original Go instruction")
	check(world.step([go]).has({"type":"campaign_start_first_voyage"}) and world._state["opening"]["error"].is_empty(),"Go must request the first voyage without an unsupported source callback")
	world.step([{"type":"campaign_first_voyage_returned","won":false}])
	check(world._state["opening"]["persistent"]["EventVoyageProgress"]==1 and world.inspect(go)["ok"] and not hint(world,5303),"The original first-voyage defeat must allow another attempt")
	world.step([{"type":"campaign_first_voyage_returned","won":true}])
	check(world._state["opening"]["persistent"]["EventVoyageProgress"]==2 and world._state["opening"]["events_step"]==1 and hint(world,5303),"The original successful return must show the source Farming instruction")
	check(world.step([go]).has({"type":"campaign_open_voyages"}),"Go after the first victory must open the voyage selection")
	if failures==0: check_expansion(world)
	if failures==0: check_sacrifice(world)
	print("Source Dock repair, leash and card: ",failures," failures")
	quit(1 if failures else 0)


func check_expansion(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var first: Dictionary=world.source_shrine_site(opening["definition"]["first_shrine_id"])
	first["started"]=true
	Temples.complete(state["progression"],first["id"])
	for tick in range(35): world._advance_source_influence([])
	var beacon: Dictionary=world.source_shrine_site("1013")
	var release:={"type":"campaign_activate_shrine","id":beacon["id"]}
	var anchor:=Vector2i(beacon["x"],beacon["z"])
	check(not world.inspect(release)["ok"] and not world.can_act_at(190,220),"The next expansion must require actual Beacon repair")
	var entrance:=Vector2i(-1,-1)
	for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var start:=anchor+offset
		if not world.source_shrine_repair_plan(beacon,start).is_empty(): entrance=start; break
	check(entrance.x>=0,"The next source Beacon must have an approach in the existing influence")
	if failures>0: return
	var worker: Dictionary=world._agent(entrance.x,entrance.y,false)
	state["followers"].append(worker)
	var leash:={"type":"leash","followers":[worker["id"]],"x":anchor.x,"z":anchor.y}
	check(world.inspect(leash)["ok"],"A real leash must accept the next authored expansion site")
	if failures>0: return
	world.step([leash])
	var job: Dictionary=state["homes"].back()
	check(job.get("shrine_id")==beacon["id"] and beacon["started"] and job["build_ticks"]==9000,"The Builder must start the original Beacon's native construction duration")
	if failures>0: return
	# Resume with one tick of authored repair work remaining.
	job["progress"]=8999
	job["temple_work"]=preload("res://simulation/source_terrain.gd").f32(899.99)
	for tick in range(20):
		if beacon.get("repaired",false): break
		world.step()
	check(world.inspect(release)["ok"] and beacon["id"] in world.snapshot(false)["opening"]["shrine_claims"],"Completed work must expose the Beacon claim")
	world.step([release,release])
	for tick in range(60): world.step()
	check(beacon["complete"] and world.can_act_at(190,220) and not world.inspect(release)["ok"],"The original expansion unlock must expose the new coast only once")
	check(not opening.get("pit_card_open",false) and opening["events_step"]==1,"Later Beacons must preserve the completed opening tutorials")


func check_sacrifice(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var pit: Dictionary=world.source_shrine_site()
	var pit_rules=preload("res://simulation/campaign_pit.gd")
	var weights: Array=opening["definition"]["pit_sacrifice"]["gems"]
	for pair: Array in [[0.5,1],[0.965,2],[0.975,3],[0.985,4],[0.995,5]]:
		check(pit_rules.payout(weights,pair[0])==pair[1],"Every authored gem payout must occupy its original probability interval")
	check(hint(world,5102),"The original Pit leash instruction must become available after the Leashing lesson")
	var anchor:=Vector2i(pit["x"],pit["z"])
	var approach:=Vector2i(-1,-1)
	for offset: Vector2i in [Vector2i(-4,0),Vector2i(4,0),Vector2i(0,-4),Vector2i(0,4)]:
		if not pit_rules.route(world,state,pit,anchor+offset).is_empty(): approach=anchor+offset; break
	check(approach.x>=0,"The source Pit must be reachable on its actual map")
	if failures>0: return
	var agent: Dictionary=world._agent(approach.x,approach.y,false)
	state["followers"].append(agent)
	var leash:={"type":"leash","followers":[agent["id"]],"x":anchor.x,"z":anchor.y}
	var price: int=opening["definition"]["leash_rules"]["follower_cost"]
	state["belief"]=price-1
	var gems: int=state["gems"]
	var happiness: float=state["progression"]["happiness"]["player"]
	check(not world.inspect(leash)["ok"],"A Pit leash without enough belief must be rejected")
	state["belief"]=price*2
	check(world.inspect(leash).get("sacrifice",false),"Dropping on the repaired Pit must select its native sacrifice destination")
	world.step([leash,leash])
	check(state["belief"]==price and state["gems"]==gems and agent.has("leash_goal"),"The accepted order charges belief once and begins the walk before granting gems")
	for tick in range(200):
		if agent.has("sacrifice_due"): break
		world.step()
	check(agent.has("sacrifice_due") and not agent.has("leash_goal") and agent["state"] in pit_rules.CLIPS,"Arriving at the Pit must start an original sacrifice clip")
	if failures>0: return
	for tick in range(35): world.step()
	var second: Dictionary=world._agent(approach.x,approach.y,false)
	var home_id: int=state["next_id"]
	state["next_id"]+=1
	state["homes"].append({"id":home_id,"x":170,"z":145,"span":1,"build_ticks":120,"progress":120,"stored":0,
		"residents":1,"capacity":2,"birth_ticks":100,"builder":-1,"work_x":170,"work_z":144,"stalled":false})
	second["away_home"]=home_id
	state["followers"].append(second)
	var another: Dictionary=leash.duplicate()
	another["followers"]=[second["id"]]
	world.step([another])
	check(second.get("leash_sacrifice",false) and state["gems"]==gems,"A second arrival must join the pending source batch")
	var saved:=World.new()
	check(saved.restore(world.export_state(),RandomNumberGenerator.new()),"An in-progress sacrifice must survive a save")
	if failures>0: return
	world=saved
	state=world._state
	opening=state["opening"]
	var events: Array=[]
	var before: int=state["followers"].size()
	var first_due: int=agent["sacrifice_due"]
	while state["tick"]<first_due+30: events.append_array(world.step())
	check(state["gems"]==gems and state["followers"].size()==before,"The first completed clip and gem delay must wait for the later follower")
	for tick in range(160): events.append_array(world.step())
	var rewards:=events.filter(func(event: Dictionary) -> bool: return event["type"]=="campaign_follower_sacrificed")
	check(rewards.size()==2 and state["followers"].size()==before-2 and state["gems"]>=gems+2 and state["gems"]<=gems+10,"The restored batch must remove and pay out both followers exactly once")
	check(events.count({"type":"source_sound","event":"Pit of Doom sacrifice"})==2,"Both original sound cues must fire at their native offsets after loading")
	check(events.count({"type":"campaign_pit_beam","site":pit["id"]})==2,"The native beam delay must fire once per completed clip")
	check(opening["pit_step"]==2 and not hint(world,5102) and opening["error"].is_empty(),"The original sacrifice callback must finish the Pit lesson")
	check(is_equal_approx(float(state["progression"]["happiness"]["player"]),maxf(0,happiness-0.2)) and events.count({"type":"campaign_autosave"})==1,"The source happiness penalty and one save must follow the delayed payout")
	var stats: Dictionary=preload("res://simulation/building_stats.gd").inspect(state,pit["id"],"temple")["pit"]
	check(stats["followers"]==2 and stats["gems"]==state["gems"]-gems and is_equal_approx(stats["unhappiness"],0.2),"The Pit's original inspection rows must count its own outcomes")
	var home: Dictionary=state["homes"].back()
	var birth:=preload("res://simulation/building_stats.gd").authored_birth_interval(state,home)
	check(home.get("sacrificed_followers",0)==1 and birth==20000,"The sacrificed resident must leave the original birth-time multiplier on their abode")
	if failures>0: return
	# The authored all-followers-dead hook must allow the colony to recover.
	state["followers"].clear()
	var last: Dictionary=world._agent(approach.x,approach.y,false)
	state["followers"].append(last)
	state["belief"]=price
	leash["followers"]=[last["id"]]
	world.step([leash])
	for tick in range(240):
		if state["followers"].size()==2: break
		world.step()
	check(state["followers"].size()==2 and not state["followers"].has(last) and opening["pit_step"]==2,"Losing the final follower must restore the original starting pair without resetting the tutorial")
	if state["followers"].size()==2:
		var starts: Array=opening["definition"]["starts"]
		for index in range(2):
			check(is_equal_approx(state["followers"][index]["x"],starts[index]["x"]) and state["followers"][index]["female"]==starts[index]["source_args"][5],"The recovered pair must use its original position and sex")
