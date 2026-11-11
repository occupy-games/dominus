extends SceneTree

const World = preload("res://simulation/world.gd")
const WorldView = preload("res://presentation/world/world_view.gd")
const Foundations = preload("res://simulation/temple_rules.gd")
const TempleContent = preload("res://infrastructure/temple_sites.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok: return
	failures += 1
	push_error(message)


func retract(x: int, z: int, distance: int = -1) -> Dictionary:
	return {"type":"sculpt_drag", "x":x, "z":z, "nx":1, "nz":0, "layer":3, "distance":distance, "radius":0}


func make_view(catalog: RefCounted) -> Node3D:
	var view := WorldView.new()
	view.terrain.colors = preload("res://infrastructure/game_content.gd").new().terrain_palette()
	view.resolve_building = catalog.building_data
	root.add_child(view)
	return view


func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-sites.json"))
	var sites := TempleContent.sites("initialworldsetup6", manifest["source_sha256"])
	var beacon: Dictionary = sites.filter(func(site: Dictionary) -> bool: return site["id"] == "1012").front()
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	data["followers"] = [{"x":14, "z":18}]
	beacon.merge({"x":20, "z":20, "source_height":int(data["sea_level"])+4}, true)
	data["progression_rules"]["shrines"] = [beacon]
	for unlock: String in ["DoubleClickSculpt", "GodPower_Totem", "GodPower_TotemActivate"]:
		data["progression_rules"]["unlocks"][unlock] = "always"
	var width := int(data["width"])
	var center := 20 * width + 20
	var edge := Foundations.footprint(beacon).end.x - 1
	data["terrain"][center] = 5
	data["terrain"][20 * width + edge] = 7
	data["terrain"][20 * width + edge + 1] = 2
	data["terrain"][21 * width + edge + 2] = 2
	data["terrain"][30 * width + 31] = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 1012
	var world := World.new()
	world.initialize({"campaign_data":data}, rng)

	var catalog := preload("res://infrastructure/asset_catalog.gd").new()
	catalog.read_models()
	var view := make_view(catalog)
	view.apply_snapshot(world.snapshot(false))
	var shrine: Node3D = view.progression_nodes.get("shrine:1012")
	check(shrine != null and is_equal_approx(shrine.position.y, 4 * WorldView.Terrain.STEP),
		"The buried original beacon must keep its authored elevation")

	var drag := retract(edge, 20)
	var quote := world.inspect(drag)
	check(quote.get("edits") == [{"cell":20 * width + edge, "height":4}] and quote["cost"] == 3,
		"A deep retraction must remove cover only down to the full shrine foundation")
	check(world.query_copy().inspect(drag) == quote, "The detached drag preview must protect the same tiles")
	world.step([drag])
	check(world.height_at(edge, 20) == 4, "The committed drag must stop at the quoted foundation height")
	var belief := int(world._state["belief"])
	var revision := int(world._state["terrain_revision"])
	check(not world.inspect(drag)["ok"], "The same drag must leave the exposed foundation in place")
	world.step([drag])
	check(world.height_at(edge, 20) == 4 and world._state["belief"] == belief and world._state["terrain_revision"] == revision,
		"A fully blocked drag must keep terrain and belief unchanged")

	var mixed := retract(edge + 1, 21, -2)
	quote = world.inspect(mixed)
	check(quote.get("edits") == [{"cell":21 * width + edge + 1, "height":2}] and quote["cost"] == 2,
		"A drag across the foundation must quote only the editable land")
	world.step([mixed])
	check(world.height_at(edge, 21) == 4 and world.height_at(edge + 1, 21) == 2,
		"A mixed drag must still retract the neighboring terrace")

	var dig := {"type":"dig", "x":20, "z":20}
	check(world.inspect(dig)["ok"], "Double-click digging must still uncover a shrine")
	world.step([dig])
	for kind: String in ["lower", "dig"]:
		check(not world.inspect({"type":kind, "x":20, "z":20})["ok"], "Single-cell %s must preserve exposed support" % kind)
	var brush := {"type":"lower", "x":edge, "z":20, "radius":1}
	check(world.inspect(brush).get("cells") == [20 * width + edge + 1],
		"A lowering brush can still edit the tile beside the shrine")
	world.step([brush])
	check(world.height_at(edge, 20) == 4 and world.height_at(edge + 1, 20) == 1,
		"The committed brush must leave the support and lower its neighbor")

	var place := {"type":"use_power", "power":"GodPower_Totem", "x":30, "z":30}
	world.step([place])
	var totem_drag := retract(30, 30)
	var lower := {"type":"lower", "x":30, "z":30}
	check(not world.inspect(totem_drag)["ok"] and not world.inspect(lower)["ok"], "A placed totem must keep its anchor land")
	place["x"] = 32
	world.step([place])
	check(world.inspect(totem_drag)["ok"] and not world.inspect({"type":"lower", "x":32, "z":30})["ok"],
		"Moving a totem must move its protection")
	world.step([{"type":"use_power", "power":"GodPower_TotemActivate"}])
	check(world.inspect({"type":"lower", "x":32, "z":30})["ok"], "A deactivated totem must leave the tile editable")

	var saved := world.export_state()
	saved["state"]["terrain"][center] = 2
	var restored := World.new()
	check(restored.restore(saved, RandomNumberGenerator.new()), "An older save with an undermined shrine must still load")
	check(not restored.inspect(dig)["ok"], "Restoring a save must rebuild the remaining foundation protection")
	view.apply_snapshot(restored.snapshot(false))
	check(shrine != null and is_equal_approx(shrine.position.y, 2 * WorldView.Terrain.STEP),
		"The existing original beacon model must meet the ground in an undermined save")
	view.free()

	check_voyage(catalog)
	print("Shrine and totem sculpt foundations: %d failures" % failures)
	quit(1 if failures else 0)


func check_voyage(catalog: RefCounted) -> void:
	var data := preload("res://infrastructure/adventure_content.gd").definition("event_02a__ex02a_map01_expshrineintroeasy")
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	world.initialize({"campaign_data":data}, rng)
	world.step([{"type":"start_voyage", "followers":int(data["voyage"]["minimum"])}])
	var view := make_view(catalog)
	view.apply_snapshot(world.snapshot(false))
	var shrine: Node3D = view.progression_nodes.get("voyage_temple:1001")
	var before := world.height_at(38, 42)
	var lower := {"type":"lower", "x":38, "z":42}
	check(shrine != null and world.inspect(lower)["ok"], "The original voyage shrine must be visible and editable")
	world.step([lower])
	view.apply_snapshot(world.snapshot(false))
	check(world.height_at(38, 42) == before - 1 and shrine != null and is_equal_approx(shrine.position.y, (before - 1) * WorldView.Terrain.STEP),
		"The same voyage shrine model must follow the lowered terrain")
	view.free()
