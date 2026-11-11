extends SceneTree

const World = preload("res://simulation/world.gd")
const Session = preload("res://application/game_session.gd")
const Chests = preload("res://simulation/authored_chests.gd")
const Storms = preload("res://simulation/campaign_storms.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")
const Progression = preload("res://simulation/progression.gd")
var failures := 0


func _initialize() -> void:
	create_timer(100).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func action(id: String) -> Dictionary:
	return {"type":"open_chest","id":id}


func find_chest(opening: Dictionary, id: String) -> Dictionary:
	for chest: Dictionary in opening["chests"]:
		if Chests.identifier(chest)==id: return chest
	return {}


func run() -> void:
	var content := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var source: Dictionary=content.get("story",{})
	var packs: Array=source.get("authored_pack_chests",[])
	check(packs.map(func(row: Dictionary) -> int: return row["id"])==[19,28,78,85,88,93,99,104,105,123],
		"Register the ten original Homeworld6 gem pack sites")
	if failures: finish(); return
	var legacy := content.duplicate(false)
	legacy["story"]=source.duplicate(false)
	legacy["story"].erase("authored_pack_chests")
	legacy["terrain"]=content["terrain"].duplicate()
	legacy["terrain"][189*1024+179]-=1
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=628
	world.initialize({"campaign_data":legacy},random)
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	opening.merge({"phase":"discovery","discovery_step":2,"pit_step":1,"leash_step":2,"messages":[]},true)
	opening["leash_level_card"]=source["leash_population_card"]["id"]
	opening["globals"]["onStartPlayTriggered"]=true
	state["belief"]=1000
	state["progression"]["script_unlocks"]={"Expansion_2a":true,"Expansion_2b":true}
	for tick in range(60): world._advance_source_influence([])
	world.initialize_authored_chests()
	world.step()
	var opened_id := ""
	for chest: Dictionary in opening["chests"]:
		var id := Chests.identifier(chest)
		if world.inspect(action(id))["ok"]:
			opened_id=id
			break
	check(not opened_id.is_empty(),"The legacy save must have a reachable original sticker chest")
	if failures: finish(); return
	world.step([action(opened_id)])
	for tick in range(24): world.step()
	var history: Dictionary=opening["chest_history"].duplicate()
	check(history.has(opened_id.get_slice(":",1)) and find_chest(opening,opened_id).is_empty(),
		"The legacy chest must be opened and removed before migration")

	var adapter := Chests.new()
	adapter.configure(world,state,[])
	adapter.random=random
	Storms.advance(opening,true,0.1,adapter.random_word)
	adapter.spawn(opening,{"x":202.0,"z":183.0,"depth":0.0})
	var storm := find_chest(opening,"storm:1")
	check(not storm.is_empty() and int(storm["handle"])==Chests.authored_count(opening["definition"])+1,
		"A saved storm must occupy the first new authored handle")
	world.step([action("storm:1")])
	check(not storm.is_empty() and storm["core"]["source_slots"]["60"]==1,
		"Save the colliding storm while its opening animation is in progress")
	if failures: finish(); return
	var old_handle: int=storm["handle"]
	var old_core: Dictionary=storm["core"].duplicate(true)
	opening.erase("registered_sticker_chests")
	var profile := OS.get_environment("DOMINUS_SAVE_DIRECTORY")
	if profile.is_empty(): profile=OS.get_temp_dir()
	var path := profile.path_join("chest-pack-migration-%d.sqlite" % OS.get_process_id())
	var session := Session.new()
	session.world=world
	check(session.save_game(path)["ok"],"Save the previous roster with a live storm")
	var loaded := session.load_game(path)
	DirAccess.remove_absolute(path)
	check(loaded["ok"],"The normal save entry point must install the original packs. %s" % loaded.get("message",""))
	world=session.world
	session.free()
	if failures: finish(); return
	state=world._state
	opening=state["opening"]
	storm=find_chest(opening,"storm:1")
	check(int(storm.get("handle",0))>old_handle and Progression.canonical_numbers(storm.get("core"))==Progression.canonical_numbers(old_core) and opening["chest_history"]==history,
		"Migration must preserve identities, animation progress and opened chest history")
	check(Chests.valid(opening),"A save made before the new chests register must still be valid")
	world.step()
	check(opening["registered_sticker_chests"]==Chests.authored_count(opening["definition"]) and find_chest(opening,opened_id).is_empty(),
		"Registration must append the packs without recreating opened chests")
	for tick in range(24): world.step()

	var buried := find_chest(opening,"reward:28")
	var floor_: int=content["bathymetry"][189*1024+179]-3
	check(not buried.is_empty() and roundi(float(buried["core"]["base_height"])/Terrain.HEIGHT_SCALE)==floor_,
		"Use the original depth even where a saved edit already removed a layer")
	var collect := action("reward:28")
	check(not world.inspect(collect)["ok"],"A buried pack must wait for exposure")
	var player := Player.new()
	adapter.configure(world,state,[])
	for attempt in range(10):
		if world.inspect(collect)["ok"]: break
		var view: Array=adapter.snapshot().filter(func(chest: Dictionary) -> bool: return chest["id"]==collect["id"])
		if view.is_empty(): break
		var edit := player.excavate_chest(world,view[0])
		if edit.is_empty(): break
		world.step([edit])
	check(world.inspect(collect)["ok"],"Real terrain drags must uncover the original pack")
	if failures: finish(); return
	var gems: int=state["gems"]
	var stock: int=state["progression"]["inventory"].get("Sticker_Gem_1",0)
	world.step([collect,collect])
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Reload a pack in the middle of opening")
	var grants: Array=[]
	for tick in range(24):
		for event: Dictionary in world.step():
			if event["type"]=="chest_opened" and event["id"]==collect["id"]: grants.append(event["reward"])
		restored.step()
	check(grants==[{"gems":5}] and state["gems"]==gems+5 and state["progression"]["inventory"].get("Sticker_Gem_1",0)==stock,
		"The native five-slot pack must credit five gems once to the wallet")
	check(find_chest(opening,"reward:28").is_empty() and not world.inspect(collect)["ok"] and opening["chest_history"].get("28")==2,
		"A redeemed pack must disappear without being claimable again")
	check(restored._state["gems"]==state["gems"] and restored._state["opening"]["chest_history"]==opening["chest_history"],
		"Restored opening must credit the same pack exactly once")
	finish()


func finish() -> void:
	print("Homeworld6 authored chest packs: ",failures," failures")
	quit(1 if failures else 0)
