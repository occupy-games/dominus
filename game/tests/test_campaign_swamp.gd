extends SceneTree

const Content = preload("res://infrastructure/campaign_opening_content.gd")
const World = preload("res://simulation/world.gd")
const Swamp = preload("res://simulation/campaign_swamp.gd")
const Fields = preload("res://simulation/source_map_fields.gd")
const Temples = preload("res://simulation/temple_rules.gd")
const START := Vector2i(165,139)
var failures := 0


class FlatTerrace extends RefCounted:
	var capacity := 4

	func source_raw_height_at(_x: float,_z: float) -> int:
		return 21

	func _occupied(_x: int,_z: int) -> bool:
		return false

	func source_plot_capacity(_x: int,_z: int,limit: int) -> int:
		return mini(capacity,limit)


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=Content.definition()
	var rules: Dictionary=content.get("story",{}).get(Swamp.KEY,{})
	check(rules.get("population")==400 and rules.get("belief")==4000 and rules.get("initial",[]).size()==6,
		"Load the original Swamp discovery, cost and authored positions")
	if failures: finish(); return
	check_native_spread(rules)
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=400
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var p: Dictionary=state["progression"]
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(p,site["id"])
	for tick in range(24): world._advance_source_influence([])
	for z in range(START.y-5,START.y+6):
		for x in range(START.x-5,START.x+6):
			if world.height_at(x,z)==0: world._dry_land+=1
			state["terrain"][z*1024+x]=2
	var command:={"type":"use_power","power":Swamp.Source.POWER,"x":START.x+0.25,"z":START.y+0.25}
	while state["followers"].size()<399: state["followers"].append(world._agent(157,123,false))
	world.step()
	check(opening[Swamp.KEY]["casts"].size()==6,"Initial source script must place its six wetlands once")
	check(not Swamp.Source.CARD in p["discovered"] and not world.inspect(command)["ok"],"Keep Swamp locked below its milestone")
	state["followers"].append(world._agent(157,123,false))
	var events:=world.step()
	check(events.any(func(event: Dictionary) -> bool: return event.get("card")==Swamp.Source.CARD and event["type"]=="card_discovered"),
		"Discover Swamp at 400 followers")
	state["belief"]=3999
	check(not world.inspect(command)["ok"] and world.inspect(command)["cost"]==4000,"Use the source Miracle cost in the live quote")
	state["belief"]=4000
	check(world.inspect(command)["ok"],"Place the original power inside influence after discovery")
	events=world.step([command,command])
	check(state["belief"]==0 and opening[Swamp.KEY]["casts"].size()==7 and events.any(func(event: Dictionary) -> bool: return event.get("event")=="Swamp cast"),
		"Charge once and emit the recovered cast sound")
	for tick in range(65): world.step()
	check(Swamp.active_at(state,START.x,START.y),"The expanding cast must form a working puddle")
	if failures: finish(); return
	var target:=world._agent(START.x,START.y,false)
	state["followers"].append(target)
	world.step()
	check(target.has("swamp_entered") and target["health"]<100,"A follower in a puddle struggles and takes source damage")
	for tick in range(50):
		world.step()
		if not target in state["followers"]: break
	check(not target in state["followers"] and opening[Swamp.KEY]["casualties"].size()==1,"The trap must remove the drowned follower and keep its animation state")
	var saved:=World.new()
	check(saved.restore(world.export_state(),RandomNumberGenerator.new()),"Restore the in-progress Swamp and its casualty")
	if failures: finish(); return
	check(Swamp.active_at(saved._state,START.x,START.y) and saved.snapshot(false).get("casualties",[]).size()==1,
		"Loading preserves the active footprint and the original death animation")
	var current: Dictionary=opening[Swamp.KEY]["casts"].back()
	current["until"]=state["tick"]+1
	world.step()
	check(not Swamp.active_at(state,START.x,START.y),"The spent Miracle must expire and unblock its footprint")
	finish()


func check_native_spread(rules: Dictionary) -> void:
	var raster:={"fields":{}}
	var spread:=Swamp.Source.start(170.25,250.75,21,12000,1024,raster)
	for frame in range(75):
		Swamp.Source.spread(spread,raster,rules,func(_x: int,_z: int) -> int: return 21,1024,0.04)
		if frame==0:
			check(spread["count"]==2 and Fields.byte_at(raster,3,170,251)==2 and Fields.byte_at(raster,3,171,251)==2,
				"Match the original first spread frame on a flat terrace")
		elif frame==39:
			check(spread["count"]==10 and Fields.byte_at(raster,3,169,251)==42 and Fields.byte_at(raster,3,171,250)==52,
				"Match the native intermediate membership and blight bytes")
	check(spread["count"]==21 and Fields.byte_at(raster,3,170,251)==64 and Fields.byte_at(raster,3,171,251)==62,
		"Match the recovered native three-second spread")
	var stepped:={"fields":{}}
	var cliff:=Swamp.Source.start(170.25,250.75,21,12000,1024,stepped)
	for frame in range(75):
		Swamp.Source.spread(cliff,stepped,rules,func(x: int,_z: int) -> int: return 22 if x>=171 else 21,1024,0.04)
	check(Fields.byte_at(stepped,3,171,250)==0 and Fields.byte_at(stepped,3,170,251)>0,"Spread follows a terrace and stops at its one-layer cliff")
	var flat:=FlatTerrace.new()
	var expected:=[[169,248,4],[167,250,2],[168,253,2],[171,253,2],[168,249,1]]
	check(Swamp.pack_puddles(flat,spread,rules,1024,{})==expected,"Match the native descending puddle footprints")
	flat.capacity=0
	check(Swamp.pack_puddles(flat,spread,rules,1024,{}).is_empty(),"The desktop source must skip zero-size puddles")


func finish() -> void:
	print("Homeworld6 Swamp: ",failures," failures")
	quit(1 if failures else 0)
