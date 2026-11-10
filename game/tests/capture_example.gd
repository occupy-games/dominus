extends SceneTree
## Reproducible native render fixture for example-world inspection.


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_example()
	var id := "tents.group.bin:dff1563f"
	if "--assembly-review" in OS.get_cmdline_user_args(): id = "mudhut.group.bin:dff1563f"
	if "--water" in OS.get_cmdline_user_args():
		for descriptor: Dictionary in app.catalog.models:
			if descriptor["source"] == "boats.group.bin" and descriptor.has("motion"):
				id = descriptor["id"]
				break
	app.screen.select_model(id)
	if not "--water" in OS.get_cmdline_user_args():
		app.screen.frame_family(app.screen.by_id[id])
	if "--assembly-review" in OS.get_cmdline_user_args():
		app.screen.select_model(id)
		var player: Variant = app.screen.preview
		player.playing = false
		for i in range(30): await process_frame
		for fraction in [0.0,0.5,1.0]:
			player.seek_to(player.duration * fraction)
			player.update_controls()
			print("Capture stage: ", player.active_stage, " ", player.time_label.text)
			await create_timer(0.2).timeout
			for i in range(3): await process_frame
			await RenderingServer.frame_post_draw
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../build/screenshots/whole-building-%d.png" % int(fraction*100))
		print("Native whole-building lifecycle captured")
		app.queue_free()
		await process_frame
		quit()
	if "--capture-overview" in OS.get_cmdline_user_args():
		var started := Time.get_ticks_msec()
		app.screen.overview()
		app.screen.queue_neighborhood()
		while not app.screen.queue.is_empty(): await process_frame
		await process_frame
		await process_frame
		var path := "res://../build/screenshots/example-world-overview.png"
		root.get_texture().get_image().save_png(path)
		print("Native example overview: %d source models rendered in %d ms" % [app.screen.nodes.size(), Time.get_ticks_msec() - started])
		app.queue_free()
		await process_frame
		quit()
