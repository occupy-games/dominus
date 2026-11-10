extends "res://presentation/library/object_preview.gd"
## Source mesh/rig player and explicit source-component lifecycle sequences.

const Actors = preload("res://presentation/world/actors.gd")
const OriginalUnit = preload("res://presentation/world/original_follower.gd")
const Ground = preload("res://presentation/world/exhibit_ground.gd")
const Building = preload("res://presentation/world/assembled_building.gd")
var source_data: Dictionary
var content := Node3D.new()
var ground: Node3D
var unit: Node3D
var tracks: Array = []
var track_choice := OptionButton.new()
var play_button: Button
var timeline := HSlider.new()
var time_label: Label
var note: Label
var playing := false
var looped := true
var speed := 1.0
var playhead := 0.0
var duration := 0.0
var active_track := 0
var active_stage := -1
var fixed_scale := 0.0
var clip_cache: Dictionary = {}
var building: Node3D
var building_id := ""
var cue_audio := preload("res://presentation/world/source_audio.gd").new()


func _ready() -> void:
	cue_audio.assets = source_data.get("audio_events", {})
	add_child(cue_audio)
	model = {"parts": []}
	show_parts = false
	super._ready()
	build_player()


func bounds_of(data: Dictionary) -> AABB:
	var bounds := AABB()
	var first := true
	for vertex: Array in data["vertices"]:
		var point := Vector3(vertex[0], vertex[1], vertex[2])
		if first:
			bounds = AABB(point, Vector3.ZERO)
			first = false
		else: bounds = bounds.expand(point)
	return bounds


func build_meshes() -> void:
	pivot.add_child(content)
	if not source_data.get("building", {}).is_empty():
		display_building(source_data["building"])
	else: display_model(source_data)


func clear_content() -> void:
	unit = null
	building = null
	building_id = ""
	for child in content.get_children(): child.free()
	if is_instance_valid(ground): ground.free()


func add_ground(bounds: AABB, factor: float) -> void:
	var kind: String = source_data.get("environment", "land")
	var height := -bounds.size.y * factor * 0.5 - 0.03
	ground = Ground.patch(kind, Vector2(8, 8), height)
	if kind == "underwater":
		ground.get_child(0).position.y = maxf(0.2, bounds.size.y * factor * 0.3)
		ground.get_child(0).material_override = Ground.translucent_water(0.38)
	pivot.add_child(ground)


func display_model(data: Dictionary) -> void:
	clear_content()
	var bounds := bounds_of(data)
	var factor := fixed_scale if fixed_scale > 0 else 3.0 / maxf(bounds.size.length(), 0.001)
	var instance := Actors.mesh(data)
	instance.scale = Vector3.ONE * factor
	instance.position = -bounds.get_center() * factor
	content.add_child(instance)
	add_ground(bounds, factor)


func display_building(data: Dictionary) -> void:
	if is_instance_valid(building) and building_id == data["base_id"]: return
	clear_content()
	var assembled := Building.new()
	assembled.data = data
	content.add_child(assembled)
	building = assembled
	building_id = data["base_id"]
	var bounds: AABB = assembled.source_bounds
	var factor := fixed_scale if fixed_scale > 0 else 3.0 / maxf(bounds.size.length(), 0.001)
	assembled.scale = Vector3.ONE * factor
	assembled.position = -bounds.get_center() * factor
	add_ground(bounds, factor)


func build_player() -> void:
	tracks.append({"kind": "static", "name": "Completed building" if not source_data.get("building", {}).is_empty() else "Source mesh"})
	if not source_data.get("building", {}).is_empty() and source_data["descriptor"]["id"] != source_data["building"]["base_id"]:
		tracks.append({"kind": "static", "name": "Selected component", "source_only": true})
	for sequence: Dictionary in source_data.get("sequences", []):
		tracks.append({"kind": "stages", "name": sequence["name"], "stages": sequence["stages"]})
	var motion: Dictionary = source_data.get("animation", {})
	for clip: Dictionary in motion.get("clips", []):
		tracks.append({"kind": "clip", "name": clip["name"], "clip": clip})
	track_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_choice.fit_to_longest_item = false
	track_choice.clip_text = true
	track_choice.get_popup().max_size.y = 420
	for track: Dictionary in tracks: track_choice.add_item(track["name"])
	for unavailable: Dictionary in motion.get("unsupported", []):
		track_choice.add_item(unavailable["name"] + " (unavailable)")
		track_choice.set_item_disabled(track_choice.item_count - 1, true)
		track_choice.set_item_tooltip(track_choice.item_count - 1, unavailable["reason"])
	track_choice.item_selected.connect(select_track)
	add_child(track_choice)
	var controls := HBoxContainer.new()
	play_button = Style.button("Play", toggle_playback)
	controls.add_child(play_button)
	controls.add_child(Style.button("Restart", func() -> void:
		seek_to(0)
		playing = duration > 0
		update_controls()))
	var loop := CheckButton.new()
	loop.text = "Loop"
	loop.button_pressed = true
	loop.toggled.connect(func(value: bool) -> void: looped = value)
	controls.add_child(loop)
	var sound := CheckButton.new()
	sound.text = "SFX"
	sound.tooltip_text = "Original sound cues where recovered"
	sound.button_pressed = true
	sound.disabled = cue_audio.assets.is_empty()
	sound.toggled.connect(cue_audio.set_effects_enabled)
	controls.add_child(sound)
	var rate := OptionButton.new()
	for value in [0.25, 0.5, 1.0, 2.0]: rate.add_item("%s×" % value)
	rate.selected = 2
	rate.item_selected.connect(func(index: int) -> void: speed = [0.25, 0.5, 1.0, 2.0][index])
	add_child(controls)
	var speed_row := HBoxContainer.new()
	speed_row.add_child(Style.label("Playback speed", 12))
	speed_row.add_child(rate)
	add_child(speed_row)
	timeline.step = 0.001
	timeline.value_changed.connect(func(value: float) -> void: seek_to(value))
	add_child(timeline)
	time_label = Style.label("", 12)
	time_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(time_label)
	note = Style.label("", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var initial := 0
	for index in range(tracks.size()):
		if tracks[index]["kind"] != "static":
			initial = index
			break
	for index in range(tracks.size()):
		if tracks[index]["name"] in ["default_stand_1", "default_stand", "static", "docked"]:
			initial = index
			break
	select_track(initial)


func select_track(index: int) -> void:
	if index < 0 or index >= tracks.size(): return
	cue_audio.stop_effects()
	active_track = index
	track_choice.select(index)
	playhead = 0
	active_stage = -1
	fixed_scale = 0
	var track: Dictionary = tracks[index]
	if track["kind"] == "clip":
		show_clip(track["clip"])
		note.text = "Source clip · root travel removed for inspection."
	elif track["kind"] == "stages":
		duration = track["stages"].size() * 1.5
		var maximum := 0.0
		for stage: Dictionary in track["stages"]:
			maximum = maxf(maximum, bounds_of(stage["model"]).size.length())
		fixed_scale = 3.0 / maxf(maximum, 0.001)
		note.text = "Whole building · recovered source parts and placement. Preview timing is adjustable."
	else:
		duration = 0
		if not source_data.get("building", {}).is_empty() and not track.get("source_only", false):
			display_building(source_data["building"])
			building.set_stage(0, true)
		else: display_model(source_data)
		note.text = "No recovered animation or building stages for this mesh." if tracks.size() == 1 else "Original source mesh at rest."
	playing = duration > 0
	timeline.max_value = maxf(duration, 0.001)
	seek_to(0)
	update_controls()


func show_clip(descriptor: Dictionary) -> void:
	clear_content()
	var motion: Dictionary = source_data["animation"]
	var path: String = descriptor["path"]
	if not clip_cache.has(path): clip_cache[path] = motion["resolve_clip"].call(path)
	var clip: Dictionary = clip_cache[path]
	if clip.is_empty():
		duration = 0
		return
	duration = clip["duration"]
	var mesh := source_data.duplicate(false)
	mesh["bindings"] = motion["bindings"]
	var bounds := bounds_of(source_data)
	var factor := 3.0 / maxf(bounds.size.length(), 0.001)
	var actor := OriginalUnit.new()
	actor.assets = {"bones": motion["bones"], "models": [mesh], "clips": {"preview": clip}}
	actor.animation_state = "preview"
	actor.visual_scale = factor
	var center := bounds.get_center()
	actor.position = Vector3(center.x, -center.y, center.z) * factor
	content.add_child(actor)
	actor.set_process(false)
	unit = actor
	add_ground(bounds, factor)


func seek_to(value: float, from_playback: bool = false) -> void:
	if not from_playback: cue_audio.stop_effects()
	playhead = clampf(value, 0, duration)
	var track: Dictionary = tracks[active_track]
	if track["kind"] == "clip" and is_instance_valid(unit):
		unit.clip_time = minf(playhead, maxf(0, duration - 0.00001))
		unit.apply_animation(0)
	elif track["kind"] == "stages":
		var stages: Array = track["stages"]
		var index := mini(stages.size() - 1, int(playhead / 1.5))
		if index != active_stage:
			active_stage = index
			var assembly: Dictionary = stages[index].get("building", {})
			if not assembly.is_empty():
				display_building(assembly)
				var complete: bool = stages[index]["name"] == "Completed" or track["name"] == "Rank progression"
				var count: int = stages[index].get("part_number", 0)
				building.set_stage(count, complete)
			else: display_model(stages[index]["model"])
			if from_playback and track["name"] == "Construction stages":
				cue_audio.play_event("PLAYSOUND_FOLLOWERSTATEFINISHBUILDING" if stages[index]["name"] == "Completed" else "PLAYSOUND_FOLLOWERHAMMERGROUND")
	timeline.set_value_no_signal(playhead)
	if is_instance_valid(time_label):
		var label: String = track["stages"][active_stage]["name"] if track["kind"] == "stages" else track["name"]
		time_label.text = "%s · %.2f / %.2f s" % [label, playhead, duration]


func toggle_playback() -> void:
	if duration <= 0: return
	if playhead >= duration: seek_to(0)
	playing = not playing
	if not playing: cue_audio.stop_effects()
	update_controls()


func update_controls() -> void:
	play_button.text = "Pause" if playing else "Play"
	play_button.disabled = duration <= 0
	timeline.editable = duration > 0


func _process(delta: float) -> void:
	super._process(delta)
	if not playing: return
	var before := playhead if playhead > 0 else -0.00001
	var next := playhead + delta * speed
	var track: Dictionary = tracks[active_track]
	var cues: Array = source_data.get("animation", {}).get("cues", {}).get(track["name"], [])
	if next >= duration:
		if looped:
			cue_audio.advance(cues, before, duration)
			before = -0.00001
			next = fmod(next, duration)
		else:
			next = duration
			playing = false
			update_controls()
	cue_audio.advance(cues, before, next)
	seek_to(next, true)
