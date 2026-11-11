extends SceneTree

const Content = preload("res://infrastructure/game_content.gd")
const FrontEnd = preload("res://application/front_end.tscn")
var failures := 0


func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func run() -> void:
	var assets := Content.new().follower_assets()
	check(assets.get("bones", []).size() == 32 and assets.get("models", []).size() == 2, "Original follower rig and both models must be recovered")
	var app: Variant = FrontEnd.instantiate()
	root.add_child(app)
	app.show_game(true)
	app.session.set_process(false)
	var human: Variant = app.screen.world_view.actor_nodes[1]
	check(human.has_node("Rig") and human.has_node("OriginalSourceMesh"), "World followers must use original skinned geometry")
	var twin := preload("res://presentation/world/original_follower.gd").new()
	twin.assets=assets
	twin.variant=human.variant
	root.add_child(twin)
	check(twin.get_node("OriginalSourceMesh").mesh==human.get_node("OriginalSourceMesh").mesh,"Matching original models must share GPU mesh resources")
	check(twin.rig!=human.rig,"Shared source meshes must retain independently animated skeletons")
	twin.free()
	human.set_process(false)
	for clip: String in ["idle", "walking", "building", "swamp_struggle"]:
		human.animation_state = clip
		human.apply_animation(0)
		var poses := []
		for i in range(32): poses.append(human.rig.get_bone_pose_rotation(i))
		human.apply_animation(0.3)
		var changed := false
		for i in range(32):
			if not poses[i].is_equal_approx(human.rig.get_bone_pose_rotation(i)): changed = true
		check(changed, "Source clip must animate the original skeleton: " + clip)
	app.screen.update_playback(true, 3)
	var time: float = human.clip_time
	await process_frame
	check(human.clip_time == time, "Pausing must freeze original animation as well as simulation")
	check(app.screen.audio.music.stream is AudioStreamOggVorbis and app.screen.audio.music.stream.loop, "Original music must load and loop")
	app.screen.audio.set_music_enabled(false)
	check(app.screen.audio.music.stream_paused, "Music control must pause playback")
	app.screen.audio.set_sculpting(true)
	check(app.screen.audio.sculpt.playing, "Dragging must play the original SculptLoop event")
	app.screen.audio.set_sculpting(false, true)
	check(not app.screen.audio.sculpt.playing and "STOPSOUND_SCULPTLOOP" in app.screen.audio.played_events, "Release must stop the loop and play its original release tail")
	app.screen.audio.play_event("Swamp cast")
	check("Swamp cast" in app.screen.audio.played_events, "The recovered Swamp cast event must load its original bank media")
	human.animation_state = "building"
	human.playback_speed = 1.0
	human.last_clip = ""
	human.apply_animation(0)
	human.cue_audio.played_events.clear()
	human.apply_animation(0.89)
	check(human.cue_audio.played_events.is_empty(), "Hammer SFX must wait for its source marker")
	human.apply_animation(0.02)
	check(human.cue_audio.played_events == ["PLAYSOUND_FOLLOWERHAMMERGROUND"], "Original hammer cue must fire at 0.9 seconds")
	app.screen.set_effects_enabled(false)
	check(not human.cue_audio.effects_enabled and not human.cue_audio.effects[0].playing, "SFX control must also mute animation cues")
	human.apply_animation(0.5)
	check(human.cue_audio.played_events.size() == 1, "Muted playback must not trigger sounds")
	var audio: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/audio_catalog.json"))
	check(audio["assets"].size() == 612 and audio["failures"].is_empty(), "All observed bank media must convert")
	for record: Dictionary in audio["assets"]:
		var stream: Resource = load("res://assets/original/" + record["path"])
		check(stream is AudioStream and stream.get_length() > 0, "Recovered audio must import: " + record["path"])
	app.show_library()
	app.screen.search.text = "follower.group.bin"
	app.screen.apply_filters()
	var viewer: Variant = app.screen.preview_content.get_child(0)
	check(viewer.human.rig.get_bone_count() == 32, "Library must expose original animated followers")
	app.screen.show_character(1, "building")
	viewer = app.screen.preview_content.get_child(0)
	check(viewer.human.variant == 1 and viewer.human.animation_state == "building", "Library must switch model and source clip")
	app.screen.search.text = "GodusMain_675198389.ogg"
	app.screen.apply_filters()
	check(app.screen.player.stream is AudioStream and not app.screen.player.playing, "Decoded music must be available for manual library audition")
	app.queue_free()
	await process_frame
	await create_timer(0.05).timeout
	print("Original characters and audio: %d failures" % failures)
	quit(1 if failures else 0)
