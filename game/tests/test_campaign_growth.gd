extends SceneTree

const World = preload("res://simulation/world.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
const Player = preload("res://simulation/campaign_player.gd")
var failures := 0


func _initialize() -> void:
	create_timer(300).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func run() -> void:
	var definition := Content.homeworld()
	check(definition.get("width") == 1024,"Campaign must recover the complete original map")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	world.initialize({"campaign_data":definition},random)
	var initial := world.snapshot(false)
	check(initial["followers"].size()==2 and initial["followers"][0]["x"]==175 and initial["followers"][0]["z"]==166,"Campaign must use original player starts")
	check(initial["belief"]==75 and initial["build_ticks"]==200,"Opening balance must use supplied configuration and Shelter row")
	check(world.height_at(175,166)==1,"Original waterline must map height 20 to the first dry terrace")
	var player := Player.new()
	var commands: Array = []
	var state := initial
	for tick in range(18000):
		if tick%10==0: commands = player.commands(world)
		else: commands = []
		world.step(commands)
		if tick%1000==0:
			state = world.snapshot(false)
			print("Campaign tick %d: %d followers, %d homes, %d sculpts, %d belief" % [tick,state["followers"].size(),state["homes"].size(),state["sculpted"],state["belief"]])
			await process_frame
			if state["followers"].size()>64: break
	state = world.snapshot(false)
	check(state["followers"].size()>64 and "Card_MaxRank_2" in state["progression"]["completed"],"Original campaign self-play must grow past 50 followers")
	check(player.sculpted_inward and state["sculpted"]>=2,"Self-play must perform influence-constrained layer edits")
	check(state["progression"]["player_level"]>=3 and not state["won"],"The source map must expand through its real thresholds without the former invented victory")
	if "--profile-save" in OS.get_cmdline_user_args():
		var store := preload("res://infrastructure/world_store.gd").new()
		store.database_path="res://../build/navigation-population.sqlite3"
		check(store.save_world(world.export_state())["ok"],"Prepare population profile from an ordinary-command playthrough")
	var exported := world.export_state()
	var restored := World.new()
	check(restored.restore(exported,RandomNumberGenerator.new()),"Original-map campaign must restore")
	world.step()
	restored.step()
	if world.snapshot(false)!=restored.snapshot(false): report_difference(world.snapshot(false),restored.snapshot(false),"state")
	check(world.snapshot(false)==restored.snapshot(false),"Campaign save continuation must remain deterministic")
	print("Original Homeworld extended self-play: %d failures" % failures)
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
