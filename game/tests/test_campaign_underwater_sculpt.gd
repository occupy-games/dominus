extends SceneTree

const Content = preload("res://infrastructure/campaign_opening_content.gd")
const World = preload("res://simulation/world.gd")
const Water = preload("res://simulation/source_underwater_sculpt.gd")
const Temples = preload("res://simulation/temple_rules.gd")
const START := Vector2i(165,139)

var failures := 0
var world := World.new()
var state: Dictionary


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=Content.definition()
	var rules: Dictionary=content.get("story",{}).get(Water.KEY,{})
	check(rules.get("population")==440 and rules.get("sea_level")==19 and rules.get("shallow_level")==14,
		"Load the original population threshold and shallow water floor")
	if failures: finish(); return
	check(is_equal_approx(Water.cost(17,16,rules),8.0/3.0) and Water.cost(18,17,rules)==0.0 and Water.cost(65,64,rules)==50.0,
		"Use the native free band, interpolation and upper overflow price")
	var random:=RandomNumberGenerator.new()
	random.seed=440
	world.initialize({"campaign_data":content},random)
	state=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var p: Dictionary=state["progression"]
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(p,site["id"])
	for tick in range(24): world._advance_source_influence([])
	state["belief"]=100
	var left:=START+Vector2i.LEFT
	var right:=START+Vector2i.RIGHT
	set_raw(left,19)
	set_raw(START,19)
	set_raw(right,17)
	set_raw(right+Vector2i.RIGHT,13)
	set_raw(right+Vector2i.DOWN,16)
	var edge:=world.find_edge(START.x+0.49,START.y,0)
	check(world.sculpt_minimum_layer()==-5 and edge.get("layer")==-1,"Find an editable edge below the waterline")
	var shallow:=drag(START,Vector2i.RIGHT,-1,-1)
	var before: int=state["terrain_revision"]
	var quote:=world.inspect(shallow)
	check(quote["ok"] and quote["cost"]==0 and quote.get("edits",[])==[{"cell":index(START),"height":0,"raw_height":17}],
		"Quote the source free shallow retraction and keep the cell non-walkable")
	world.step([shallow])
	check(world.source_raw_height_at(START.x,START.y)==17 and state["terrain_revision"]==before and opening.get("bathymetry_revision")==1,
		"Commit wet geometry independently of walking topology")
	world.step([drag(left,Vector2i.RIGHT,0,1)])
	check(world.source_raw_height_at(START.x,START.y)==19 and state["terrain_revision"]==before,
		"Extend the zero layer across shallow water")
	set_raw(left,20)
	world.step([drag(left,Vector2i.RIGHT,1,1)])
	check(world.height_at(START.x,START.y)==1 and state["terrain_revision"]==before+1,
		"Extending above the sea creates a new dry terrace")
	var priced:=drag(right,Vector2i.DOWN,-2,-1)
	check(world.inspect(priced).get("cost")==3,"Charge three belief for sculpting raw step 17 to 16")
	world.step([priced])
	check(world.source_raw_height_at(right.x,right.y)==16 and state["belief"]==97,"Apply the underwater quote once")
	var deep:=drag(right,Vector2i.RIGHT,-5,-1)
	check(not world.inspect(deep)["ok"],"Keep raw step 13 locked before research")
	world.step([deep])
	check(state["belief"]==97 and world.source_raw_height_at(right.x,right.y)==16,"Reject a deep drag without charging or changing terrain")

	while state["followers"].size()<439: state["followers"].append(world._agent(157,123,false))
	world.step()
	check(not Water.CARD in p["discovered"],"Keep Sculpt the Oceans hidden at 439 followers")
	state["followers"].append(world._agent(157,123,false))
	var events:=world.step()
	check(events.any(func(event: Dictionary) -> bool: return event.get("card")==Water.CARD and event["type"]=="card_discovered"),
		"Discover the original card at 440 followers")
	check(not world.inspect(deep)["ok"],"Discovery alone must leave the deep floor locked")
	p["inventory"]["Sticker_Textile_1"]=1
	check(not world.inspect({"type":"research_card","card":Water.CARD,"sticker":"Sticker_Textile_1"})["ok"],"Reject a Social-only sticker")
	var assign:={"type":"research_card","card":Water.CARD,"sticker":"Sticker_ReligiousObject_2"}
	p["inventory"][assign["sticker"]]=6
	for payment in range(5): world.step([assign])
	check(not world.inspect(deep)["ok"] and p["research"].get(Water.CARD)==10,
		"Credit only the matching contribution and keep the gate through partial research")
	world.step([assign])
	check(Water.CARD in p["completed"] and world.sculpt_minimum_layer()==-19 and world.inspect(deep)["ok"],
		"Twelve Faith points must enable the original deep floor")
	world.step([deep])
	check(world.source_raw_height_at(right.x,right.y)==13 and state["terrain_revision"]==before+1,
		"Retraction reaches the deeper shelf while retaining dry topology")
	var saved:=World.new()
	check(saved.restore(world.export_state(),RandomNumberGenerator.new()),"Save and load the new raw heights and depth revision")
	if not failures:
		check(saved.sculpt_minimum_layer()==-19 and saved.source_raw_height_at(right.x,right.y)==13 and saved._state["opening"]["bathymetry_revision"]==opening["bathymetry_revision"],
			"Reload must keep the researched floor and exact sculpted layers")
	finish()


func index(point: Vector2i) -> int:
	return point.y*int(state["width"])+point.x


func set_raw(point: Vector2i,raw: int) -> void:
	var cell:=index(point)
	var height:=maxi(0,raw-19)
	if state["terrain"][cell]>0 and height==0: world._dry_land-=1
	if state["terrain"][cell]==0 and height>0: world._dry_land+=1
	state["terrain"][cell]=height
	if height==0: state["opening"]["submerged_levels"][str(cell)]=raw


func drag(point: Vector2i,normal: Vector2i,layer: int,distance: int) -> Dictionary:
	return {"type":"sculpt_drag","x":point.x,"z":point.y,"nx":normal.x,"nz":normal.y,"layer":layer,"distance":distance,"radius":0}


func finish() -> void:
	print("Homeworld6 underwater sculpting: ",failures," failures")
	quit(1 if failures else 0)
