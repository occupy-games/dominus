extends SceneTree

const Cliff = preload("res://simulation/campaign_cliff_sculpt.gd")
const World = preload("res://simulation/world.gd")
const Temples = preload("res://simulation/temple_rules.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var p: Dictionary=state["progression"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	p["script_unlocks"]={"PlotsAppearClaim":true,"Low_Rank_1":true}
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(p,site["id"])
	for tick in range(24): world._advance_source_influence([])
	# Controlled adjacent columns on the original active terrain. Commands
	# below still run through the normal query, debit and topology update.
	var x:=165
	var z:=139
	var width: int=state["width"]
	for row in range(3):
		state["terrain"][(z+row)*width+x]=10 if row==2 else 8
		state["terrain"][(z+row)*width+x+1]=5
	state["belief"]=100
	var extend:={"type":"sculpt_drag","power":Cliff.POWER,"x":x,"z":z,"nx":1,"nz":0,"layer":8,"distance":1,"radius":0}
	while state["followers"].size()<199: state["followers"].append(world._agent(157,123,false))
	world.step()
	check(not Cliff.CARD in p["discovered"] and not world.inspect(extend)["ok"],"Cliff Sculpting must be locked at 199 followers")
	state["followers"].append(world._agent(157,123,false))
	world.step()
	check(Cliff.CARD in p["discovered"] and not world.inspect(extend)["ok"],"The 200-follower card still needs Faith research")
	var definition: Dictionary=p["rules"]["research_cards"][Cliff.CARD]
	var sticker:=""
	var points:=0
	for id: String in p["rules"]["stickers"]:
		if p["rules"]["stickers"][id].get("internal",false): continue
		points=int(p["rules"]["stickers"][id].get("contributions",{}).get(definition["research_type"],0))
		if points>0: sticker=id; break
	check(not sticker.is_empty(),"The supplied research catalog must contain a compatible Faith sticker")
	if failures>0: quit(1); return
	var count:=ceili(float(definition["research_needed"])/points)
	p["inventory"][sticker]=count
	for index in range(count): world.step([{"type":"research_card","card":Cliff.CARD,"sticker":sticker}])
	check(Cliff.POWER in p["powers"],"Finishing Faith research must arm the Cliff Sculpting power")
	var point:=Vector2(x+0.5,z)
	check(world.find_edge(point.x,point.y,0)["layer"]==6,"The ordinary tool must still pick the lowest exposed layer")
	check(world.find_edge(point.x,point.y,0,true)["layer"]==8,"The Cliff tool must pick the three-layer face")
	var quoted:=world.inspect(extend)
	check(quoted["ok"] and quoted["cost"]==4 and quoted["edits"]==[{"cell":z*width+x+1,"height":8}],"The outward preview must quote and extend the full three-layer face")
	world.step([extend,extend])
	check(world.height_at(x+1,z)==8 and state["belief"]==96,"An already-moved face must not charge again")
	var retract:=extend.duplicate()
	retract["z"]=z+1
	retract["distance"]=-1
	world.step([retract])
	check(world.height_at(x,z+1)==5 and state["belief"]==92,"An inward drag must retract the same band")
	extend["z"]=z+2
	world.step([extend])
	check(world.height_at(x,z+2)==10 and world.height_at(x+1,z+2)==8,"A taller cliff must keep the untouched layers above the researched cap")
	check_upgrades(world)
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and restored.snapshot(false)["opening"]["cliff_status"]["layers"]==12,"The researched tool, all upgrades and terrain must survive reload")
	print("Source Homeworld6 Cliff Sculpting: ",failures," failures")
	quit(1 if failures else 0)


func check_upgrades(world: RefCounted) -> void:
	var state: Dictionary=world._state
	var rules: Dictionary=state["opening"]["definition"]["cliff_sculpt"]
	var upgrade:={"type":"campaign_cliff_upgrade"}
	state["ore"]=100
	upgrade["id"]=rules["upgrades"][2]["id"]
	check(not world.inspect(upgrade)["ok"],"An affordable later upgrade must still follow the preceding upgrade")
	for level: Dictionary in rules["upgrades"]:
		upgrade["id"]=level["id"]
		state[level["currency"]]=int(level["cost"])-1
		check(not world.inspect(upgrade)["ok"],"The matching original currency is required for each upgrade")
		state[level["currency"]]=level["cost"]
		world.step([upgrade,upgrade])
		check(Cliff.layers(state)==level["layers"] and state[level["currency"]]==0,"Each upgrade must debit its price once and apply the source layer cap")
	check(not Cliff.status(state).has("next"),"The twelve-layer upgrade must finish the original sequence")
