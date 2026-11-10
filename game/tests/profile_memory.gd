extends SceneTree

var records: Array = []


func _initialize() -> void:
	run.call_deferred()


func sample(stage: String, elapsed: float = 0.0) -> void:
	var data := {"stage":stage,"static_bytes":OS.get_static_memory_usage(),"peak_bytes":OS.get_static_memory_peak_usage(),"elapsed_ms":elapsed,"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
	data["live_card_images"] = preload("res://infrastructure/current_card_content.gd").live_image_count()
	records.append(data)
	print(JSON.stringify(data))


func run() -> void:
	var started := Time.get_ticks_usec()
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	sample("menu", (Time.get_ticks_usec()-started)/1000.0)
	started = Time.get_ticks_usec()
	app.show_campaign()
	app.session.set_process(false)
	await process_frame
	sample("campaign", (Time.get_ticks_usec()-started)/1000.0)
	var loaded: Dictionary = app.session.load_game("res://../build/navigation-population.sqlite3")
	if not loaded.get("ok",false): push_error(str(loaded)); quit(1); return
	app.show_game(false)
	app.session.set_process(false)
	started = Time.get_ticks_usec()
	for index in range(60):
		var snapshot: Dictionary = app.session.world.snapshot(false)
		var query: RefCounted = app.session.world.query_copy()
		if snapshot.is_empty() or query == null: quit(1); return
	sample("60_snapshot_query_pairs", (Time.get_ticks_usec()-started)/1000.0)
	started = Time.get_ticks_usec()
	for index in range(60): app.session.advance_elapsed(0.1)
	sample("60_populated_ticks", (Time.get_ticks_usec()-started)/1000.0)
	app.screen.progression_panel.open_book()
	await process_frame
	sample("card_gallery")
	app.screen.progression_panel.hide()
	app.screen.powers_panel.open_book()
	await process_frame
	sample("powers_gallery")
	app.screen.powers_panel.hide()
	await process_frame
	sample("galleries_closed")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE)
			file.store_string(JSON.stringify(records,"\t"))
	app.queue_free()
	await process_frame
	quit()
