extends SceneTree

const Response = preload("res://simulation/source_tree_response.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const TreeAnimation = preload("res://presentation/world/source_tree_animation.gd")
const World = preload("res://simulation/world.gd")
var failures := 0


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_tree_response.json"))
	var config: Dictionary=fixture["configuration"]
	for example: Dictionary in fixture["cases"]:
		var state := {"trees":[],"removed_trees":{},"tree_response":Response.initial(),"opening":{"definition":{"tree_response_config":config}}}
		var rows := {}
		var tree_tiles := {}
		var tiles := {}
		for tile: Array in example["tiles"]: tiles[Vector2i(int(tile[0]),int(tile[1]))]=true
		for item: Dictionary in example["objects"]:
			var cell := int(item["cells"][0])
			rows[cell]=state["trees"].size()
			state["trees"].append({"cell":cell,"source_y":float(item["height"])-float(config["sea_height"]),"x":float(item["x"]),"z":float(item["z"])})
			var tile := Vector2i((cell%1024)/32,(cell/1024)/32)
			if not tree_tiles.has(tile): tree_tiles[tile]=[]
			tree_tiles[tile].append(cell)
		for i in range(example["steps"].size()):
			var step: Dictionary=example["steps"][i]
			if step["refresh"]: Response.refresh(state,tiles,tree_tiles,rows,func(_tree: Dictionary) -> float: return Terrain.surface_height(int(step["raw"])),float(step["now"]))
			for j in range(state["trees"].size()):
				var key := str(int(state["trees"][j]["cell"]))
				var actual: Dictionary=state["tree_response"]["entries"].get(key,{"enabled":true,"changed_ms":0.0})
				var expected: Dictionary=example["states"][i][j]
				check(actual["enabled"]==expected["enabled"] and float(actual["changed_ms"])==float(expected["changed_ms"]),"Native %s activation and timestamp at step %d must match"%[example["name"],i])
				var size := TreeAnimation.scale_at(config,actual["enabled"],float(step["now"]),float(actual["changed_ms"]))
				check(absf(size-float(expected["scale"]))<0.000001,"Native %s tree appearance at step %d must match"%[example["name"],i])
	for item: Dictionary in fixture["scale_cases"]:
		var actual := TreeAnimation.scale_at(config,item["enabled"],float(item["now"]),float(item["changed_ms"]),float(item["base"]),float(item["encouragement"]))
		check(absf(actual-float(item["scale"]))<0.000001,"Original tree scale must match native enabled/time/base/encouragement inputs: %s"%item)
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	# Controlled resources and observer progression; terrain edits still go
	# through the same validated ordinary commands as interactive sculpting.
	var saved := world.export_state()
	saved["state"]["belief"]=100
	check(world.restore(saved,RandomNumberGenerator.new()),"Initial tree response state must restore")
	# Source desktop influence starts empty and expands over the first two
	# seconds. Probe ordinary actionable trees after that real expansion.
	for tick in range(21): world.step()
	var selected := {}
	var command := {}
	for tree: Dictionary in world._state["trees"]:
		var cell := int(tree["cell"])
		var proposed := {"type":"raise","x":cell%1024,"z":cell/1024,"radius":0}
		if not world.inspect(proposed)["ok"]: continue
		var before := world.source_tree_target(tree)
		var vertex := func(x: int,z: int) -> int: return world.source_raw_height_at(x,z)+(1 if z*1024+x==cell else 0)
		var hypothetical := Terrain.surface_height(Terrain.raw_at(vertex,1024,float(tree["x"]),float(tree["z"])))
		if hypothetical==before: continue
		selected=tree
		command=proposed
		break
	check(not selected.is_empty(),"An actionable tree must respond to an ordinary sculpt edit")
	if selected.is_empty(): quit(1); return
	var cell := int(selected["cell"])
	var key := str(cell)
	check(world.tree_at(cell%1024,cell/1024) and world.query_copy().tree_at(cell%1024,cell/1024),"Live and detached initial occupancy must match")
	check(not world.tree_at(cell%1024+1024,cell/1024-1),"Out-of-map coordinates must not alias another row's tree identity")
	world.step([command])
	check(not world.tree_at(cell%1024,cell/1024) and not world.query_copy().tree_at(cell%1024,cell/1024),"Sculpting must release the native tree footprint without a clearing reward")
	check(not world._state["removed_trees"].has(key),"Terrain suppression must remain distinct from permanent player clearing")
	var legacy := world.export_state()
	legacy["state"].erase("tree_response")
	var migrated := World.new()
	check(migrated.restore(legacy,RandomNumberGenerator.new()) and not migrated.tree_at(cell%1024,cell/1024),"Missing transition state must derive native occupancy from the saved sculpted ground")
	var snap := world.snapshot()
	snap["tree_response"]["entries"][key]["enabled"]=true
	check(not world.tree_at(cell%1024,cell/1024),"A detached visual snapshot must not change authoritative tree occupancy")
	var store := preload("res://infrastructure/world_store.gd").new()
	store.database_path=preload("res://infrastructure/save_paths.gd").directory().path_join("test-tree-response.sqlite")
	check(store.save_world(world.export_state()).get("ok",false),"Suppressed trees must save")
	var restored := World.new()
	check(restored.restore(store.load_world().get("data",{}),RandomNumberGenerator.new()),"Suppressed trees must reload")
	var lower := command.duplicate()
	lower["type"]="lower"
	check(world.inspect(lower)["ok"],"Restoring the planted terrain must use an ordinary sculpt command")
	world.step([lower]); restored.step([lower])
	check(world.tree_at(cell%1024,cell/1024) and world.export_state()==restored.export_state(),"The planted height must restore occupancy and deterministic save continuation")
	var invalid := world.export_state()
	invalid["state"]["tree_response"]["entries"][key]["changed_ms"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Non-finite tree transition timestamps must reject")
	invalid=world.export_state()
	invalid["state"]["tree_response"]["entries"]["-1"]={"enabled":true,"changed_ms":0.0}
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Unknown tree identities must reject")
	await presentation(world,cell)
	print("Original tree response: %d terrain cases, %d scale cases, %d failures"%[fixture["cases"].size(),fixture["scale_cases"].size(),failures])
	quit(1 if failures else 0)


func presentation(world: RefCounted,cell: int) -> void:
	var content := preload("res://infrastructure/game_content.gd").new()
	var stream := preload("res://presentation/world/scenery_stream.gd").new()
	stream.configure(content.scenery_assets()["trees"],false)
	root.add_child(stream)
	stream.set_process(false)
	var area := Rect2i(cell%1024-8,cell/1024-8,16,16)
	var snapshot: Dictionary = world.snapshot()
	stream.update(snapshot,area)
	while not stream.pending.is_empty(): stream.build_tile(stream.pending.pop_front())
	check(stream.tree_instances.has(cell),"The source tree must have a reusable original mesh instance")
	if not stream.tree_instances.has(cell): stream.queue_free(); return
	var original: Transform3D=stream.tree_instances[cell]["base"]
	var multi: MultiMesh=stream.tree_instances[cell]["multi"]
	var builds := int(stream.builds)
	snapshot["tree_response"]["entries"][str(cell)]={"enabled":false,"changed_ms":snapshot["tick"]*100.0}
	snapshot["tree_response"]["revision"]+=1
	snapshot["terrain_revision"]+=1
	stream.update(snapshot,area)
	check(stream.tree_instances[cell]["scale"]==0.0 and stream.pending.is_empty() and stream.builds==builds,"Terrain-suppressed trees must disappear without rebuilding the forest")
	snapshot=snapshot.duplicate(true)
	snapshot["tree_response"]["entries"][str(cell)]["enabled"]=true
	snapshot["tree_response"]["revision"]+=1
	stream.update(snapshot,area)
	stream.advance_trees(0.05)
	check(stream.tree_instances[cell]["scale"]>1.0 and stream.tree_instances[cell]["base"]==original and stream.tree_instances[cell]["multi"]==multi,"Re-enabled tree size must follow the native curve while remaining anchored to its planted height")
	if DisplayServer.get_name()!="headless":
		check(multi.get_instance_transform(int(stream.tree_instances[cell]["index"])).is_equal_approx(stream.tree_instances[cell]["transform"]),"The GPU must receive the source tree's actual animated transform")
	stream.set_pixel_density(5.0)
	stream.update(snapshot,area)
	while not stream.pending.is_empty(): stream.build_tile(stream.pending.pop_front())
	var sprite: Dictionary=stream.tree_instances[cell]
	check(sprite["multi"].use_custom_data,"Distant source trees must retain their original atlas sprite")
	var sprite_base: Transform3D=sprite["base"]
	check(absf(sprite_base.origin.y-float(sprite["center"])-original.origin.y)<0.00001,"Imposter centers must preserve the original planted ground height")
	builds=stream.builds
	snapshot=snapshot.duplicate(true)
	snapshot["tree_response"]["entries"][str(cell)]["enabled"]=false
	snapshot["tree_response"]["revision"]+=1
	stream.update(snapshot,area)
	check(stream.tree_instances[cell]["scale"]==0.0 and stream.builds==builds and stream.pending.is_empty(),"Distant sprites must disappear through instance updates without rebuilding the forest")
	if DisplayServer.get_name()!="headless":
		check(sprite["multi"].get_instance_transform(int(sprite["index"])).is_equal_approx(sprite["transform"]),"The GPU must receive the disabled original imposter transform")
	stream.queue_free()
	await process_frame
