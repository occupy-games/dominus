extends SceneTree

const Motion = preload("res://simulation/source_rock_motion.gd")
const Rocks = preload("res://simulation/authored_rocks.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const World = preload("res://simulation/world.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func fixture_state(example: Dictionary,config: Dictionary) -> Dictionary:
	var state := {"width":1024,"rocks":PackedByteArray(),"rock_motion":Motion.initial(),"progression":{"rock_taps":{}},"opening":{"definition":{"rock_objects":[],"rock_motion_config":config,"object_config":{"taps_to_destroy_rock":1}}}}
	state["rocks"].resize(1024*1024)
	for item: Dictionary in example["objects"]:
		var cell := int(item["z"])*1024+int(item["x"])
		state["rocks"][cell]=6
		var first := int(item["cells"][0])
		state["opening"]["definition"]["rock_objects"].append({"cell":cell,"x":float(item["x"]),"z":float(item["z"]),"source_y":float(item["height"])-float(config["sea_height"]),"origin_x":first%1024,"origin_z":first/1024,"size_x":2,"size_z":2})
	Rocks.prepare(state["opening"]["definition"])
	return state


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_rock_motion.json"))
	var config: Dictionary=fixture["configuration"]
	for example: Dictionary in fixture["cases"]:
		var state := fixture_state(example,config)
		var objects: Array=state["opening"]["definition"]["rock_objects"]
		var cells: Array=objects.map(func(item: Dictionary) -> int: return int(item["cell"]))
		var tiles := {}
		for tile: Array in example["tiles"]: tiles[Vector2i(int(tile[0]),int(tile[1]))]=true
		for index in range(example["steps"].size()):
			var step: Dictionary=example["steps"][index]
			var target := func(_cell: int) -> float: return Terrain.surface_height(int(step["raw"]))
			if step.get("refresh",false): Motion.refresh(state,tiles,target)
			Motion.advance(state["rock_motion"],float(step["delta"]),float(config["duration"]),target,func(_cell: int) -> bool: return true)
			var expected: Dictionary=example["states"][index]
			for i in range(cells.size()):
				check(float(state["rock_motion"]["heights"].get(str(cells[i]),6.0))==float(expected["heights"][i]),"Native %s rock height at step %d must match"%[example["name"],index])
			var queue: Array=[]
			for slot: int in state["rock_motion"]["active"]:
				var record: Dictionary=state["rock_motion"]["slots"][slot]
				queue.append({"object":float(cells.find(int(record["cell"]))),"start":float(record["start"]),"elapsed":float(record["elapsed"])})
			check(queue==expected["queue"],"Native %s queue ordering, retargeting and pool reuse must match at step %d"%[example["name"],index])
			check(Motion.valid(state["rock_motion"],objects,float(config["duration"])),"All emitted native motion states must pass persistence validation")
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	# A controlled belief balance permits an ordinary vertex edit at the first
	# rock's center; the command still passes the normal influence/terrain gates.
	var saved := world.export_state()
	saved["state"]["belief"]=20
	check(world.restore(saved,RandomNumberGenerator.new()),"Source rock-motion state must restore")
	# The source influence raster expands from empty during startup.
	for tick in range(21): world.step()
	var command := {"type":"raise","x":161,"z":123,"radius":0}
	check(world.inspect(command)["ok"],"A normal permitted sculpt command must reach native rock refresh")
	world.step([command])
	var cell := 123*1024+161
	check(Rocks.alive(world._state,cell) and world.plot_obstruction(160,122)=="rock","Changing the ground must preserve the rock identity and footprint")
	check(world._state["rock_motion"]["heights"].has(str(cell)) and not world._state["rock_motion"]["active"].is_empty(),"A changed source rock must enter the original height-transition pool")
	var snapshot := world.snapshot(false)
	var height := float(snapshot["rock_motion"]["heights"][str(cell)])
	snapshot["rock_motion"]["heights"][str(cell)]=0.0
	check(float(world.snapshot(false)["rock_motion"]["heights"][str(cell)])==height,"Rendering snapshots must not mutate live rock-motion state")
	var store := Store.new()
	store.database_path="res://../build/test-rock-motion.sqlite"
	check(store.save_world(world.export_state()).get("ok",false),"An active source rock transition must save")
	var loaded := store.load_world()
	var restored := World.new()
	var restored_ok: bool=loaded.get("ok",false) and restored.restore(loaded.get("data",{}),RandomNumberGenerator.new())
	check(restored_ok,"An active source rock transition must reload")
	if not restored_ok: quit(1); return
	for tick in range(15): world.step(); restored.step()
	check(world.export_state()==restored.export_state() and world._state["rock_motion"]["active"].is_empty(),"Restored motion and source callbacks must continue identically through completion")
	var invalid := world.export_state()
	invalid["state"]["rock_motion"]["free"].append(0)
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Duplicate persisted pool slots must reject")
	invalid=world.export_state()
	invalid["state"]["rock_motion"]["heights"][str(cell)]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Non-finite persisted rock heights must reject")
	var stopped := fixture_state(fixture["cases"][1],config)
	var first_cell := int(stopped["opening"]["definition"]["rock_objects"][0]["cell"])
	Motion.request(stopped["rock_motion"],first_cell,6.0)
	stopped["progression"]["rock_taps"][str(first_cell)]=1
	Motion.advance(stopped["rock_motion"],0.1,1.0,func(_cell: int) -> float: return 6.3,func(root_cell: int) -> bool: return Rocks.alive(stopped,root_cell))
	check(stopped["rock_motion"]["active"].is_empty() and stopped["rock_motion"]["free"].size()==12,"Removing a moving rock must release its motion slot without reviving its model")
	await test_presentation(world,cell)
	print("Original rock motion: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)


func test_presentation(world: RefCounted,cell: int) -> void:
	var content := preload("res://infrastructure/game_content.gd").new()
	var stream := preload("res://presentation/world/scenery_stream.gd").new()
	stream.configure(content.scenery_assets()["rocks"],true)
	root.add_child(stream)
	stream.set_process(false)
	var snapshot: Dictionary=world.snapshot()
	var area := Rect2i(150,115,25,30)
	stream.update(snapshot,area)
	while not stream.pending.is_empty(): stream.build_tile(stream.pending.pop_front())
	check(stream.rock_instances.has(cell),"The original moving rock must remain in its source mesh batch")
	if not stream.rock_instances.has(cell): stream.queue_free(); return
	var before := float(stream.rock_instances[cell]["height"])
	var multi: MultiMesh=stream.rock_instances[cell]["multi"]
	var builds := int(stream.builds)
	snapshot=snapshot.duplicate(true)
	snapshot["rock_motion"]["heights"][str(cell)]+=0.3
	snapshot["rock_motion"]["revision"]+=1
	snapshot["terrain_revision"]+=1
	stream.update(snapshot,area)
	stream.advance_motion(0.05)
	check(absf(float(stream.rock_instances[cell]["height"])-before-0.15)<0.00001,"Source rock batches must interpolate between fixed simulation snapshots")
	stream.advance_motion(0.05)
	check(absf(float(stream.rock_instances[cell]["height"])-before-0.3)<0.00001 and stream.builds==builds and stream.rock_instances[cell]["multi"]==multi and stream.pending.is_empty(),"Moving rocks must update existing instance transforms without rebuilding terrain or scenery tiles")
	if DisplayServer.get_name()!="headless":
		var actual: Transform3D=multi.get_instance_transform(int(stream.rock_instances[cell]["index"]))
		var expected: Transform3D=stream.rock_instances[cell]["transform"]
		check(actual.is_equal_approx(expected),"The native GPU instance must receive the interpolated source transform, including its original scale and rotation")
	stream.queue_free()
	await process_frame
