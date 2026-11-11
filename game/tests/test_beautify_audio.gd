extends SceneTree

const World = preload("res://simulation/world.gd")
const GameScreen = preload("res://presentation/world/game_screen.gd")
const Content = preload("res://infrastructure/game_content.gd")

var failures := 0


func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	data["followers"] = [{"x":8, "z":8}]
	data["progression_rules"]["chests"] = [{"id":"beautify", "type":"treasure1", "x":8, "z":8,
		"depth":0, "source_height":4, "card":"Card_GodPower_Beautify", "rotation":0}]
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed = 26
	world.initialize({"campaign_data":data}, random)
	var screen := GameScreen.new()
	screen.campaign_mode = true
	screen.audio_assets = Content.new().audio_assets()
	root.add_child(screen)
	screen.set_process(false)
	var audio := screen.audio
	audio.set_process(false)
	check(not audio.beautify.is_empty(), "The original bank loop must load")
	if audio.beautify.is_empty():
		quit(1)
		return
	var source := audio.beautify["stream"] as AudioStreamWAV
	var media: AudioStreamWAV = load("res://assets/original/audio/GodusMain_458803511.wav")
	check(source.data == media.data and source.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and source.loop_begin == 0 and source.loop_end == 252668, "Playback must loop the unchanged original PCM")
	check(audio.beautify["attack"] == 0.5 and audio.beautify["release"] == 2.2
		and audio.beautify["volume_db"] == -2.0, "Playback must use the authored transition times and source level")
	screen.select_power("GodPower_Beautify")
	var stroke := {"type":"use_power", "power":"GodPower_Beautify", "x":32, "z":32}
	var events := world.step([stroke])
	screen.apply_snapshot(world.snapshot(), events)
	check(audio.beautify_voice == null, "Arming an unavailable power and rejecting a cast must stay silent")
	world.step([{"type":"open_chest", "id":"beautify"}])
	for sample in range(5):
		events = world.step([stroke])
		screen.apply_snapshot(world.snapshot(), events)
		check(audio.beautify_voice != null and audio.beautify_voice.playing, "A validated terrain sample must start the source voice")
		if audio.beautify_voice == null:
			quit(1)
			return
		audio.advance_beautify(0.1)
		check(is_equal_approx(audio.beautify_gain, (sample + 1) * 0.2), "Repeated samples must continue the same fade-in")
	var first := audio.beautify_voice
	check(is_equal_approx(first.volume_db, audio.effects_db - 2.0), "A sustained stroke must reach the authored level")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	screen._input(release)
	check(audio.beautify_voice == null and first.playing, "Releasing anywhere must begin the original fade-out")
	audio.advance_beautify(1.1)
	check(is_equal_approx(first.volume_db, audio.effects_db - 2.0 + linear_to_db(0.5)), "The stop action must fade the loop")
	events = world.step([stroke])
	screen.apply_snapshot(world.snapshot(), events)
	var second := audio.beautify_voice
	check(second != null and first != second and first.playing, "A new contact can start while the previous voice fades")
	audio.advance_beautify(1.1)
	check(not first.playing and audio.beautify_voice == null and audio.beautify_releases.size() == 1,
		"The first voice must stop at 2.2 seconds and an expired contact must release")
	screen.set_effects_enabled(false)
	check(audio.beautify_releases.is_empty() and not second.playing, "Muting must stop the remaining release")
	events = world.step([stroke])
	screen.apply_snapshot(world.snapshot(), events)
	check(audio.beautify_voice == null, "Accepted samples must remain silent when effects are muted")
	screen.queue_free()
	await process_frame
	print("Original Beautify brush audio: %d failures" % failures)
	quit(1 if failures else 0)
