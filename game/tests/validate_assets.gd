extends SceneTree
## Run after editor import: godot --headless --path game --script res://tests/validate_assets.gd


func _initialize() -> void:
	var path := "res://assets/extracted/manifest.json"
	if not FileAccess.file_exists(path):
		push_error("Extract assets before validation")
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary or not manifest.get("assets") is Array or manifest["assets"].is_empty():
		push_error("Missing or empty asset manifest")
		quit(1)
		return
	var failures := 0
	for asset: Dictionary in manifest["assets"]:
		var asset_path: String = "res://assets/extracted/" + asset["output"]
		if FileAccess.get_sha256(asset_path) != asset["sha256"]:
			push_error("Hash mismatch: " + asset_path)
			failures += 1
		var resource := load(asset_path)
		if resource is Texture2D:
			if resource.get_width() <= 0 or resource.get_height() <= 0 or resource.get_image().is_empty():
				failures += 1
		elif resource is AudioStream:
			if resource.get_length() <= 0:
				failures += 1
		elif not resource is Font:
			push_error("Unsupported imported resource: " + asset_path)
			failures += 1
	print("Asset validation: %d resources, %d failures" % [manifest["assets"].size(), failures])
	quit(1 if failures else 0)
