extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var app: Variant=load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	if "--population" in OS.get_cmdline_user_args():
		var loaded: Dictionary=app.session.load_game("res://../build/navigation-population.sqlite3")
		if not loaded.get("ok",false): push_error(str(loaded)); quit(1); return
		app.show_game(false)
	print("Profile population: ",app.session.presentation_snapshot()["followers"].size())
	root.title="Dominus navigation verification"
	DisplayServer.window_move_to_foreground()
	root.grab_focus()
	if "--scale-half" in OS.get_cmdline_user_args(): root.scaling_3d_scale=0.5
	RenderingServer.set_render_loop_enabled(false)
	# Keep actual fixed-tick simulation active while moving the camera.
	var view: Variant=app.screen.world_view
	for span: float in [8.0,30.0,150.0,500.0]:
		view.zoom=span
		view.update_camera()
		var frames: Array[float]=[]
		var updates: Array[float]=[]
		var draws: Array[float]=[]
		var scenes: Array[float]=[]
		var previous := Time.get_ticks_usec()
		for frame in range(180):
			var start := Time.get_ticks_usec()
			view.trackpad_pan(Vector2(1.2,0.6),frame%120>60)

			updates.append((Time.get_ticks_usec()-start)/1000.0)
			var draw_start := Time.get_ticks_usec()
			RenderingServer.force_draw(true)
			var draw_end := Time.get_ticks_usec()
			await process_frame
			if frame>20:
				draws.append((draw_end-draw_start)/1000.0)
				scenes.append((Time.get_ticks_usec()-draw_end)/1000.0)
			var now := Time.get_ticks_usec()
			if frame>20: frames.append((now-previous)/1000.0)
			previous=now
		frames.sort(); updates.sort(); draws.sort(); scenes.sort()
		print("BREAKDOWN draw median=",draws[draws.size()/2]," p95=",draws[int(draws.size()*.95)]," scene median=",scenes[scenes.size()/2]," p95=",scenes[int(scenes.size()*.95)])
		print("Explicit rendered frames: 180")
		print("COST terrain=",triangles(view.terrain)," trees=",triangles(view.trees)," rocks=",triangles(view.rocks)," scene builds ms=",view.trees.max_build_usec/1000.0,"/",view.rocks.max_build_usec/1000.0)
		print("PROFILE span=",span," frame median=",frames[frames.size()/2]," p95=",frames[int(frames.size()*0.95)]," max=",frames.back()," input+tick max=",updates.back()," tiles=",view.terrain.chunks.size()," objects=",Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png("res://../build/screenshots/navigation-far-current.png")
	RenderingServer.set_render_loop_enabled(true)
	app.queue_free()
	await process_frame
	quit()

func triangles(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh!=null:
		for surface in range(node.mesh.get_surface_count()): count+=maxi(node.mesh.surface_get_array_len(surface),node.mesh.surface_get_array_index_len(surface))/3
	if node is MultiMeshInstance3D and node.multimesh!=null:
		if node.multimesh.mesh is QuadMesh: count+=node.multimesh.instance_count*2
		else:
			for surface in range(node.multimesh.mesh.get_surface_count()): count+=node.multimesh.instance_count*maxi(node.multimesh.mesh.surface_get_array_len(surface),node.multimesh.mesh.surface_get_array_index_len(surface))/3
	for child: Node in node.get_children():
		if not child is Node3D or child.is_visible_in_tree(): count+=triangles(child)
	return count
