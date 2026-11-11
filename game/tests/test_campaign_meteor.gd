extends SceneTree

const Content = preload("res://infrastructure/campaign_opening_content.gd")
const World = preload("res://simulation/world.gd")
const Meteor = preload("res://simulation/campaign_meteor.gd")
const Fields = preload("res://simulation/source_map_fields.gd")
const Temples = preload("res://simulation/temple_rules.gd")
const TARGET := Vector2i(165,139)
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=Content.definition()
	var rules: Dictionary=content.get("story",{}).get(Meteor.KEY,{})
	check(rules.get("population")==500 and rules.get("belief")==6000,"Load the original Meteor Strike milestone and Miracle cost")
	if failures: finish(); return
	check_native(rules)
	var world:=World.new()
	var random:=RandomNumberGenerator.new()
	random.seed=500
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	var progression: Dictionary=state["progression"]
	for site: Dictionary in [world.source_shrine_site(opening["definition"]["first_shrine_id"]),world.source_shrine_site()]:
		site["started"]=true
		Temples.complete(progression,site["id"])
	for tick in range(24): world._advance_source_influence([])
	for z in range(TARGET.y-4,TARGET.y+5):
		for x in range(TARGET.x-4,TARGET.x+5):
			if world.height_at(x,z)==0: world._dry_land+=1
			state["terrain"][z*1024+x]=4
	var command:={"type":"use_power","power":Meteor.POWER,"x":TARGET.x+0.125,"z":TARGET.y+0.125,
		"viewport":[1200,800],"drag":[0,460],"heading":[0,1],"seconds":0.25}
	while state["followers"].size()<499: state["followers"].append(world._agent(157,123,false))
	world.step()
	check(not Meteor.CARD in progression["discovered"] and not world.inspect(command)["ok"],"Keep Meteor Strike locked at 499 followers")
	state["followers"].append(world._agent(157,123,false))
	var events:=world.step()
	check(events.any(func(event: Dictionary) -> bool: return event.get("card")==Meteor.CARD and event["type"]=="card_discovered"),"Discover Meteor Strike at 500 followers")
	state["belief"]=5999
	check(not world.inspect(command)["ok"] and world.inspect(command)["cost"]==6000,"Quote the original belief cost")
	state["belief"]=6000
	var invalid:=command.duplicate()
	invalid["drag"]=[0,-460]
	check(not world.inspect(invalid)["ok"],"Reject a swipe aimed up")
	invalid=command.duplicate()
	invalid.merge({"x":800,"z":800},true)
	check(not world.inspect(invalid)["ok"],"Reject a cast outside influence")
	check(world.inspect(command)["ok"],"Accept a valid swipe inside influence after discovery")
	if failures: finish(); return
	var cell:=TARGET.y*1024+TARGET.x
	events=world.step([command,command])
	check(state["belief"]==0 and opening["meteor_flights"].size()==1 and events.any(func(event: Dictionary) -> bool: return event.get("event")=="Meteor Strike launch"),"Debit and launch exactly once")
	check(state["terrain"][cell]==4,"A flying meteor leaves the terrain intact until impact")
	var restored:=World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Restore a paid meteor in flight")
	if failures: finish(); return
	var impacts:=0
	for tick in range(28):
		events=world.step()
		check(events==restored.step(),"Resumed flight must emit the same ordered events")
		for event: Dictionary in events:
			if event["type"]=="campaign_meteor_impact": impacts+=1
	check(impacts==1 and state["terrain"][cell]<4,"Impact lowers the original layers once")
	check(Fields.byte_at(state["source_influence"]["raster"],2,TARGET.x,TARGET.y)==128,"Impact writes the original blight byte")
	check(world.export_state()==restored.export_state(),"Finish the blast identically after restoring")
	state["gems"]=10
	var upgrade:={"type":Meteor.UPGRADE,"id":"LvlUp_GodPower_MeteorStrike_2"}
	check(world.inspect(upgrade)["ok"],"Offer the source ten-gem upgrade")
	world.step([upgrade])
	check(state["gems"]==0 and not world.inspect(upgrade)["ok"],"Apply the upgrade only once")
	finish()


func check_native(rules: Dictionary) -> void:
	# Captured with native 0x1008b6c6, 0x100f7180, 0x10143a80 and 0x100f6ff0.
	var source = Meteor.Source
	var viewport:=Vector2(1200,800)
	check(source.swipe(Vector2(0,80),viewport,0.25,rules).is_empty(),"Native minimum swipe distance is exclusive")
	var quote: Dictionary=source.swipe(Vector2(80,240),viewport,0.25,rules)
	check(is_equal_approx(float(quote.get("angle",0)),18.434947967529297) and is_equal_approx(float(quote.get("speed",0)),52.541038513183594),"Match native diagonal swipe angle and speed")
	var flight: Dictionary=source.launch(Vector3(173.25,6.9,249.625),Vector2(0,1),{"angle":30.0,"speed":56.0},rules)
	check(source.vector(flight["position"]).distance_to(Vector3(173.25,41.416568756103516,229.625))<0.0001,"Match native launch position")
	check(source.vector(flight["velocity"]).distance_to(Vector3(0,-48.49742126464844,28))<0.0001,"Match native velocity")
	var result: Dictionary
	for frame in range(8): result=source.advance(flight,func(_x: float,_z: float) -> float: return 6.900000095367432,0.1,rules)
	check(result.has("impact") and (result["impact"] as Vector3).distance_to(Vector3(173.25,6.800000190734863,252.0250244140625))<0.0001,"Match native impact after eight equal frames")
	var edits: Array=source.crater(Vector3(173.25,6.8,249.625),4.0,-2.4,1024,rules,
		func(x: int,z: int) -> int: return 23+(x+z)%3,
		func(x: int,z: int) -> int: return 23 if x==175 and z==250 else (24 if x==174 and z==250 else 0))
	var heights:={}
	for edit: Dictionary in edits: heights[edit["cell"]]=edit["raw_height"]
	check(heights.size()==49 and heights[250*1024+173]==20 and heights[250*1024+175]==23 and not heights.has(250*1024+174),"Match the native crater footprint and height clamps")
	var raster:={"fields":{}}
	source.write_fields(raster,Vector3(173.25,6.8,249.625),2.64,5.0,1024)
	check(Fields.byte_at(raster,2,173,249)==128 and Fields.byte_at(raster,2,171,247)==21 and Fields.byte_at(raster,2,172,247)==97,"Match the native blight field's center and falloff")


func finish() -> void:
	print("Homeworld6 Meteor Strike: ",failures," failures")
	quit(1 if failures else 0)
