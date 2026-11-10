extends RefCounted
## Filesystem/process adapter for the installer setup screen.

var worker := -1
var root_path := OS.get_environment("DOMINUS_RUNTIME_DIRECTORY")
var bundle := OS.get_environment("DOMINUS_BUNDLE")


func _init() -> void:
	if root_path.is_empty(): root_path=ProjectSettings.globalize_path("res://..").simplify_path()
	if bundle.is_empty(): bundle=root_path


static func content_present() -> bool:
	for path: String in ["original/models/catalog.json","original/cards_24/catalog.json","original/campaign/homeworld-runtime.json","library/catalog.json"]:
		if not FileAccess.file_exists("res://assets/"+path): return false
	return true


func python() -> String:
	var configured := OS.get_environment("DOMINUS_PYTHON")
	if not configured.is_empty(): return configured
	return "/opt/homebrew/bin/python3" if FileAccess.file_exists("/opt/homebrew/bin/python3") else "python3"


func in_process() -> bool:
	return OS.get_environment("DOMINUS_BUNDLE").is_empty()


func start() -> bool:
	if running(): return true
	DirAccess.remove_absolute(root_path.path_join("setup-status.json"))
	worker=OS.create_process(python(),PackedStringArray([root_path.path_join("tools/setup_content.py"),"--root",root_path,"--bundle",bundle,"--status",root_path.path_join("setup-status.json")]))
	return worker>=0


func running() -> bool:
	return worker>0 and OS.is_process_running(worker)


func status() -> Dictionary:
	var path := root_path.path_join("setup-status.json")
	if not FileAccess.file_exists(path): return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func launch_game() -> bool:
	worker=-1
	var arguments := PackedStringArray(["--path",root_path.path_join("game")])
	var requested: Variant=JSON.parse_string(OS.get_environment("DOMINUS_LAUNCH_ARGUMENTS"))
	if requested is Array:
		for argument: Variant in requested:
			if argument is String: arguments.append(argument)
	if not "--log-file" in arguments:
		arguments.insert(2,"--log-file")
		arguments.insert(3,root_path.path_join("session.log"))
	var process := OS.create_process(bundle.path_join("engine"),arguments)
	if process>=0:
		var record := FileAccess.open(root_path.path_join("game-process.json"),FileAccess.WRITE)
		if record!=null: record.store_string(JSON.stringify({"pid":process})); record.close()
	return process>=0


func stop() -> void:
	if running(): OS.execute(python(),PackedStringArray([root_path.path_join("tools/setup_content.py"),"--stop",str(worker)]))
	worker=-1
