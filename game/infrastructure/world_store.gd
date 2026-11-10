extends RefCounted
## Replaceable desktop SQLite adapter. Python owns DB access, never simulation.

var decode_error := ""
var database_path := preload("res://infrastructure/save_paths.gd").world()


func exists() -> bool:
	return FileAccess.file_exists(database_path)


func save_world(data: Dictionary) -> Dictionary:
	var encoded: Dictionary = encode_numbers(data)
	encoded["numeric_encoding"]="ieee754-le-v1"
	return _invoke("save", JSON.stringify(encoded,"",true,true))


func load_world() -> Dictionary:
	var result := _invoke("load")
	if result.get("ok",false) and result.get("data",{}).get("numeric_encoding")=="ieee754-le-v1":
		decode_error=""
		result["data"]=decode_numbers(result["data"])
		if not decode_error.is_empty(): return {"ok":false,"message":decode_error}
		result["data"].erase("numeric_encoding")
	return result


func _invoke(action: String, data: String = "") -> Dictionary:
	if action=="save": DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(database_path).get_base_dir())
	var bridge := ProjectSettings.globalize_path("res://../tools/save_game.py")
	if not FileAccess.file_exists(bridge):
		return {"ok": false, "message": "SQLite save helper is missing. Run from the source checkout."}
	var executable := "/opt/homebrew/bin/python3" if FileAccess.file_exists("/opt/homebrew/bin/python3") else "python3"
	if not OS.get_environment("DOMINUS_PYTHON").is_empty(): executable=OS.get_environment("DOMINUS_PYTHON")
	var arguments := PackedStringArray([bridge, action, ProjectSettings.globalize_path(database_path)])
	var request_path := ""
	if action == "save":
		if data.length() < 80000: arguments.append(Marshalls.utf8_to_base64(data))
		else:
			request_path = ProjectSettings.globalize_path(database_path) + ".request-%d.json" % get_instance_id()
			var request := FileAccess.open(request_path, FileAccess.WRITE)
			if request == null: return {"ok": false, "message": "Could not prepare campaign save."}
			request.store_string(data)
			request.close()
			arguments.append("--json-file")
			arguments.append(request_path)
	var output: Array = []
	var code := OS.execute(executable, arguments, output, false)
	if not request_path.is_empty(): DirAccess.remove_absolute(request_path)
	if not output.is_empty():
		var result: Variant = JSON.parse_string(str(output[0]).strip_edges())
		if result is Dictionary:
			return result
	return {"ok": false, "message": "SQLite storage needs Python 3 on this desktop (exit %d)." % code}


func encode_numbers(value: Variant) -> Variant:
	# Decimal parsers across the Godot/Python bridge may round differently by
	# one ULP. Preserve IEEE-754 bits in JSON while keeping only plain data.
	if value is float:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0,value)
		return {"$f64":bytes.hex_encode()}
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key]=encode_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(encode_numbers(item))
		return result
	return value


func decode_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size()==1 and value.has("$f64"):
			var encoded: Variant = value["$f64"]
			if not encoded is String or encoded.length()!=16:
				decode_error="Invalid floating-point data in saved game."
				return 0.0
			for character: int in encoded.to_ascii_buffer():
				if not character in "0123456789abcdef".to_ascii_buffer():
					decode_error="Invalid floating-point data in saved game."
					return 0.0
			var number: float = encoded.hex_decode().decode_double(0)
			if not is_finite(number): decode_error="Non-finite value in saved game."
			return number
		var result := {}
		for key: Variant in value: result[key]=decode_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(decode_numbers(item))
		return result
	return value
