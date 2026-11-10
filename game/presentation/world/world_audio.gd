extends "res://presentation/world/source_audio.gd"
## Source audio responds to detached events; it cannot influence simulation.

var music := AudioStreamPlayer.new()
var music_enabled := true
var sculpt := AudioStreamPlayer.new()
var sculpt_activity := 0.0


func play_event(kind: String) -> void:
	var source: String = {"chest_opened":"PLAYSOUND_FOLLOWERSTATEREACTTOCHEST","claim_card":"PLAYSOUND_FOLLOWERSTATECELEBRATECARD"}.get(kind,kind)
	super.play_event(source)


func _ready() -> void:
	super._ready()
	add_child(music)
	music.volume_db = -19
	if assets.get("music") is AudioStream:
		music.stream = assets["music"].duplicate()
		if music.stream is AudioStreamOggVorbis:
			music.stream.loop = true
		music.play()
	add_child(sculpt)
	sculpt.volume_db = -17


func set_sculpting(active: bool, release: bool = false) -> void:
	if not active or not effects_enabled:
		var was_active := sculpt.playing
		sculpt.stop()
		sculpt_activity = 0
		if release and was_active: play_event("STOPSOUND_SCULPTLOOP")
		return
	sculpt_activity = 0.16
	if sculpt.playing: return
	var samples: Array = assets.get("PLAYSOUND_SCULPTLOOP", [])
	if samples.is_empty(): return
	var stream: AudioStream = samples[0].duplicate()
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif stream is AudioStreamOggVorbis: stream.loop = true
	sculpt.stream = stream
	sculpt.play()


func set_music_enabled(value: bool) -> void:
	music_enabled = value
	music.stream_paused = not value


func set_effects_enabled(value: bool) -> void:
	super.set_effects_enabled(value)
	if not value: set_sculpting(false)


func _process(delta: float) -> void:
	sculpt_activity -= delta
	if sculpt_activity <= 0 and sculpt.playing: set_sculpting(false)


func _exit_tree() -> void:
	super._exit_tree()
	music.stream_paused = false
	music.stop()
	music.stream = null
	sculpt.stop()
	sculpt.stream = null
