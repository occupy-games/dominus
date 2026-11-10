extends SceneTree
var failures := 0
func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message); failures+=1
func run() -> void:
	var app: Variant=load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	var state: Dictionary=app.session.presentation_snapshot().duplicate(true)
	var house: Dictionary=app.session.world.house_spec(1)
	state["homes"]=[]
	for index in range(4):
		state["homes"].append({"id":100+index,"x":175+index*3,"z":166,"model_id":house["model_id"],"span":house["span"],"build_ticks":house["build_ticks"],"progress":house["build_ticks"] if index<3 else 1,"stored":0,"stalled":false})
	app.screen.apply_snapshot(state)
	var view: Variant=app.screen.world_view
	await process_frame
	var source_parts := 0
	for component: Dictionary in view.home_nodes[100].components:
		if component["node"].visible: source_parts+=1
	var batch_instances := 0
	for batch: MultiMeshInstance3D in view.building_batches.get_children(): batch_instances+=batch.multimesh.instance_count
	check(batch_instances==source_parts*3,"Every completed source component must render once per completed building")
	check(not view.home_nodes[100].visible and view.home_nodes[103].visible,"Completed buildings must batch while construction keeps its whole original lifecycle")
	check(view.building_batches.get_child_count()==source_parts,"Identical buildings must share source-component draw calls")
	var builds: int=view.building_batches.builds
	app.screen.apply_snapshot(state)
	check(view.building_batches.builds==builds,"Unchanged buildings must reuse their rendering batches")
	var source_field: Dictionary = state["progression"]["rules"]["economy"]["plots"]["farm:1"]
	for index in range(2):
		var field := source_field.duplicate(true)
		field.merge({"id":200+index,"x":175+index*5,"z":173,"progress":source_field["build_ticks"],"stored":0,"stalled":false,"harvest_accumulator":0.2 if index==0 else 0.8},true)
		state["homes"].append(field)
	app.screen.apply_snapshot(state)
	await process_frame
	builds=view.building_batches.builds
	check(view.building_batches.crop_bindings.has(200) and view.building_batches.crop_bindings.has(201),"Original crop components must participate in the shared building batches")
	for id: int in [200,201]:
		for binding: Dictionary in view.building_batches.crop_bindings.get(id,[]):
			check(binding["multi"].use_custom_data,"Crop batches must allocate per-field growth data")
			# The dummy headless renderer returns zero for GPU instance reads.
			if DisplayServer.get_name()!="headless":
				var value: Color = binding["multi"].get_instance_custom_data(binding["index"])
				check(absf(value.r-(0.2 if id==200 else 0.8))<0.01,"Each field must retain its own ripeness in the shared source crop shader")
	state["homes"][4]["harvest_accumulator"]=0.6
	app.screen.apply_snapshot(state)
	check(view.building_batches.builds==builds,"Crop growth must update instance data without rebuilding source mesh batches")
	for binding: Dictionary in view.building_batches.crop_bindings.get(200,[]):
		if DisplayServer.get_name()!="headless": check(absf(binding["multi"].get_instance_custom_data(binding["index"]).r-0.6)<0.01,"Harvest growth must reach the existing GPU instance")
	var worker: Dictionary = app.catalog.worker_data("farmer")
	check(worker.get("attachments",[]).size()==3 and worker["clips"].has("farming") and worker["clips"].has("carrying"),"Original farmers need their body, profession parts, sickle, wheat and source work/carry clips")
	var original := preload("res://presentation/world/original_follower.gd")
	var first_worker := original.new()
	first_worker.assets=worker
	first_worker.variant=1
	root.add_child(first_worker)
	var mesh_count: int=original.mesh_cache.size()
	var second_worker := original.new()
	second_worker.assets=worker
	second_worker.variant=97
	root.add_child(second_worker)
	check(original.mesh_cache.size()==mesh_count,"Different followers must share source body and tool meshes rather than cache one mesh per follower ID")
	first_worker.queue_free()
	second_worker.queue_free()
	# Keep the camera's per-frame density update from replacing the test's
	# explicit distant density while the independent scenery streamer drains.
	view.set_process(false)
	view.trees.set_pixel_density(5)
	view.update_trees()
	while not view.trees.pending.is_empty(): await process_frame
	await process_frame # Retire old tile nodes queued during the final rebuild.
	var instances := 0
	for tile: Node3D in view.trees.get_children():
		if not tile.visible: continue
		check(tile.get_child_count()<=1,"Distant original sprites must share one batch per scenery tile")
		for batch: MultiMeshInstance3D in tile.get_children():
			instances+=batch.multimesh.instance_count
			check(batch.multimesh.use_custom_data and batch.material_override.get_shader_parameter("source_texture").resource_path.ends_with("pack_treeImposters_v2.png"),"Distant trees must use the original atlas and recovered rectangles")
	check(instances>0,"Source distant-tree sprites must remain present")
	var cleared_cell := -1
	for tree: Dictionary in state["trees"]:
		var cell: int = int(tree["z"])*int(state["width"])+int(tree["x"])
		var key := Vector2i(int(tree["x"])/64,int(tree["z"])/64)
		if view.trees.wanted.has(key) and not view.trees.blocked.has(cell) and int(state["terrain"][cell])>0:
			cleared_cell=cell
			break
	check(cleared_cell>=0,"A visible source tree must be available for clearing verification")
	if cleared_cell>=0:
		state["removed_trees"]={str(cleared_cell):true}
		state["vegetation_revision"]=int(state.get("vegetation_revision",0))+1
		app.screen.apply_snapshot(state)
		check(view.trees.pending.size()<=1,"Clearing one tree must rebuild only its scenery tile")
		while not view.trees.pending.is_empty(): await process_frame
		await process_frame
		var after := 0
		for tile: Node3D in view.trees.get_children():
			if tile.visible:
				for batch: MultiMeshInstance3D in tile.get_children(): after+=batch.multimesh.instance_count
		check(after==instances-1,"Clearing must remove exactly the selected source tree from rendered batches")
	app.queue_free()
	await process_frame
	print("Source building and scenery batches: %d failures" % failures)
	quit(1 if failures else 0)
