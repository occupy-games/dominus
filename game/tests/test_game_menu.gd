extends SceneTree
var failures := 0
func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(1))
	run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message); failures+=1
func run() -> void:
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.settings.path="res://../build/menu-settings.json"
	app.constants.path="res://../build/menu-constants.csv"
	var file := FileAccess.open(app.constants.path,FileAccess.WRITE)
	file.store_string("Name,Value\nRuntime.birth_rate,2\n")
	file.close()
	app.show_campaign()
	app.session.set_process(false)
	var screen: Variant = app.screen
	screen.toggle_menu()
	check(app.session.paused and screen.pause_panel.visible,"Settings button must open the menu and pause")
	check(screen.pause_panel.tree.get_root().get_child_count()==app.settings.definitions.size(),"Settings must expose grouped JSON preferences")
	screen.pause_panel.setting_changed.emit("camera.pinch_sensitivity",0.2)
	check(screen.world_view.preferences["camera.pinch_sensitivity"]==0.2,"Apply preferences to live camera")
	screen.pause_panel.reset_requested.emit("camera.pinch_sensitivity")
	check(screen.world_view.preferences["camera.pinch_sensitivity"]==0.1,"Reset individual default")
	file=FileAccess.open(app.constants.path,FileAccess.WRITE)
	file.store_string("Name,Value\nRuntime.birth_rate,4\n")
	file.close()
	var tick: int = app.session.world.snapshot(false)["tick"]
	screen.pause_panel.reload_constants_requested.emit()
	check(app.session.world.runtime_value("birth_rate",1)==4 and app.session.paused and app.session.world.snapshot(false)["tick"]==tick,"CSV reload button must apply without advancing a paused simulation")
	screen.save_directory=ProjectSettings.globalize_path("res://../build")
	screen.pause_panel.save_requested.emit()
	check(screen.file_dialog.file_mode==FileDialog.FILE_MODE_SAVE_FILE,"Save must show a named save dialog")
	var path := ProjectSettings.globalize_path("res://../build/menu-save.sqlite3")
	screen.file_dialog.file_selected.emit(path)
	screen.file_dialog.hide()
	check(FileAccess.file_exists(path),"Save dialog selection must write SQLite")
	var saved: Dictionary = app.session.world.export_state()
	screen.pause_panel.load_requested.emit()
	check(screen.file_dialog.file_mode==FileDialog.FILE_MODE_OPEN_FILE,"Load must show a file picker")
	screen.file_dialog.file_selected.emit(path)
	app.session.set_process(false)
	check(app.screen!=screen and app.session.world.export_state()==saved,"Load must restore simulation and recreate presentation")
	check(app.screen.world_view.preferences["camera.pinch_sensitivity"]==0.1,"Preferences must survive loading games")
	app.queue_free()
	await process_frame
	for filename: String in [path,"res://../build/menu-settings.json","res://../build/menu-constants.csv"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	print("Game menu and live configuration controls: %d failures" % failures)
	quit(1 if failures else 0)
