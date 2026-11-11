extends SceneTree

const FrontEnd = preload("res://application/front_end.tscn")
const Catalog = preload("res://infrastructure/asset_catalog.gd")
var failures := 0


func _initialize() -> void:
	create_timer(20).timeout.connect(func() -> void:
		push_error("Front-end integration timed out")
		quit(1))
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1


func verify_continuation() -> void:
	var paths := preload("res://infrastructure/save_paths.gd")
	var previous := OS.get_environment("DOMINUS_SAVE_DIRECTORY")
	var temporary := ProjectSettings.globalize_path("res://../build/test-continue-%d"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(temporary)
	OS.set_environment("DOMINUS_SAVE_DIRECTORY",temporary)
	check(paths.continuation()==paths.world(),"An empty save directory must retain the standard default")
	FileAccess.open(paths.opening(),FileAccess.WRITE).close()
	check(paths.continuation()==paths.opening(),"Continue must find an authored save when the standard save is absent")
	await create_timer(1.05).timeout
	FileAccess.open(paths.world(),FileAccess.WRITE).close()
	check(paths.continuation()==paths.world(),"Continue must select a newer standard campaign save")
	await create_timer(1.05).timeout
	FileAccess.open(paths.opening(),FileAccess.WRITE).close()
	check(paths.continuation()==paths.opening(),"Continue must select a newer authored campaign save")
	DirAccess.remove_absolute(paths.opening())
	DirAccess.remove_absolute(paths.world())
	DirAccess.remove_absolute(temporary)
	if previous.is_empty(): OS.unset_environment("DOMINUS_SAVE_DIRECTORY")
	else: OS.set_environment("DOMINUS_SAVE_DIRECTORY",previous)


func run() -> void:
	await verify_continuation()
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	await process_frame
	check(app.screen.library_button != null, "Main menu must expose the library action")
	app.screen.library_button.pressed.emit()
	await process_frame
	var library: Variant = app.screen
	check(library.catalog.entries.size() > 0, "Generated catalog must be loaded")
	check(library.file_nodes.size() == library.filtered.size(), "Every visible source entry must be listed while original branding artwork stays hidden")
	check(library.catalog.assemblies.size() == 1, "Text source geometry must yield the known assembly")
	var viewer: Variant = library.preview_content.get_child(0)
	check(viewer.part_meshes.size() == 4, "The assembly must contain all four source components")
	var base_position: Vector3 = viewer.part_meshes["storey1"].position
	viewer.exploded = true
	viewer.position_parts()
	check(viewer.part_meshes["storey1"].position != base_position, "Explode must separate components")
	viewer.exploded = false
	viewer.position_parts()
	check(viewer.part_meshes["storey1"].position == base_position, "Reassembly must restore shared coordinates")
	viewer.part_buttons[0].button_pressed = false
	check(not viewer.part_meshes["storey1"].visible, "Visibility toggles must hide their component")
	var scene_root: TreeItem = library.items.get_root()
	check(scene_root.get_child(0).get_text(0) == "Assembled objects", "Tree must expose assembled objects")
	check(library.folder_nodes.has("art/environments/monuments"), "Tree must preserve nested source folders")
	library.search.text = "ChristmasTree"
	library.apply_filters()
	check(library.filtered.size() >= 4, "Search by original object name must discover geometry parts")
	library.search.text = "PACK_TREEIMPOSTERS_V2.PNG"
	library.apply_filters()
	check(library.filtered.size() == 2, "Search must be case-insensitive and include the atlas metadata")
	library.only_previewable.button_pressed = true
	library.apply_filters()
	check(library.filtered.size() == 1, "Media filter must exclude unresolved metadata")
	check(library.preview_content.get_child(0) is TextureRect, "Selected image must have a texture preview")
	library.search.text = "this asset does not exist"
	library.apply_filters()
	check(library.file_nodes.size() == 0 and library.player.stream == null, "Empty searches must clear the preview")
	library.only_previewable.button_pressed = false
	library.search.text = "02_Sculpting_card.mp3"
	library.apply_filters()
	check(library.player.stream is AudioStream and not library.player.playing, "Audio must load without autoplay")
	library.player.play()
	check(library.player.playing, "Audio preview must start on request")
	library.search.text = "stray-that-has-no-match"
	library.apply_filters()
	check(not library.player.playing and library.player.stream == null, "Changing selection must release audio")
	await create_timer(0.05).timeout
	library.search.text = ""
	for i in range(library.category.item_count):
		if library.category.get_item_metadata(i) == "unknown":
			library.category.select(i)
	library.apply_filters()
	check(not library.filtered.is_empty(), "Category filter must include unresolved files")
	check(library.preview_content.get_child(0) is TextEdit, "Unsupported formats must show a raw excerpt")
	library.leave()
	await process_frame
	check(app.screen.library_button != null, "Back action must restore the menu")
	app.show_campaigns()
	app.screen.select_map("homeworld6")
	check(not app.screen.start_button.disabled, "Homeworld6 must be selectable from the campaign menu")
	app.screen.start_button.pressed.emit()
	app.session.set_process(false)
	app.session.finish_worker()
	var opening: Dictionary=app.session.presentation_snapshot()
	check(opening["campaign"]["map_id"]=="homeworld6" and opening["opening"]["phase"]=="rescue", "Starting Homeworld6 must enter its original rescue")
	check(opening["followers"].size()==2 and opening["followers"][0]["state"]=="drowning", "Campaign selection must use the two original Lua-spawned followers")
	check(app.session.store.database_path.ends_with("homeworld6-opening.sqlite"), "The authored opening must retain its separate save path")
	app.show_menu()
	await process_frame
	# Exercise a missing/unbuilt catalog without touching local source files.
	var empty := Catalog.new()
	empty.error_message = "Test: build the library first."
	app.catalog = empty
	# Directly inject the empty adapter so application does not reload the real one.
	var empty_view: Variant = app.Library.new()
	empty_view.catalog = empty
	app.replace_screen(empty_view)
	await process_frame
	check(empty_view.file_nodes.size() == 0, "Missing catalogs must show an empty state")
	check(empty_view.preview_content.get_child_count() == 1, "Empty state must show setup guidance")
	app.queue_free()
	await process_frame
	# AudioServer releases stopped Ogg playback on its next mixing pass.
	await create_timer(0.1).timeout
	print("Front-end integration: %d failures" % failures)
	quit(1 if failures else 0)
