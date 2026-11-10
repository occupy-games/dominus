extends RefCounted

const INK := Color("f3f3fa")
const PANEL := Color("d6d6ee")
const GOLD := Color("345d83")
const TEXT := Color("354452")
const MUTED := Color("526579")


static func box(_color: Color, _radius: int = 8, _border := Color.TRANSPARENT) -> StyleBoxTexture:
	# Nine-slice an source panel/button, without drawing replacement art.
	var result := StyleBoxTexture.new()
	result.texture = atlas(Rect2(221, 424, 84, 88))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(side, 25)
	result.content_margin_left = 16
	result.content_margin_right = 16
	result.content_margin_top = 12
	result.content_margin_bottom = 12
	return result


static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.default_font = source_font()
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	for type in ["Button", "OptionButton"]:
		result.set_color("font_color", type, TEXT)
		result.set_stylebox("normal", type, box(PANEL, 8, Color("35505b")))
		result.set_stylebox("hover", type, box(Color("254553"), 8, GOLD))
		result.set_stylebox("pressed", type, box(Color("315666"), 8, GOLD))
		result.set_stylebox("focus", type, box(Color.TRANSPARENT, 8, GOLD))
		result.set_stylebox("disabled", type, box(INK.lightened(0.02)))
	result.set_stylebox("normal", "LineEdit", box(INK, 8, Color("35505b")))
	result.set_stylebox("focus", "LineEdit", box(INK, 8, GOLD))
	result.set_color("font_color", "LineEdit", TEXT)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_stylebox("panel", "PanelContainer", box(PANEL))
	result.set_stylebox("panel", "ItemList", box(INK))
	result.set_stylebox("panel", "Tree", box(INK))
	result.set_stylebox("selected", "Tree", box(Color("315666"), 4))
	result.set_stylebox("selected_focus", "Tree", box(Color("315666"), 4, GOLD))
	result.set_color("font_color", "Tree", TEXT)
	result.set_stylebox("selected", "ItemList", box(Color("315666"), 4))
	result.set_stylebox("selected_focus", "ItemList", box(Color("315666"), 4, GOLD))
	result.set_color("font_color", "ItemList", TEXT)
	result.set_color("font_selected_color", "ItemList", GOLD)
	result.set_stylebox("normal", "TextEdit", box(INK))
	result.set_stylebox("read_only", "TextEdit", box(INK))
	result.set_color("font_readonly_color", "TextEdit", TEXT)
	result.set_stylebox("panel", "PopupMenu", box(PANEL, 8, MUTED))
	return result


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func source_font() -> Font:
	return load("res://assets/fonts/RobotoCondensed-Regular.ttf") as Font


static func serif() -> Font:
	return source_font()


static func atlas(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load("res://assets/extracted/sprites/Atlas_AutoGUI.png")
	texture.region = region
	return texture


static func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 48
	node.pressed.connect(callback)
	return node
