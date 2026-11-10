extends SceneTree

const Content = preload("res://infrastructure/campaign_content.gd")
const World = preload("res://simulation/world.gd")
const Session = preload("res://application/game_session.gd")
const Picker = preload("res://presentation/menu/campaign_menu.gd")
var failures := 0


func _initialize() -> void:
	create_timer(180).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok: push_error(message); failures += 1


func run() -> void:
	var maps := Content.maps()
	check(maps[0]["id"] == "homeworld", "Homeworld must be the first campaign")
	var hashes := {}
	var constants := preload("res://infrastructure/live_constants.gd").new()
	constants.initialize(Content.homeworld()["progression_rules"])
	var parsed := constants.read()
	check(parsed.get("ok", false), "All three live tables must parse")
	var count := 0
	for entry: Dictionary in maps:
		if not entry["available"]:
			check(Content.map_definition(entry["id"]).is_empty(), "Unsupported maps must not start a substitute world")
			continue
		var definition := Content.map_definition(entry["id"])
		check(not definition.is_empty(), "Available map must load: " + str(entry["name"]))
		if definition.is_empty(): continue
		var world := World.new()
		var random := RandomNumberGenerator.new()
		random.seed = 2026
		world.initialize({"campaign_data": definition}, random)
		var state := world.snapshot(false)
		check(state["campaign"]["map_id"] == entry["id"] and state["source_map"]["name"] == entry["name"], "Campaign must retain selected map identity")
		check(state["source_map"]["height_sha256"] == entry["height_sha256"], "Campaign must use the selected terrain")
		check(not hashes.has(state["source_map"]["height_sha256"]), "Campaign maps must have different terrain")
		hashes[state["source_map"]["height_sha256"]] = true
		check(state["terrain"] == definition["terrain"], "Terrain must be source-derived without cropping")
		var default_area: Dictionary = state["progression"]["rules"]["influence_areas"][0].duplicate()
		check(world.reconfigure(parsed["changes"]).get("ok", false), "Live tables must apply to " + str(entry["name"]))
		check(world.snapshot(false)["progression"]["rules"]["influence_areas"][0] == default_area, "Reload must keep the selected-map influence registration")
		check(world.reconfigure(parsed["changes"]).get("ok", false), "Repeated reload must succeed")
		check(world.snapshot(false)["progression"]["rules"]["influence_areas"][0] == default_area, "Repeated reload must not accumulate a map offset")
		for index in range(definition["followers"].size()):
			var start: Dictionary = definition["followers"][index]
			check(state["followers"][index]["x"] == start["x"] and state["followers"][index]["z"] == start["z"] and world.height_at(start["x"], start["z"]) > 0, "Use actual dry player starts")
		var player := preload("res://simulation/campaign_player.gd").new()
		for tick in range(240):
			var clearing := player.clear_for_plot(world,world.snapshot(false)) if tick%10==0 else {}
			world.step([clearing] if not clearing.is_empty() else [])
		state = world.snapshot(false)
		check(not state["homes"].is_empty(), "Followers must be able to settle on " + str(entry["name"]))
		var restored := World.new()
		check(restored.restore(world.export_state(), RandomNumberGenerator.new()), "Selected-map state must restore")
		world.step()
		restored.step()
		check(world.snapshot(false) == restored.snapshot(false), "Selected-map continuation must be deterministic")
		print(entry["name"], ": ", state["homes"].size(), " homes")
		count += 1
		await process_frame
	check(count == 8, "All eight supported large-map starts must run")
	var picker := Picker.new()
	picker.maps = maps
	root.add_child(picker)
	check(picker.selected == "homeworld" and not picker.start_button.disabled, "Picker must default to Homeworld")
	picker.select_map("homeworld6")
	check(picker.start_button.disabled, "Missing authored starts must stay unavailable")
	picker.select_map("hubworld_02")
	var requested: Array = []
	picker.start_requested.connect(func(id: String) -> void: requested.append(id))
	picker.start_button.pressed.emit()
	check(requested == ["hubworld_02"], "Picker must request the chosen map ID")
	picker.queue_free()
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	var definition := Content.map_definition("hubworld_02")
	session.new_campaign(definition)
	var path := "res://../build/map-selection-save.sqlite3"
	check(session.save_game(path).get("ok", false), "Selected map must save to SQLite")
	session.new_campaign(Content.homeworld())
	check(session.load_game(path).get("ok", false), "Selected map must load from SQLite")
	var loaded := session.presentation_snapshot()
	check(loaded["campaign"]["map_id"] == "hubworld_02", "Load must retain the selected map")
	check(Content.for_state(loaded)["bathymetry"] == definition["bathymetry"], "Load must resolve the selected water background, not Homeworld")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	session.queue_free()
	await process_frame
	print("Original large campaign maps: %d failures" % failures)
	quit(1 if failures else 0)
