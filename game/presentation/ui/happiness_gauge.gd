extends Control
## Exact native atlas art; the simulation supplies both tribe values.

var textures: Dictionary = {}
var gradient := TextureRect.new()
var player := TextureRect.new()
var astari := TextureRect.new()
var values := {"player":0.0,"astari":0.0}


func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	modulate.a=0.65
	for entry: Array in [[gradient,"happiness_gradient",Vector2(8,165)],[player,"happiness_player",Vector2(28,25.7)],[astari,"happiness_astari",Vector2(28,23.8)]]:
		var node: TextureRect = entry[0]
		node.texture=textures.get(entry[1])
		node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.size=entry[2]
		add_child(node)
	gradient.stretch_mode=TextureRect.STRETCH_SCALE
	apply_values(values)


func apply_values(data: Dictionary) -> void:
	values=data.duplicate(true)
	player.position=Vector2(-29,(1-clampf(float(values.get("player",0)),0,1))*165-player.size.y/2)
	astari.position=Vector2(9,(1-clampf(float(values.get("astari",0)),0,1))*165-astari.size.y/2)
	player.tooltip_text="Your followers: %d%%"%roundi(float(values.get("player",0))*100)
	astari.tooltip_text="Astari: %d%%"%roundi(float(values.get("astari",0))*100)
