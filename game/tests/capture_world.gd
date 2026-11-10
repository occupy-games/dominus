extends SceneTree
## Deterministic playable-state capture fixture; never used by normal startup.

const FrontEnd = preload("res://application/front_end.tscn")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	if "--character" in OS.get_cmdline_user_args():
		app.show_library()
		app.screen.search.text = "follower.group.bin"
		app.screen.apply_filters()
		app.screen.show_character(0, "walking")
		return
	app.show_game(true)
	app.session.set_process(false)
	var world: Variant = app.session.world
	for n in range(3):
		var found := false
		for z in range(13, 22):
			for x in range(13, 23):
				var command := {"type": "home", "x": x, "z": z}
				if not found and world.inspect(command)["ok"]:
					world.step([command])
					found = true
		for i in range(120): world.step()
	for i in range(3):
		world.step([{"type": "sheep", "x": 17 + i, "z": 18}])
	app.screen.apply_snapshot(world.snapshot())
	app.screen.goal_panel.visible = false
	app.screen.message_label.text = ""
