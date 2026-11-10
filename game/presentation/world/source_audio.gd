extends Node
## Playback-only sound cues; original streams and times are injected by adapters.

var assets: Dictionary = {}
var effects: Array[AudioStreamPlayer] = []
var effects_enabled := true
var effects_db := -15.0
var next_effect := 0
var variants: Dictionary = {}
var played_events: Array[String] = []


func _ready() -> void:
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.volume_db = effects_db
		add_child(player)
		effects.append(player)


func play_event(kind: String) -> void:
	if not effects_enabled or effects.is_empty(): return
	var sample: Variant = assets.get(kind)
	if sample is Array:
		if sample.is_empty(): return
		var index: int = variants.get(kind, 0)
		variants[kind] = index + 1
		sample = sample[index % sample.size()]
	if not sample is AudioStream: return
	var player: AudioStreamPlayer = effects[next_effect % effects.size()]
	next_effect += 1
	player.stream = sample
	player.play()
	played_events.append(kind)
	if played_events.size() > 32: played_events.pop_front()


func advance(cues: Array, before: float, after: float) -> void:
	for cue: Dictionary in cues:
		if float(cue["time"]) > before and float(cue["time"]) <= after:
			play_event(cue["event"])


func stop_effects() -> void:
	for player: AudioStreamPlayer in effects: player.stop()


func set_effects_enabled(value: bool) -> void:
	effects_enabled = value
	if not value: stop_effects()


func _exit_tree() -> void:
	stop_effects()
	for player: AudioStreamPlayer in effects: player.stream = null


func set_effects_volume(value: float) -> void:
	effects_db=value
	for player: AudioStreamPlayer in effects: player.volume_db=value
