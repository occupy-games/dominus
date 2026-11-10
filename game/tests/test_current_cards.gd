extends SceneTree
const Content = preload("res://infrastructure/current_card_content.gd")
const Campaign = preload("res://infrastructure/campaign_content.gd")
const World = preload("res://simulation/world.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failures += 1


func run() -> void:
	var catalog := Content.entries()
	check(Content.image_loads == 0, "Reading the complete catalog must not load card images")
	var count := 0
	for id: String in catalog:
		var entry: Dictionary = catalog[id]
		if id != entry["canonical_id"]: continue
		count += 1
		if entry["available"]:
			check(ResourceLoader.exists(entry["thumbnail_path"]) and ResourceLoader.exists(entry["texture_path"]), "Every available card needs its exact source image and converted thumbnail")
			check(not str(entry["texture_path"]).contains("/Resources/Cards/"), "Never fall back to legacy square card icons")
	check(count == 249, "All recovered card and sticker records must be represented")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	var definition := Campaign.homeworld()
	check(not definition.has("objects"), "Runtime maps must not expand unused per-cell objects")
	world.initialize({"campaign_data":definition,"models":{"source:model":{"name":"Source model"}}}, random)
	var before := world.snapshot(false)
	check(before["progression"]["rules"].is_read_only() and before["progression"]["rules"]["cards"].is_read_only(), "Shared rule tables must be deeply immutable")
	var query := world.query_copy()
	check(query._models.is_read_only() and query._models["source:model"].is_read_only(), "Shared model definitions must be deeply immutable")
	var prior: String = str(before["progression"]["rules"]["config"]["InitialTotemCapacity"])
	check(world.reconfigure([{"category":"config","key":"InitialTotemCapacity","value":float(prior)+1}])["ok"], "Replacing immutable configuration must still support live tuning")
	check(str(before["progression"]["rules"]["config"]["InitialTotemCapacity"]) == prior, "Existing snapshots must retain old rule versions")
	check(str(world.snapshot(false)["progression"]["rules"]["config"]["InitialTotemCapacity"]) != prior, "New snapshots must receive the new immutable rule version")
	before["followers"][0]["x"]=-100
	check(world.snapshot(false)["followers"][0]["x"] >= 0, "Mutable entity snapshots must remain detached")
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	app.screen.progression_panel.open_book()
	for frame in range(6): await process_frame
	var panel: Control = app.screen.progression_panel
	check(panel.gallery_items.size() > 150, "All 2.4 advances and resources must be browsable independently of unported game rules")
	var shown := Content.live_image_count()
	check(shown > 0 and shown < 40, "Only visible gallery thumbnails and one detail image should remain resident")
	var scroll: ScrollContainer = panel.tabs.get_tab_control(0)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	for frame in range(3): await process_frame
	check(Content.live_image_count() < 40, "Scrolling must release off-screen illustration references")
	panel.open_card("Sticker_ReligiousObject_3")
	for frame in range(3): await process_frame
	check(panel.tabs.current_tab == 1, "Exact resource/sticker IDs must open their quantified resource tab")
	panel.hide()
	app.screen.powers_panel.open_book()
	for frame in range(3): await process_frame
	check(app.screen.powers_panel.gallery_items.size() >= 60, "The powers gallery must include every recovered 2.4 power")
	app.screen.powers_panel.hide()
	for frame in range(3): await process_frame
	check(Content.live_image_count() <= 3, "Closing galleries must release their illustration textures")
	app.queue_free()
	await process_frame
	# Let the audio mixer retire its stopped Ogg playback before engine shutdown.
	await create_timer(0.1).timeout
	print("Complete original 2.4 cards and bounded image residency: %d failures" % failures)
	quit(1 if failures else 0)
