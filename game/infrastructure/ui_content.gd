extends RefCounted
## Exact named Scaleform bitmap regions. No replacement HUD artwork.

static func textures() -> Dictionary:
	var path := "res://assets/original/ui/catalog.json"
	if not FileAccess.file_exists(path): return {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result := {}
	for name: String in data["regions"]:
		var region: Dictionary = data["regions"][name]
		var image: Dictionary = data["images"][str(int(region["atlas"]))]
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/original/ui/"+image["name"])
		var rect: Array = region["rect"]
		atlas.region = Rect2(rect[0],rect[1],rect[2],rect[3])
		result[name] = atlas
	# Native original game uses this hand sprite over its empty pink power button.
	var native: Texture2D = load("res://assets/extracted/sprites/Atlas_AutoGUI.png")
	for name: String in data["native_atlas"]["regions"]:
		var rect: Array = data["native_atlas"]["regions"][name]
		var atlas := AtlasTexture.new()
		atlas.atlas = native
		atlas.region = Rect2(rect[0],rect[1],rect[2],rect[3])
		result[name] = atlas
	return result
