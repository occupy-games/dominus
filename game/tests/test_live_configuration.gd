extends SceneTree
const Content=preload("res://infrastructure/campaign_content.gd")
const World=preload("res://simulation/world.gd")
const Settings=preload("res://infrastructure/settings_store.gd")
const Constants=preload("res://infrastructure/live_constants.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message); failures+=1
func run() -> void:
	var settings := Settings.new()
	settings.path="res://../build/test-settings.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	settings.read()
	check(settings.values["camera.pinch_sensitivity"]==0.1,"Trackpad default")
	check(settings.change("camera.pinch_sensitivity",0.25)["ok"],"Write JSON preference")
	settings.read()
	check(settings.values["camera.pinch_sensitivity"]==0.25,"Read JSON preference")
	check(not settings.change("camera.pinch_sensitivity",-1)["ok"],"Reject invalid setting")
	settings.reset("camera")
	check(settings.values["camera.pinch_sensitivity"]==0.1,"Reset group defaults")
	var content := Content.homeworld()
	var csv := Constants.new()
	csv.path="res://../build/test-constants.csv"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(csv.path))
	csv.initialize(content["progression_rules"])
	check(csv.definitions.size()>200,"Hundreds of source constants must be available")
	print("Editable constants: ",csv.definitions.size())
	check(csv.ensure_file()["ok"],"Create editable CSV")
	var parsed := csv.read()
	check(parsed["ok"] and parsed["count"]>csv.definitions.size()+100,"Read full CSV")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":content},random)
	var before := world.export_state()
	var applied := world.reconfigure(parsed["changes"])
	print("Full CSV: ",applied)
	check(applied["ok"],"Apply full CSV")
	check(world.snapshot(false)["tick"]==0 and before["rng_state"]==world.export_state()["rng_state"],"Reload must not advance time or RNG")
	var unchanged := world.export_state()
	check(not world.reconfigure([{"category":"runtime","key":"birth_rate","value":0}])["ok"] and unchanged==world.export_state(),"Reject constants atomically")
	var file := FileAccess.open(csv.path,FileAccess.WRITE)
	file.store_string("Name;Value\nRuntime.birth_rate;2,5\nRuntime.build_rate;3\n")
	file.close()
	check(csv.ensure_file()["ok"] and csv.read()["changes"][0]["value"]==2.5,"Preserve OpenOffice semicolon and decimal-comma edits")
	check(world.reconfigure(csv.read()["changes"])["ok"] and world.runtime_value("birth_rate",1)==2.5,"Reload running simulation")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Save live constants")
	world.step(); restored.step()
	if world.snapshot(false)!=restored.snapshot(false): report_difference(world.snapshot(false),restored.snapshot(false),"state")
	check(world.snapshot(false)==restored.snapshot(false),"Live constants deterministic continuation")
	# A controlled broad flat plot isolates growth and route decisions from
	# the original map's finite starting terrace. No player assets are replaced.
	var fixture := world.export_state()
	var state: Dictionary = fixture["state"]
	state["trees"]=[]
	state["rocks"]=PackedByteArray()
	state["rocks"].resize(1024*1024)
	for z in range(110,231):
		for x in range(110,231): state["terrain"][z*1024+x]=1
	state["progression"]["rules"]["influence_areas"]=[{"x":175,"z":166,"radius":60,"unlock":"always","force":true}]
	state["progression"]["influence_enabled"]=false
	state["runtime"]={"birth_rate":20,"build_rate":20,"home_search_radius":8}
	check(world.restore(fixture,RandomNumberGenerator.new()),"Restore growth fixture")
	for tick in range(6000):
		world.step()
		if tick%500==0:
			var current := world.snapshot(false)
			print("Growth tick ",tick,": ",current["followers"].size()," followers, ",current["homes"].size()," homes")
			await process_frame
			if current["followers"].size()>64 and current["homes"].size()>24: break
	var grown := world.snapshot(false)
	check(grown["followers"].size()>64 and grown["homes"].size()>24 and not grown["won"],"Campaign must continue building and birthing beyond 50 followers")
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Save growing campaign beyond former cap")
	for tick in range(20): world.step(); restored.step()
	check(world.snapshot(false)==restored.snapshot(false),"Continued growth deterministic after restore")
	var session := preload("res://application/game_session.gd").new()
	session.world=world
	var saved_path := "res://../build/test-live-config.sqlite3"
	check(session.save_game(saved_path)["ok"],"Named save must persist growing campaign and constants")
	var saved := session.world.export_state()
	check(not session.load_game("res://../build/missing-config-save.sqlite3")["ok"] and saved==session.world.export_state(),"A failed load must preserve the current game")
	var loaded := session.load_game(saved_path)
	print("Named load: ",loaded)
	if loaded.get("ok",false) and saved!=session.world.export_state(): report_difference(saved,session.world.export_state(),"saved")
	check(loaded["ok"] and saved==session.world.export_state(),"Named saved game must restore all authoritative data")
	session.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(csv.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	print("Settings, live balance and continued growth: %d failures" % failures)
	quit(1 if failures else 0)


func report_difference(a: Variant,b: Variant,path: String) -> bool:
	if typeof(a)!=typeof(b):
		print("Different types at ",path,": ",typeof(a)," / ",typeof(b))
		return true
	if a is Dictionary:
		for key: Variant in a:
			if not b.has(key): print("Missing key ",path,"/",key); return true
			if report_difference(a[key],b[key],path+"/"+str(key)): return true
	elif a is Array:
		if a.size()!=b.size(): print("Different lengths ",path); return true
		for index in range(a.size()):
			if report_difference(a[index],b[index],path+"/"+str(index)): return true
	elif a!=b:
		print("Different values at ",path,": ",a," / ",b)
		return true
	return false
