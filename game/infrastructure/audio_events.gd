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
		var samples: Array = []
		for relative: String in definitions[name]["default_media"]:
			if not relative.begins_with("audio/") or ".." in relative.split("/"): continue
			if not streams.has(relative): streams[relative] = load("res://assets/original/" + relative)
			if streams[relative] is AudioStream: samples.append(streams[relative])
		if not samples.is_empty(): result[name] = samples
	return result
