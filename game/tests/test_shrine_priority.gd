extends SceneTree

const World = preload("res://simulation/world.gd")
const Temple = preload("res://simulation/temple_rules.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func definition() -> Dictionary:
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	data["tree_field"].resize(64*64)
	data["followers"]=[{"x":14,"z":18},{"x":14,"z":19}]
	data["automatic_settlement"]=true
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-sites.json"))
	var beacon := {}
	for site: Dictionary in preload("res://infrastructure/temple_sites.gd").sites("initialworldsetup6",manifest["source_sha256"]):
		if site["id"]=="1012": beacon=site.duplicate(true); break
	beacon.merge({"x":18,"z":18,"source_height":23,"food_cost":3,"ore_cost":2,"build_ticks":100},true)
	data["progression_rules"]["shrines"]=[beacon]
	return data


func create(data: Dictionary,wheat: int=3,ore: int=2) -> RefCounted:
	var world := World.new()
	var rng := RandomNumberGenerator.new(); rng.seed=1012
	world.initialize({"campaign_data":data},rng)
	var saved: Dictionary=world.export_state()
	saved["state"]["wheat"]=wheat; saved["state"]["ore"]=ore
	check(world.restore(saved,RandomNumberGenerator.new()),"The starting resource boundary must restore")
	return world


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var data := definition()
	var world := create(data)
	var site: Dictionary=world._state["progression"]["shrines"][0]
	var region := Temple.footprint(site)
	check(region.size.x>=4 and region.size.y>=4,"The original shrine dimensions must reserve its full model footprint")
	check(not world.inspect({"type":"home","x":region.position.x,"z":region.position.y,"rank":1})["ok"],"Homes cannot be built over an unrepaired shrine")
	check(not world.inspect({"type":"home","x":region.position.x-1,"z":region.position.y,"rank":1})["ok"],"Homes must leave a usable builder approach beside the shrine")
	for tick in range(30): world.step()
	check(world._state["homes"].size()==1 and world._state["homes"][0].get("kind")=="shrine","Idle builders must start the affordable shrine before any new houses")
	check(world._state["followers"].all(func(f: Dictionary) -> bool: return f["job"]!=-1),"Available builders must fill the shrine's source worker slots")
	check(world._state["wheat"]==0 and world._state["ore"]==0,"Automatic repair pays the authored costs exactly once")
	var saved: Dictionary=world.export_state()
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"The automatically selected job must save/load")
	for tick in range(150): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Worker priorities and queued repair commands must continue deterministically")
	check(world._state["progression"]["shrines"][0]["complete"],"The assigned builders must finish the original shrine job")
	check(world._state["wheat"]==0 and world._state["ore"]==0,"Subsequent decisions cannot repay or repeat a completed shrine")
	var blocked_data := definition()
	blocked_data["terrain"][18*64+18]=5
	var buried := create(blocked_data)
	check(not buried.inspect({"type":"repair_shrine","id":"1012"})["ok"],"Terrain above the source shrine elevation must prevent repair")
	for tick in range(30): buried.step()
	check(not buried._state["progression"]["shrines"][0]["started"],"Buried shrines cannot silently take builders or resources")
	check(buried._state["wheat"]==3 and buried._state["ore"]==2,"A blocked automatic job cannot charge resources")
	var poor := create(definition(),3,1)
	for tick in range(30): poor.step()
	check(not poor._state["progression"]["shrines"][0]["started"] and poor._state["ore"]==1,"Unaffordable shrines must wait without charging or trapping builders")
	var tree_data := definition()
	tree_data["tree_field"][18*64+18]=1
	var wooded := create(tree_data)
	var obstructed: Dictionary=wooded.inspect({"type":"repair_shrine","id":"1012"})
	check(not obstructed["ok"] and obstructed.get("obstruction",{}).get("kind")=="tree","A covering tree must be identified before assigning repair")
	for tap in range(int(tree_data["progression_rules"]["vegetation"]["taps_to_clear"])): wooded.step([{"type":"tap_tree","cell":18*64+18}])
	for tick in range(30): wooded.step()
	check(wooded._state["progression"]["shrines"][0]["started"],"Clearing the tree must let builders select the shrine without an extra repair click")
	# Existing repairs retain their paid costs and progress when their former
	# two-cell occupancy is migrated to the recovered dimensions.
	var legacy: Dictionary=saved.duplicate(true)
	legacy["state"]["homes"][0]["x"]=18; legacy["state"]["homes"][0]["z"]=18; legacy["state"]["homes"][0]["span"]=2
	legacy["state"]["progression"]["rules"]["version"]=11
	var migration := World.new()
	check(migration.restore(legacy,RandomNumberGenerator.new()),"An older small-footprint repair must remain readable")
	var progress: float=migration._state["homes"][0]["temple_work"]
	migration.migrate_progression(data["progression_rules"],data["rock_field"])
	check(migration._state["homes"][0]["x"]==region.position.x and migration._state["homes"][0]["span"]==maxi(region.size.x,region.size.y),"Migration must correct the actual repair occupancy")
	check(migration._state["homes"][0]["temple_work"]==progress and migration._state["wheat"]==0 and migration._state["ore"]==0,"Footprint migration must preserve existing work and prior payment")
	print("Shrine repair priority, full footprints, clearance and saved jobs: %d failures"%failures)
	quit(1 if failures else 0)
