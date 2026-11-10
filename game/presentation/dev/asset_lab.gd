extends Control
## Local asset inspection, with audio playback only on explicit button press.

const MANIFEST := "res://assets/extracted/manifest.json"
var player := AudioStreamPlayer.new()


func _ready() -> void:
	add_child(player)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)
	var title := Label.new()
	title.text = "DOMINUS / Asset Lab"
	title.add_theme_font_size_override("font_size", 30)
	list.add_child(title)
	if not FileAccess.file_exists(MANIFEST):
		var help := Label.new()
		help.text = "Run python3 tools/assets.py inventory, then python3 tools/assets.py extract from the repository root."
		list.add_child(help)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary or not manifest.get("assets") is Array:
		push_error("Invalid asset manifest")
		return
	for asset: Dictionary in manifest["assets"]:
		var label := Label.new()
		label.text = "%s — %s" % [asset["role"], asset["source"]]
		list.add_child(label)
		var path: String = "res://assets/extracted/" + asset["output"]
		var resource := load(path)
		if resource is Texture2D:
			var preview := TextureRect.new()
			preview.texture = resource
			preview.custom_minimum_size = Vector2(600, 260)
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			list.add_child(preview)
		elif resource is AudioStream:
			var play := Button.new()
			play.text = "Play audio sample"
			play.pressed.connect(func() -> void:
				player.stream = resource
				player.play())
			list.add_child(play)
			var stop := Button.new()
			stop.text = "Stop audio"
			stop.pressed.connect(player.stop)
			list.add_child(stop)
		else:
			push_warning("No preview for " + path)
