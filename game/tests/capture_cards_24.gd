extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func capture(path: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("Resident card images: ",preload("res://infrastructure/current_card_content.gd").live_image_count())


func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	app.screen.progression_panel.open_card("Card_AbodeType2_Rank1")
	await capture("res://../build/screenshots/cards-24-advances.png")
	app.screen.progression_panel.open_card("Sticker_ReligiousObject_3")
	await capture("res://../build/screenshots/cards-24-resources.png")
	app.screen.progression_panel.open_card("Card_Belief_1000")
	await capture("res://../build/screenshots/cards-24-belief.png")
	app.screen.progression_panel.hide()
	app.screen.powers_panel.open_card("Card_GodPower_Beautify")
	await capture("res://../build/screenshots/cards-24-powers.png")
	app.screen.powers_panel.hide()
	await capture("res://../build/screenshots/cards-24-closed.png")
	app.queue_free()
	await process_frame
	print("original 2.4 advances, powers and resources presented")
	quit()
