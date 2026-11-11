extends SceneTree


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func capture(name: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../build/screenshots/"+name+".png")
	print("Captured ",name)


func run() -> void:
	preload("res://infrastructure/adventure_content.gd").progress_path="res://../build/capture-economy-profile.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../build/campaign-economy-preview.json"))
	if not data is Dictionary: quit(1); return
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	app.session.store.database_path="res://../build/capture-economy-homeworld.sqlite"
	if not app.session.world.restore(data,RandomNumberGenerator.new()): quit(1); return
	app.session.refresh_queries()
	# The controlled test map uses source rules and art, not original map layout.
	var campaign := preload("res://infrastructure/campaign_content.gd")
	campaign.definition["width"]=64
	campaign.definition["bathymetry"]=PackedByteArray()
	campaign.definition["bathymetry"].resize(64*64)
	campaign.definition["bathymetry"].fill(23)
	app.show_game(false)
	app.session.set_process(false)
	var view: Variant = app.screen.world_view
	view.zoom=27
	view.focus=view.world_position(12,12)
	view.update_camera()
	await capture("campaign-farming-settlement")
	view.focus=view.world_position(40,40)
	view.update_camera()
	await capture("campaign-mining-settlement")
	for role: String in ["farmer","miner"]:
		for agent: Dictionary in app.session.presentation_snapshot()["followers"]:
			if agent.get("profession","")!=role: continue
			view.zoom=4
			view.focus=view.world_position(agent["x"],agent["z"])
			view.update_camera()
			await capture("campaign-"+role+"-detail")
			break
	view.zoom=27
	view.update_camera()
	app.screen.progression_panel.open_card("Card_Settlement_Farming")
	await capture("campaign-farming-card")
	app.screen.progression_panel.hide()
	app.screen.powers_panel.open_card("Card_GodPower_Settlement_2")
	await capture("campaign-settlement-power")
	app.queue_free()
	await process_frame
	print("Original campaign worker and settlement presentation captured")
	quit()
