extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func capture(path: String) -> void:
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	for step in range(48): app.session.advance_elapsed(0.5)
	var snapshot: Dictionary = app.session.presentation_snapshot().duplicate(true)
	# Detached presentation fixture: show the three supported opening cards.
	for id: String in ["Card_MaxRank_2", "Card_DoubleClick", "Card_AbodeType_2"]:
		if not id in snapshot["progression"]["discovered"]: snapshot["progression"]["discovered"].append(id)
	app.screen.apply_snapshot(snapshot)
	for frame in range(75): await process_frame
	await capture("res://../build/screenshots/original-hud-corrected.png")
	app.screen.progression_panel.open_card("Card_DoubleClick")
	await capture("res://../build/screenshots/original-portrait-card-detail.png")
	app.queue_free()
	await process_frame
	print("Original portrait HUD, counters and house badges presented")
	quit()
