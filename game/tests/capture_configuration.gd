extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(path: String) -> void:
	for frame in range(4): await process_frame
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	app.screen.toggle_menu()
	app.screen.pause_panel.selected="camera.pinch_sensitivity"
	app.screen.pause_panel.refresh(app.settings.definitions,app.settings.values)
	await capture("res://../build/screenshots/settings-tree.png")
	app.screen.toggle_menu()
	app.screen.progression_panel.open_card("Card_MaxRank_2")
	await capture("res://../build/screenshots/card-gallery.png")
	app.screen.progression_panel.open_card("Card_Textile_1")
	await capture("res://../build/screenshots/resource-gallery.png")
	app.screen.progression_panel.hide()
	app.screen.powers_panel.open_card("Card_GodPower_TotemActivate")
	await capture("res://../build/screenshots/powers-gallery.png")
	print("Native settings, card, resource and power galleries presented")
	app.queue_free()
	await process_frame
	quit()
