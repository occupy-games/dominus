extends RefCounted
## Test runners can isolate persistence without changing the player's defaults.


static func directory() -> String:
	var override := OS.get_environment("DOMINUS_SAVE_DIRECTORY")
	return override if not override.is_empty() else "res://../saves"


static func world() -> String:
	var override := OS.get_environment("DOMINUS_SAVE_DIRECTORY")
	return override.path_join("world.sqlite3") if not override.is_empty() else "user://world.sqlite3"


static func opening() -> String:
	return directory().path_join("homeworld6-opening.sqlite")


static func weyworld() -> String:
	return directory().path_join("weyworld-ark.sqlite")


static func continuation() -> String:
	var latest := world()
	for candidate: String in [opening(),weyworld()]:
		if FileAccess.file_exists(candidate) and (not FileAccess.file_exists(latest) or FileAccess.get_modified_time(candidate)>=FileAccess.get_modified_time(latest)):
			latest=candidate
	return latest
