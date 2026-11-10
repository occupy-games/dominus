extends RefCounted
## JSON preferences are independent of saved simulation data.
var path := "res://../config/settings.json"
var defaults_path := "res://../config/settings.defaults.json"
var definitions: Dictionary = {}
var values: Dictionary = {}
var error := ""


func read() -> void:
	error=""
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(defaults_path))
	definitions=defaults.get("groups",{}) if defaults is Dictionary else {}
	if definitions.is_empty(): error="Settings defaults are unavailable."
	values=default_values()
	if not FileAccess.file_exists(path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("schema_version")!=1 or not parsed.get("values") is Dictionary:
		error="Settings JSON is invalid; defaults are in use."
		return
	for key: String in parsed["values"]:
		if valid_value(key,parsed["values"][key]): values[key]=parsed["values"][key]
	if parsed["values"].size()!=values.size(): write()


func default_values() -> Dictionary:
	var result := {}
	for group: String in definitions:
		for key: String in definitions[group]["settings"]: result[group+"."+key]=definitions[group]["settings"][key]["default"]
	return result


func valid_value(key: String,value: Variant) -> bool:
	var parts := key.split(".")
	if parts.size()!=2 or not definitions.has(parts[0]) or not definitions[parts[0]]["settings"].has(parts[1]): return false
	var spec: Dictionary = definitions[parts[0]]["settings"][parts[1]]
	if spec["type"]=="bool": return value is bool
	if not (value is int or value is float) or not is_finite(float(value)): return false
	if spec["type"]=="enum": return value==int(value) and value>=0 and value<spec["choices"].size()
	return value>=spec["min"] and value<=spec["max"]


func change(key: String,value: Variant) -> Dictionary:
	if not valid_value(key,value): return {"ok":false,"message":"Invalid setting value."}
	values[key]=value
	return write()


func reset(prefix: String = "") -> Dictionary:
	var defaults := default_values()
	for key: String in defaults:
		if prefix.is_empty() or key==prefix or key.begins_with(prefix+"."): values[key]=defaults[key]
	return write()


func write() -> Dictionary:
	var filename := ProjectSettings.globalize_path(path)
	var directory := filename.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(filename+".tmp",FileAccess.WRITE)
	if file==null: return {"ok":false,"message":"Could not write settings JSON."}
	file.store_string(JSON.stringify({"schema_version":1,"values":values},"  ")+"\n")
	file.close()
	var code := DirAccess.rename_absolute(filename+".tmp",filename)
	return {"ok":code==OK,"message":"Settings saved." if code==OK else "Could not replace settings JSON."}
