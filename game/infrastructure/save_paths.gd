extends RefCounted
## Test runners can isolate persistence without changing the player's defaults.


static func directory() -> String:
	var override := OS.get_environment("DOMINUS_SAVE_DIRECTORY")
	return override if not override.is_empty() else "res://../saves"


static func world() -> String:
	var override := OS.get_environment("DOMINUS_SAVE_DIRECTORY")
	return override.path_join("world.sqlite3") if not override.is_empty() else "user://world.sqlite3"
