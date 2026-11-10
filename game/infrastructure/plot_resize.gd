extends RefCounted
## Source-derived finite branch tables; no emulator is used by the game.


static func load_rules(executable_sha256: String) -> Dictionary:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/plot-resize-rules.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("executable_sha256")!=executable_sha256: return {}
	var rate: Variant=metadata.get("progress_rate")
	if not (rate is int or rate is float) or not is_finite(float(rate)) or float(rate)<=0: return {}
	var result := {"progress_rate":preload("res://simulation/source_terrain.gd").f32(float(rate))}
	for key: String in ["growth","repair"]:
		var info: Dictionary=metadata[key]
		var bytes := FileAccess.get_file_as_bytes("res://assets/original/"+info["path"])
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if hash.finish().hex_encode()!=info["sha256"] or bytes.size()!=int(info["count"]): return {}
		result[key]=Array(bytes)
	return result if preload("res://simulation/source_plot_resize.gd").valid_rules(result) else {}
