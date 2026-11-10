extends SceneTree

const FrontEnd = preload("res://application/front_end.tscn")
const Building = preload("res://presentation/world/assembled_building.gd")
var failures := 0


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func run() -> void:
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	app.show_example()
	await process_frame
	var view: Variant = app.screen
	var assemblies := 0
	for model: Dictionary in app.catalog.models:
		var info: Dictionary = model.get("building_assembly", {})
		if info.get("base_id", "") != model["id"]: continue
		var building := Building.new()
		building.data = app.catalog.building_data(model["id"])
		root.add_child(building)
		check(info["unresolved"].is_empty(), "Assembly must not invent missing component placement: " + model["id"])
		check(building.components.size() == info["components"].size(), "Every recovered component must instantiate: " + model["id"])
		for index in range(building.components.size()):
			var expected: Dictionary = info["components"][index]
			var component: Dictionary = building.components[index]
			var node: Node3D = component["node"]
			var offset: Array = expected["offset"]
			check(node.position.is_equal_approx(Vector3(offset[0],offset[1],offset[2])), "Assembly must retain source-coordinate placement: " + expected["model_id"])
			check(not expected["placement_evidence"].is_empty(), "Every assembly transform needs provenance")
			var visible_at_end: bool = expected["role"] in ["complete", "shadow"] or (expected["role"] == "part" and not expected.get("embedded_in_complete", false)) or (expected["role"] == "part_shadow" and not building.has_complete_shadow)
			check(node.visible == visible_at_end, "Completed building must retain attachments and avoid duplicate chunks: " + expected["model_id"])
		building.set_stage(1, false)
		for component: Dictionary in building.components:
			var expected: bool = component["role"] in ["scaffold", "scaffold_shadow"] or (component["role"] in ["part", "part_shadow"] and component["number"] <= 1)
			check(component["node"].visible == expected, "Construction must reveal whole-building parts cumulatively")
		building.free()
		assemblies += 1
		if assemblies % 30 == 0: await process_frame
	check(assemblies >= 335, "Every recovered building family must have a whole source assembly")
	var covered := {}
	var played := 0
	var animated_groups := {}
	for model: Dictionary in app.catalog.models:
		if model["material_status"] != "source_texture" or not model.has("motion"): continue
		if model["motion"]["clips"].is_empty() or animated_groups.has(model["source"]): continue
		animated_groups[model["source"]] = true
		view.select_model(model["id"])
		var player: Variant = view.preview
		check(player.tracks.size() > 1, "Animated units need a playable list: " + model["source"])
		for index in range(player.tracks.size()):
			var track: Dictionary = player.tracks[index]
			if track["kind"] != "clip": continue
			var path: String = track["clip"]["path"]
			if covered.has(path): continue
			covered[path] = true
			player.select_track(index)
			check(is_instance_valid(player.unit) and player.duration > 0, "Original clip must instantiate its source rig: " + track["name"])
			var bone_count: int = player.unit.rig.get_bone_count()
			player.playing = false
			player.seek_to(player.duration * 0.35)
			for bone in range(bone_count):
				check(player.unit.rig.get_bone_pose_position(bone).is_finite() and player.unit.rig.get_bone_pose_rotation(bone).is_finite(), "Source poses must remain finite")
			var position: float = player.playhead
			player._process(0.1)
			check(player.playhead == position, "Pause must freeze selected clip")
			player.toggle_playback()
			player._process(0.1)
			check(player.playhead != position, "Play must advance selected clip")
			player.looped = false
			player.seek_to(player.duration - 0.001)
			player.playing = true
			player._process(0.1)
			check(not player.playing and is_equal_approx(player.playhead, player.duration), "Nonlooping playback must finish at its endpoint")
			player.clip_cache.clear()
			played += 1
			if played % 30 == 0: await process_frame
	check(played == 371 and animated_groups.size() >= 10, "Every supported clip must be playable on its own unit skeleton")
	var tent := "tents.group.bin:dff1563f"
	view.select_model(tent)
	var player: Variant = view.preview
	check(player.tracks[1]["kind"] == "stages" and player.playing, "Selecting a building must start its recovered lifecycle stages")
	var stages: Array = player.tracks[1]["stages"]
	check(stages[0]["name"] == "Scaffolds" and stages[-1]["name"] == "Completed", "Building lifecycle must use verified scaffold/component/completed records")
	var assembly: Node3D = player.building
	var transform := assembly.transform
	check(assembly.components.size() == 4, "Whole tent must retain complete, shadow, scaffold and anchored part nodes")
	var part_node: Node3D
	for component: Dictionary in assembly.components:
		if component["role"] == "part": part_node = component["node"]
	check(part_node.position.is_equal_approx(Vector3(-26.268005,140.424469,25.716591)), "Original part locator must register the construction chunk")
	player.seek_to(1.6)
	check(player.building == assembly and part_node.visible and assembly.transform == transform, "Lifecycle must reveal parts on one fixed building without recentering")
	player.seek_to(player.duration)
	check(player.active_stage == stages.size() - 1, "Lifecycle scrubbing must reach the completed source building")
	check(player.building == assembly and assembly.completed and not part_node.visible, "Completed source mesh must replace embedded chunks without duplicate faces")
	check(assembly.get_child(0).get_meta("source_resource") == app.catalog.model_index[tent]["resource_id"], "Completed stage must render the original complete mesh")
	var rank_found := false
	for model: Dictionary in app.catalog.models:
		if model.get("lifecycle", {}).get("ranks", []).size() > 1:
			view.select_model(model["id"])
			for track: Dictionary in view.preview.tracks:
				if track["name"] == "Rank progression": rank_found = true
			break
	check(rank_found, "Recovered building ranks must be available as a separate sequence")
	for source: String in ["boats.group.bin", "fish.group.bin", "eventdock.group.bin", "sheep.group.bin"]:
		for model: Dictionary in app.catalog.models:
			if model["source"] != source or model["material_status"] != "source_texture": continue
			view.select_model(model["id"])
			var expected: String = {"boats.group.bin": "water", "fish.group.bin": "underwater", "eventdock.group.bin": "shore", "sheep.group.bin": "land"}[source]
			check(view.preview.ground.get_meta("environment") == expected, "Detail background must match habitat: " + source)
			if expected != "land":
				check(view.nodes[model["id"]].has_meta("ground") and view.nodes[model["id"]].get_meta("ground").get_meta("environment") == expected, "World exhibit must match the preview habitat")
			break
	# Follower clips also work in the asset library's detail player.
	view.library_requested.emit("follower.group.bin:7c293053")
	await process_frame
	check(app.screen.preview_content.get_child(0).tracks.size() > 300, "Library must expose the full recovered follower clip list")
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Exhibit habitats and playback: %d clips, %d failures" % [played, failures])
	quit(1 if failures else 0)
