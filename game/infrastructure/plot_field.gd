extends RefCounted


static func load_field(pack_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/plot-field.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("pack_sha256")!=pack_sha256 or data.get("width")!=1024 or data.get("field")!="plotrot" or not data.get("overrides") is Array: return {}
	var result := {"default":data.get("default"),"values":{},"sha256":data.get("sha256")}
	for entry: Variant in data["overrides"]:
		if not entry is Array or entry.size()!=2 or not preload("res://simulation/source_plot_schedule.gd").integer_between(entry[0],0,1024*1024-1): return {}
		var key := str(int(entry[0]))
		if result["values"].has(key): return {}
		result["values"][key]=entry[1]
	if not preload("res://simulation/source_plot_field.gd").valid(result): return {}
	var bytes := PackedByteArray()
	bytes.resize(1024*1024)
	bytes.fill(int(result["default"]))
	for key: String in result["values"]: bytes[int(key)]=int(result["values"][key])
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return result if hash.finish().hex_encode()==result["sha256"] else {}
