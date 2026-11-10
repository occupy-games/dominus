extends Node


func _ready() -> void:
	if preload("res://infrastructure/content_setup.gd").content_present():
		get_tree().change_scene_to_file.call_deferred("res://application/front_end.tscn")
	else:
		var setup := preload("res://presentation/menu/content_setup.gd").new()
		add_child.call_deferred(setup)
