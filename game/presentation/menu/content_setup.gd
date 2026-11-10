extends Control

var message := Label.new()
var progress := ProgressBar.new()
var retry := Button.new()
var setup := preload("res://infrastructure/content_setup.gd").new()
var active := false


func _ready() -> void:
	get_tree().auto_accept_quit=false
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation",24)
	column.offset_left=44; column.offset_top=48; column.offset_right=-44; column.offset_bottom=-40
	add_child(column)
	var heading := Label.new()
	heading.text="Dominus"
	heading.add_theme_font_size_override("font_size",38)
	column.add_child(heading)
	message.text="Preparing first launch…"
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y=62
	column.add_child(message)
	column.add_child(progress)
	retry.text="Retry setup"
	retry.visible=false
	retry.pressed.connect(start)
	column.add_child(retry)
	start()


func start() -> void:
	retry.visible=false
	active=setup.start()
	if not active: message.text="Could not start content setup."; retry.visible=true


func _process(_delta: float) -> void:
	if not active: return
	var status := setup.status()
	if status.is_empty():
		if not setup.running(): active=false; message.text="Setup stopped. See setup.log in the runtime folder."; retry.visible=true
		return
	message.text=str(status.get("message","Preparing content…"))
	progress.value=float(status.get("progress",0))*100
	if status.get("stage")=="error": active=false; retry.visible=true
	elif status.get("stage")=="ready":
		active=false
		if setup.in_process():
			get_tree().auto_accept_quit=true
			get_tree().change_scene_to_file("res://application/front_end.tscn")
		elif setup.launch_game(): get_tree().quit()
		else: message.text="Could not start Dominus."; retry.visible=true
	elif not setup.running():
		active=false; message.text="Setup stopped. See setup.log in the runtime folder."; retry.visible=true


func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		setup.stop()
		get_tree().quit()
