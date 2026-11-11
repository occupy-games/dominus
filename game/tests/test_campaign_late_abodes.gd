extends SceneTree

const World = preload("res://simulation/world.gd")
const Plots = preload("res://simulation/source_plot_registry.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Session = preload("res://application/game_session.gd")
const Progression = preload("res://simulation/progression.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var content:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	var random:=RandomNumberGenerator.new()
	random.seed=480
	var world:=World.new()
	world.initialize({"campaign_data":content},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var progression: Dictionary=state["progression"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	opening["globals"]["onStartPlayTriggered"]=true
	progression["script_unlocks"]={"PlotsAppearClaim":true,"Low_Rank_1":true,"FoodSpending":true}
	state["wheat"]=100

	for item: Array in [
		[480,"Card_AbodeType1_Rank3","AbodeType_1_Rank_3",Vector2i(150,132),7,23,8,"41a622c1"],
		[650,"Card_AbodeType3_Rank3","StoneHouse_Rank_3",Vector2i(161,132),7,41,12,"41a622c1"],
		[1000,"Card_AbodeType3_Rank4","StoneHouse_Rank_4",Vector2i(172,132),9,41,14,"f2808902"],
	]:
		check_abode(world,item)
		if failures: break
	if not failures: check_old_save(world,content["story"])
	print("Homeworld6 later population abodes: ",failures," failures")
	quit(1 if failures else 0)


func check_abode(world: RefCounted,item: Array) -> void:
	var state: Dictionary=world._state
	var progression: Dictionary=state["progression"]
	var threshold: int=item[0]
	var card: String=item[1]
	var source_house: String=item[2]
	var origin: Vector2i=item[3]
	var span: int=item[4]
	var raw_height: int=item[5]
	var work:=origin-Vector2i(1,0)
	while state["followers"].size()<threshold-1: state["followers"].append(world._agent(work.x,work.y,false))
	world.step()
	check(not card in progression["discovered"],"The card must stay hidden one follower below its source threshold")
	var builder: Dictionary=world._agent(work.x,work.y,false)
	state["followers"].append(builder)
	world.step()
	check(card in progression["discovered"] and not card in progression["completed"],"The source population must reveal the card before research")
	if failures: return
	var research: Dictionary=progression["rules"]["research_cards"][card]
	var sticker := "Sticker_Tools_1"
	var points: int=progression["rules"]["stickers"][sticker]["contributions"].get(research["research_type"],0)
	check(points>0,"The recovered card must accept the source Tech sticker")
	if failures: return
	var count:=ceili(float(research["research_needed"])/points)
	progression["inventory"][sticker]=count
	for assignment in range(count): world.step([{"type":"research_card","card":card,"sticker":sticker}])
	check(card in progression["completed"] and progression["inventory"][sticker]==0,"Completing the source card must spend the matching stickers")
	# Controlled level pad on the actual map isolates the unlocked house selection.
	for z in range(origin.y-1,origin.y+span+1):
		for x in range(origin.x-1,origin.x+span+1): state["terrain"][z*int(state["width"])+x]=raw_height-19
	state["terrain_revision"]+=1
	var plot_id:=Plots.allocate(state["source_plots"],origin.x,origin.y,span,Terrain.surface_height(raw_height))
	var plot: Dictionary=state["source_plots"]["slots"][plot_id]
	var stock: int=state["wheat"]
	var quote: int=world.source_abode_wheat_cost(plot)
	check(world.begin_promised_abode(plot,builder["id"]),"The source constructor must consume the unlocked plot")
	if failures: return
	var home: Dictionary=state["homes"].back()
	check(home["source_house"]==source_house and home["model_id"]=="lowlandrural2.group.bin:"+item[7],"Construction must use the original row and assembly")
	check(home["capacity"]==item[6] and home["span"]==span and state["wheat"]==stock-quote,"Construction must apply the native size, capacity and wheat quote")
	for tick in range(6000):
		if home["residents"]>0: break
		world.advance_promised_abode()
	check(home["residents"]>0,"A Builder must finish and occupy the new abode")


func check_old_save(world: RefCounted,source: Dictionary) -> void:
	var saved: Dictionary=world.export_state()
	var previous: Dictionary=saved["state"]["opening"]["definition"]
	previous.erase("beach_lodge")
	previous.erase("sticker_advances")
	for rank: String in ["StoneHouse_Rank_3","StoneHouse_Rank_4"]: previous["stone_abodes"].erase(rank)
	previous["housing_advances"]=previous["housing_advances"].filter(func(level: Dictionary) -> bool: return level["population"]<480)
	var restored:=World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"A previous Homeworld6 save must remain readable")
	if failures: return
	var state: Dictionary=restored._state
	var houses: Array=state["homes"].duplicate(true)
	var completed: Array=state["progression"]["completed"].duplicate()
	var session:=Session.new()
	var path:="res://../build/test-late-abodes-%d.sqlite"%OS.get_process_id()
	session.store.database_path=path
	var written: Dictionary=session.store.save_world(saved)
	var loaded:=session.load_game(path) if written.get("ok",false) else written
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(loaded.get("ok",false),"Normal campaign loading must accept a previous Homeworld6 save")
	if failures: session.free(); return
	state=session.world._state
	check(state["opening"]["definition"]["housing_advances"].size()==source["housing_advances"].size(),"The migrated save must expose all original housing milestones")
	check(state["opening"]["definition"]["sticker_advances"]==source["sticker_advances"],"The migrated save must expose the source sticker milestones")
	check(state["progression"]["completed"]==completed,"Migration must preserve completed research")
	var previous_homes:=JSON.stringify(Progression.canonical_numbers(houses),"",true,true)
	var loaded_homes:=JSON.stringify(Progression.canonical_numbers(state["homes"]),"",true,true)
	check(loaded_homes==previous_homes,"Migration must preserve built homes across the save codec")
	session.free()
