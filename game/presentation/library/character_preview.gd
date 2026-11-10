extends "res://presentation/library/object_preview.gd"
## Uses the same original skinned mesh and animation playback as the world view.

const OriginalFollower = preload("res://presentation/world/original_follower.gd")
var assets: Dictionary
var variant := 0
var clip := "idle"
var human: Node3D


func _ready() -> void:
	model = {"parts": []}
	show_parts = false
	super._ready()
	var choices := HBoxContainer.new()
	var model_choice := OptionButton.new()
	model_choice.add_item("Male")
	model_choice.add_item("Female")
	model_choice.selected = variant
	model_choice.item_selected.connect(func(value: int) -> void:
		variant = value
		human.free()
		build_meshes())
	choices.add_child(model_choice)
	var animation := OptionButton.new()
	var clips := ["idle", "walking", "building"]
	for key: String in clips:
		animation.add_item(key.capitalize())
	animation.selected = clips.find(clip)
	animation.item_selected.connect(func(value: int) -> void:
		clip = clips[value]
		human.animation_state = clip)
	choices.add_child(animation)
	var pause := CheckButton.new()
	pause.text = "Pause animation"
	pause.toggled.connect(func(value: bool) -> void: human.set_process(not value))
	choices.add_child(pause)
	add_child(choices)
	move_child(choices, 0)


func build_meshes() -> void:
	human = OriginalFollower.new()
	human.assets = assets
	human.variant = variant
	human.animation_state = clip
	pivot.add_child(human)
	human.scale = Vector3.ONE * 0.009
	human.position.y = -1.0
