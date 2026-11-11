extends "res://presentation/world/source_audio.gd"
## Source audio responds to detached events; it cannot influence simulation.

var music := AudioStreamPlayer.new()
var music_enabled := true
var sculpt := AudioStreamPlayer.new()
var sculpt_activity := 0.0
var beautify_voice: AudioStreamPlayer
var beautify_releases: Array[Dictionary] = []
var beautify_activity := 0.0
var beautify_gain := 0.0
var beautify: Dictionary = {}
var rain_active := false
var rain_voices: Array[Dictionary] = []


func play_event(kind: String) -> void:
	var source: String = {"chest_opened":"PLAYSOUND_FOLLOWERSTATEREACTTOCHEST","claim_card":"PLAYSOUND_FOLLOWERSTATECELEBRATECARD",
		"belief_collector_collected":"Shrine belief collection"}.get(kind,kind)
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
	beautify = assets.get("beautify_loop", {})
	for definition: Dictionary in assets.get("rain_loop",[]):
		var player:=AudioStreamPlayer.new()
		player.stream=definition["stream"]
		add_child(player)
		rain_voices.append({"player":player,"definition":definition,"gain":0.0})


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
	if not value:
		set_sculpting(false)
		stop_beautify()
		set_rain_active(false)


func set_rain_active(active: bool) -> void:
	active=active and effects_enabled
	if rain_active==active: return
	rain_active=active
	for voice: Dictionary in rain_voices:
		if voice.has("fade"): voice["fade"].kill()
		var player: AudioStreamPlayer=voice["player"]
		if active and not player.playing:
			set_rain_gain(0.0,voice)
			player.play()
		var duration: float=voice["definition"]["attack" if active else "release"]
		if duration==0.0:
			set_rain_gain(1.0 if active else 0.0,voice)
			if not active: player.stop()
			continue
		var fade:=create_tween()
		voice["fade"]=fade
		fade.tween_method(set_rain_gain.bind(voice),voice["gain"],1.0 if active else 0.0,duration)
		if not active: fade.tween_callback(player.stop)


func set_rain_gain(gain: float,voice: Dictionary) -> void:
	voice["gain"]=gain
	voice["player"].volume_db=effects_db+float(voice["definition"]["volume_db"])+linear_to_db(maxf(gain,0.0001))


func set_effects_volume(value: float) -> void:
	super.set_effects_volume(value)
	for voice: Dictionary in rain_voices: set_rain_gain(voice["gain"],voice)


func beautify_contact() -> void:
	if not effects_enabled or beautify.is_empty(): return
	# Accepted commands arrive at fixed ticks. Bridge the gap between samples,
	# including a click whose result arrives after its release event.
	beautify_activity = 0.2
	if beautify_voice != null: return
	beautify_voice = AudioStreamPlayer.new()
	beautify_voice.stream = beautify["stream"]
	beautify_gain = 0.0
	set_beautify_gain(beautify_voice, beautify_gain)
	add_child(beautify_voice)
	beautify_voice.play()


func finish_beautify() -> void:
	if beautify_voice == null: return
	beautify_releases.append({"player": beautify_voice, "gain": beautify_gain, "time": 0.0})
	beautify_voice = null
	beautify_activity = 0.0


func set_beautify_gain(player: AudioStreamPlayer, gain: float) -> void:
	player.volume_db = effects_db + float(beautify["volume_db"]) + linear_to_db(maxf(gain, 0.0001))


func stop_beautify() -> void:
	finish_beautify()
	for voice: Dictionary in beautify_releases:
		voice["player"].stop()
		voice["player"].queue_free()
	beautify_releases.clear()


func advance_beautify(delta: float) -> void:
	for index in range(beautify_releases.size() - 1, -1, -1):
		var voice: Dictionary = beautify_releases[index]
		voice["time"] += delta
		var fade := 1.0 - float(voice["time"]) / float(beautify["release"])
		if fade <= 0.0:
			voice["player"].stop()
			voice["player"].queue_free()
			beautify_releases.remove_at(index)
		else:
			set_beautify_gain(voice["player"], float(voice["gain"]) * fade)
	if beautify_voice != null:
		var contact_time := minf(delta, beautify_activity)
		beautify_activity -= contact_time
		beautify_gain = minf(1.0, beautify_gain + contact_time / float(beautify["attack"]))
		set_beautify_gain(beautify_voice, beautify_gain)
		if beautify_activity <= 0.0: finish_beautify()


func _process(delta: float) -> void:
	sculpt_activity -= delta
	if sculpt_activity <= 0 and sculpt.playing: set_sculpting(false)
	advance_beautify(delta)


func _exit_tree() -> void:
	super._exit_tree()
	music.stream_paused = false
	music.stop()
	music.stream = null
	sculpt.stop()
	sculpt.stream = null
