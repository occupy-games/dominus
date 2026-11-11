extends RefCounted
## Original bank links and VFX marker times. Filesystem access stays in this adapter.

static var manifest: Dictionary = {}
static var streams: Dictionary = {}


static func read() -> Dictionary:
	if manifest.is_empty():
		var path := "res://assets/original/audio_events.json"
		if FileAccess.file_exists(path):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary: manifest = data
	return manifest


static func cues(source: String, clip: String) -> Array:
	var group := source.get_file().trim_suffix(".group.bin")
	if "follower" in group: group = "follower"
	var tracks: Dictionary = read().get("animation_cues", {})
	for key: String in [group + "_" + clip, clip]:
		if tracks.has(key): return tracks[key]["markers"].duplicate(true)
	return []


static func events(names: Array) -> Dictionary:
	var result := {}
	var definitions: Dictionary = read().get("events", {})
	for name: String in names:
		if result.has(name) or not definitions.has(name): continue
		if definitions[name].has("layers"):
			var mix := layered_effect(definitions[name]["layers"])
			if mix!=null: result[name]=mix
			continue
		var samples: Array = []
		for relative: String in definitions[name]["default_media"]:
			if not relative.begins_with("audio/") or ".." in relative.split("/"): continue
			if not streams.has(relative): streams[relative] = load("res://assets/original/" + relative)
			if streams[relative] is AudioStream: samples.append(streams[relative])
		if not samples.is_empty(): result[name] = samples
	return result


static func layered_effect(layers: Array) -> AudioStreamSynchronized:
	var mix := AudioStreamSynchronized.new()
	mix.stream_count=layers.size()
	for index in range(layers.size()):
		var layer: Dictionary=layers[index]
		var relative: String=layer["media"]
		if not relative.begins_with("audio/") or ".." in relative.split("/"): return null
		var source := load("res://assets/original/"+relative) as AudioStreamWAV
		if source==null: return null
		var variants := AudioStreamRandomizer.new()
		for pitch: float in layer["pitch_cents"]:
			var sample := source.duplicate() as AudioStreamWAV
			sample.mix_rate=roundi(source.mix_rate*pow(2.0,pitch/1200.0))
			variants.add_stream(variants.streams_count,sample)
		mix.set_sync_stream(index,variants)
		mix.set_sync_stream_volume(index,float(layer["volume_db"]))
	return mix


static func beautify_loop() -> Dictionary:
	var data: Dictionary = read().get("beautify_loop", {})
	var attack := float(data.get("attack_ms", 0)) / 1000.0
	var release := float(data.get("release_ms", 0)) / 1000.0
	if attack <= 0.0 or release <= 0.0: return {}
	var samples: Array = events(["PLAYSOUND_BEAUTIFY"]).get("PLAYSOUND_BEAUTIFY", [])
	if samples.size() != 1 or not samples[0] is AudioStreamWAV: return {}
	var source: AudioStreamWAV = samples[0]
	var frames := int(data.get("loop_frames", 0))
	if frames <= 0 or source.mix_rate != int(data.get("sample_rate", 0)) or roundi(source.get_length() * source.mix_rate) != frames:
		return {}
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return {"stream": stream, "attack": attack, "release": release, "volume_db": float(data["volume_db"])}


static func rain_loop() -> Array:
	var voices := []
	for voice: Dictionary in read().get("rain_loop",{}).get("voices",[]):
		var relative: String=voice["media"]
		if not relative.begins_with("audio/") or ".." in relative.split("/"): return []
		var path: String="res://assets/original/"+relative
		if not ResourceLoader.exists(path): return []
		var sample:=load(path) as AudioStreamWAV
		var frames: int=voice["loop_frames"]
		if sample==null or sample.mix_rate!=int(voice["sample_rate"]) or roundi(sample.get_length()*sample.mix_rate)!=frames:
			return []
		var stream:=sample.duplicate() as AudioStreamWAV
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=frames
		voices.append({"stream":stream,"volume_db":float(voice["volume_db"]),
			"attack":float(voice["attack_ms"])/1000.0,"release":float(voice["release_ms"])/1000.0})
	return voices
