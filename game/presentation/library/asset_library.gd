extends Control
## Browses detached catalog records; resource access is injected by application.

signal back_requested
signal place_model_requested(id: String)

const Style = preload("res://presentation/ui/style.gd")
const Background = preload("res://presentation/library/preview_background.gd")
const ObjectPreview = preload("res://presentation/library/object_preview.gd")
const CharacterPreview = preload("res://presentation/library/character_preview.gd")
const SourceModelPreview = preload("res://presentation/library/source_model_preview.gd")
var back_label := "←  Main menu"
var model_nodes: Dictionary = {}
var catalog: RefCounted
var search: LineEdit
var category: OptionButton
var only_previewable: CheckButton
var items: Tree
var file_nodes: Dictionary = {}
var folder_nodes: Dictionary = {}
var folder_state: Dictionary = {}
var results: Label
var heading: Label
var metadata: Label
var preview: PanelContainer
var preview_content: VBoxContainer
var status: Label
var player := AudioStreamPlayer.new()
var seek: HSlider
var audio_time: Label
var seeking := false
var filtered: Array = []
var selected_path := ""
var debounce := Timer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(player)
	add_child(debounce)
	debounce.one_shot = true
	debounce.wait_time = 0.18
	debounce.timeout.connect(apply_filters)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	header.add_child(Style.button(back_label, leave))
	var title := Style.label("Asset library", 34)
	title.add_theme_font_override("font", Style.serif())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(Style.label("THE BUILDING BLOCKS OF A WORLD", 12, Style.GOLD))
	column.add_child(header)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	search = LineEdit.new()
	search.placeholder_text = "Search name, folder or format…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_text: String) -> void: debounce.start())
	toolbar.add_child(search)
	category = OptionButton.new()
	category.custom_minimum_size.x = 180
	category.add_item("All categories")
	category.set_item_metadata(0, "")
	category.add_item("Assembled objects")
	category.set_item_metadata(1, "__objects")
	category.add_item("3D models")
	category.set_item_metadata(2, "__models")
	var categories: Array = []
	for entry: Dictionary in catalog.entries:
		if not entry["category"] in categories:
			categories.append(entry["category"])
	categories.sort()
	for key: String in categories:
		category.add_item(key.capitalize().replace("_", " "))
		category.set_item_metadata(category.item_count - 1, key)
	category.item_selected.connect(func(_index: int) -> void: apply_filters())
	toolbar.add_child(category)
	only_previewable = CheckButton.new()
	only_previewable.text = "Previews only"
	only_previewable.tooltip_text = "Media and reconstructed 3D objects with previews"
	only_previewable.toggled.connect(func(_pressed: bool) -> void: apply_filters())
	toolbar.add_child(only_previewable)
	column.add_child(toolbar)
	results = Style.label("", 13, Style.MUTED)
	column.add_child(results)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -100
	column.add_child(split)
	items = Tree.new()
	items.custom_minimum_size.x = 330
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.hide_root = true
	items.allow_reselect = true
	items.add_theme_constant_override("v_separation", 5)
	items.item_selected.connect(select_tree_item)
	items.item_activated.connect(func() -> void:
		var current := items.get_selected()
		if current != null and current.get_metadata(0).get("kind") == "folder":
			current.collapsed = not current.collapsed)
	split.add_child(items)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 420
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 12)
	split.add_child(detail)
	heading = Style.label("Select an asset", 23, Style.GOLD)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(heading)
	metadata = Style.label("", 12, Style.MUTED)
	metadata.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(metadata)
	preview = Background.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.y = 160
	detail.add_child(preview)
	preview_content = VBoxContainer.new()
	preview_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(preview_content)
	status = Style.label("", 13, Style.MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(status)
	if not catalog.error_message.is_empty():
		show_message(catalog.error_message)
	if selected_path.is_empty():
		selected_path = "object:" + str(catalog.assemblies[0]["id"]) if not catalog.assemblies.is_empty() else "sprites/pack_treeImposters_v2.png"
	apply_filters()
	search.grab_focus()


func apply_filters() -> void:
	debounce.stop()
	var query := search.text.strip_edges().to_lower()
	var chosen: String = category.get_selected_metadata()
	for path: String in folder_nodes:
		folder_state[path] = folder_nodes[path].collapsed
	filtered.clear()
	file_nodes.clear()
	model_nodes.clear()
	folder_nodes.clear()
	items.clear()
	var root := items.create_item()
	var objects_root := items.create_item(root)
	objects_root.set_text(0, "Assembled objects")
	objects_root.set_metadata(0, {"kind": "folder"})
	var models_root := items.create_item(root)
	models_root.set_text(0, "3D models")
	models_root.set_metadata(0, {"kind": "folder"})
	var groups := {}
	for descriptor: Dictionary in catalog.models:
		if not chosen.is_empty() and chosen != "__models":
			continue
		if not query.is_empty() and not query in (descriptor["source"] + " " + descriptor["name"] + " " + descriptor["id"]).to_lower():
			continue
		var group: String = descriptor["source"]
		if not groups.has(group):
			var branch := items.create_item(models_root)
			branch.set_text(0, group)
			branch.set_metadata(0, {"kind": "folder"})
			branch.collapsed = query.is_empty()
			groups[group] = branch
		var model := items.create_item(groups[group])
		model.set_text(0, "%s · %d triangles" % [descriptor["name"], descriptor["triangles"]])
		model.set_metadata(0, {"kind": "model", "id": descriptor["id"]})
		model.set_tooltip_text(0, descriptor["id"])
		model_nodes[descriptor["id"]] = model
	models_root.set_text(0, "3D models · %d" % model_nodes.size())
	models_root.visible = not model_nodes.is_empty()
	for descriptor: Dictionary in catalog.unsupported_models:
		if not query.is_empty() and not query in descriptor["source"].to_lower(): continue
		var unsupported := items.create_item(models_root)
		unsupported.set_text(0, descriptor["source"] + " · unsupported geometry")
		unsupported.set_tooltip_text(0, descriptor["reason"])
		unsupported.set_metadata(0, {"kind": "unsupported", "reason": descriptor["reason"]})
	var source_root := items.create_item(root)
	source_root.set_text(0, "Source files")
	source_root.set_metadata(0, {"kind": "folder"})
	var selected: TreeItem
	var matching_assemblies: Dictionary = {}
	var assembly_names: Dictionary = {}
	for descriptor: Dictionary in catalog.assemblies:
		assembly_names[descriptor["id"]] = descriptor["name"]
	for entry: Dictionary in catalog.entries:
		var filename: String=str(entry["path"]).get_file().to_lower()
		if entry["format"] in ["png","jpeg","tga","dds"] and ("logo" in filename or "splash" in filename): continue
		if chosen == "__models":
			continue
		if chosen == "__objects" and entry.get("assembly", "").is_empty():
			continue
		if not chosen.is_empty() and chosen != "__objects" and entry["category"] != chosen:
			continue
		if only_previewable.button_pressed and entry.get("preview", "").is_empty() and entry.get("assembly", "").is_empty() and not entry.get("character", false):
			continue
		if not query.is_empty() and not query in (str(entry["path"]) + " " + str(entry["format"]) + " " + str(assembly_names.get(entry.get("assembly", ""), ""))).to_lower():
			continue
		var index := filtered.size()
		filtered.append(entry)
		if not entry.get("assembly", "").is_empty():
			matching_assemblies[entry["assembly"]] = true
		var path: String = entry["path"]
		var parent := source_root
		var parent_path := ""
		var segments := path.split("/")
		for i in range(segments.size() - 1):
			parent_path = segments[i] if parent_path.is_empty() else parent_path + "/" + segments[i]
			if not folder_nodes.has(parent_path):
				var folder := items.create_item(parent)
				folder.set_text(0, display_text(segments[i]))
				folder.set_custom_color(0, Style.MUTED)
				folder.set_metadata(0, {"kind": "folder", "path": parent_path})
				folder.collapsed = folder_state.get(parent_path, query.is_empty() and chosen.is_empty())
				folder_nodes[parent_path] = folder
			parent = folder_nodes[parent_path]
		var leaf := items.create_item(parent)
		leaf.set_text(0, display_text(path.get_file()))
		leaf.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
		leaf.set_tooltip_text(0, display_text("%s\n%s · %s" % [path, entry["format"], human_size(entry["size"])]))
		leaf.set_metadata(0, {"kind": "asset", "index": index})
		file_nodes[path] = leaf
		if entry.get("character", false):
			for variant in range(2):
				var character := items.create_item(leaf)
				character.set_text(0, "Male follower" if variant == 0 else "Female follower")
				character.set_metadata(0, {"kind": "character", "variant": variant})
				character.collapsed = true
				for clip: String in ["idle", "walking", "building"]:
					var animation := items.create_item(character)
					animation.set_text(0, clip.capitalize() + " animation · 32 bones")
					animation.set_metadata(0, {"kind": "character", "variant": variant, "clip": clip})
			leaf.collapsed = true
		if path == selected_path:
			selected = leaf
	for assembly: Dictionary in catalog.assemblies:
		if not matching_assemblies.has(assembly["id"]):
			continue
		var object_item := items.create_item(objects_root)
		object_item.set_text(0, "%s · %d parts" % [assembly["name"], assembly["parts"].size()])
		object_item.set_custom_color(0, Style.GOLD)
		object_item.set_metadata(0, {"kind": "object", "id": assembly["id"]})
		if selected_path == "object:" + assembly["id"]:
			selected = object_item
		for part: Dictionary in assembly["parts"]:
			var component := items.create_item(object_item)
			component.set_text(0, part["name"])
			component.set_metadata(0, {"kind": "object", "id": assembly["id"], "part": part["name"]})
			component.set_tooltip_text(0, "%s\n%s\n%s" % [part["source"], part["material_source"], part["texture_source"]])
			component.collapsed = true
			for key in ["source", "material_source", "texture_source"]:
				var dependency := items.create_item(component)
				dependency.set_text(0, key.replace("_source", "").capitalize() + ": " + str(part[key]).get_file())
				dependency.set_tooltip_text(0, part[key])
				dependency.set_metadata(0, {"kind": "dependency", "path": part[key]})
	objects_root.visible = objects_root.get_child_count() > 0
	source_root.set_text(0, "Source and decoded assets · %d" % filtered.size())
	results.text = "%s of %s files  /  %d 3D models  /  %d assembled objects  /  %s media previews" % [filtered.size(), catalog.entries.size(), model_nodes.size(), matching_assemblies.size(), catalog.preview_count]
	if filtered.is_empty() and model_nodes.is_empty():
		clear_preview()
		heading.text = "No assets found" if not catalog.entries.is_empty() else "Your library is waiting"
		metadata.text = ""
		status.text = "Clear the search or choose another category." if not catalog.entries.is_empty() else ""
		show_message(catalog.error_message if not catalog.error_message.is_empty() else "Try another name, folder or format.")
		return
	if selected_path.begins_with("model:") and model_nodes.has(selected_path.trim_prefix("model:")):
		selected = model_nodes[selected_path.trim_prefix("model:")]
	if selected == null:
		selected = file_nodes[filtered[0]["path"]] if not filtered.is_empty() else model_nodes.values()[0]
	var ancestor := selected.get_parent()
	while ancestor != null:
		ancestor.collapsed = false
		ancestor = ancestor.get_parent()
	items.set_block_signals(true)
	selected.select(0)
	items.set_block_signals(false)
	scroll_to_selection.call_deferred()
	select_tree_item()


func scroll_to_selection() -> void:
	var selected := items.get_selected()
	if selected != null:
		items.scroll_to_item(selected)


func select_tree_item() -> void:
	var selected := items.get_selected()
	if selected == null:
		return
	var data: Dictionary = selected.get_metadata(0)
	if data.get("kind") == "asset":
		select_item(data["index"])
	elif data.get("kind") == "dependency":
		for entry: Dictionary in catalog.entries:
			if entry["path"] == data["path"]:
				show_entry(entry)
				break
	elif data.get("kind") == "object":
		show_object(data["id"], data.get("part", ""))
	elif data.get("kind") == "character":
		show_character(data.get("variant", 0), data.get("clip", "idle"))
	elif data.get("kind") == "model":
		show_model(data["id"])
	elif data.get("kind") == "unsupported":
		clear_preview()
		show_message(data["reason"])


func show_model(id: String) -> void:
	clear_preview()
	selected_path = "model:" + id
	var data: Dictionary = catalog.inspection_data(id)
	if data.is_empty():
		show_message("Model data is missing. Run python3 tools/models.py.")
		return
	var descriptor: Dictionary = data["descriptor"]
	heading.text = descriptor["name"]
	metadata.text = "%s\n%d vertices · %d triangles\nSource SHA-256 %s" % [id, descriptor["vertices"], descriptor["triangles"], descriptor["source_sha256"]]
	if data["material_status"] != "source_texture":
		show_message("This source mesh has an unresolved material. It is unavailable until its original dependencies are recovered.")
		status.text = "No replacement material or asset is used."
		return
	var viewer := SourceModelPreview.new()
	viewer.source_data = data
	preview_content.add_child(viewer)
	var placement := Style.button("Place this model in the world", func() -> void: place_model_requested.emit(id))
	placement.disabled = data["material_status"] != "source_texture"
	preview_content.add_child(placement)
	status.text = "Original source geometry and coordinates. Drag to orbit; wheel to zoom."
	if data["material_status"] != "source_texture":
		status.text += "\nOriginal material is unresolved; this is an untextured geometry inspection."


func show_character(variant: int = 0, clip: String = "idle") -> void:
	clear_preview()
	selected_path = "follower.group.bin"
	heading.text = "Source follower"
	metadata.text = "follower.group.bin · original mesh, texture, skin and 32-bone rig"
	var viewer := CharacterPreview.new()
	viewer.assets = catalog.character_data()
	viewer.variant = variant
	viewer.clip = clip
	preview_content.add_child(viewer)
	preview_content.add_child(Style.button("Browse all original animation clips", func() -> void: show_model("follower.group.bin:7c293053")))
	status.text = "Drag to orbit · wheel to zoom · select a model and animation.\nOriginal idle, walking and building clips; root motion is removed for display."


func show_object(id: String, part: String = "") -> void:
	clear_preview()
	selected_path = "object:" + id
	var model: Dictionary = catalog.assembly_data(id)
	if model.is_empty():
		heading.text = "Object preview unavailable"
		metadata.text = id
		show_message("Rebuild the asset library to regenerate the assembly.")
		status.text = ""
		return
	heading.text = model["name"] + (" / " + part if not part.is_empty() else "")
	metadata.text = "%d components · shared source model\n%s" % [model["parts"].size(), model["origin"]]
	var viewer := ObjectPreview.new()
	viewer.model = model
	preview_content.add_child(viewer)
	status.text = "Drag to orbit · wheel to zoom · toggle parts or explode.\nReconstructed from source geometry; original runtime behavior is not simulated."


func clear_preview() -> void:
	player.stop()
	player.stream_paused = false
	player.stream = null
	seeking = false
	seek = null
	audio_time = null
	for child in preview_content.get_children():
		preview_content.remove_child(child)
		child.queue_free()


func select_item(index: int) -> void:
	if index < 0 or index >= filtered.size():
		return
	show_entry(filtered[index])


func show_entry(entry: Dictionary) -> void:
	clear_preview()
	selected_path = entry["path"]
	heading.text = display_text(selected_path.get_file())
	metadata.text = display_text("%s\n%s   /   %s   /   %s\nSHA-256  %s" % [selected_path, str(entry["category"]).capitalize(), str(entry["format"]).to_upper(), human_size(entry["size"]), entry["sha256"]])
	if entry.get("character", false):
		show_character()
		return
	if not entry.get("assembly", "").is_empty():
		show_object(entry["assembly"])
		return
	var resource: Resource = catalog.preview_resource(entry)
	if resource is Texture2D:
		var image := TextureRect.new()
		image.texture = resource
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview_content.add_child(image)
		status.text = "%d × %d pixels  ·  Original image fitted to view." % [resource.get_width(), resource.get_height()]
	elif resource is AudioStream:
		show_audio(resource)
	elif resource is Font:
		var sample := Style.label("Aa Bb Cc\nDominus\nA world in your hands.\n0123456789", 34)
		sample.add_theme_font_override("font", resource)
		sample.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview_content.add_child(scroll)
		scroll.add_child(sample)
		status.text = "Font specimen  ·  Glyph coverage depends on the source font."
	else:
		var excerpt: String = entry.get("text_excerpt", "")
		var text := TextEdit.new()
		text.editable = false
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text.text = display_text(excerpt) if not excerpt.is_empty() else "BINARY EXCERPT / FIRST 128 BYTES\n\n" + str(entry.get("hex_excerpt", ""))
		preview_content.add_child(text)
		status.text = "Text excerpt · first 4 KiB." if not excerpt.is_empty() else "Visual/audio decoding is not available for this format. Source details and raw bytes are shown."
		if not entry.get("preview", "").is_empty():
			status.text = "Preview file is missing or could not load. Rebuild the library; raw content is shown."


func show_audio(stream: AudioStream) -> void:
	player.stream = stream
	var symbol := Style.label("♫", 80, Style.GOLD)
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_content.add_child(symbol)
	audio_time = Style.label("0:00 / " + duration(stream.get_length()), 16)
	preview_content.add_child(audio_time)
	seek = HSlider.new()
	seek.max_value = maxf(stream.get_length(), 0.01)
	seek.step = 0.1
	seek.drag_started.connect(func() -> void: seeking = true)
	seek.value_changed.connect(func(value: float) -> void:
		if player.playing:
			player.seek(value))
	seek.drag_ended.connect(func(changed: bool) -> void:
		seeking = false
		if changed:
			if not player.playing:
				player.play(seek.value)
			else:
				player.seek(seek.value))
	preview_content.add_child(seek)
	var controls := HBoxContainer.new()
	controls.add_child(Style.button("Play / pause", func() -> void:
		if player.playing:
			player.stream_paused = not player.stream_paused
		else:
			player.stream_paused = false
			player.play()))
	controls.add_child(Style.button("Stop", func() -> void:
		player.stop()
		player.stream_paused = false
		seek.value = 0))
	preview_content.add_child(controls)
	status.text = "Audio preview  ·  Playback starts only when you press Play."


func _process(_delta: float) -> void:
	if is_instance_valid(seek) and player.stream != null:
		var position := player.get_playback_position() if player.playing else 0.0
		if not seeking:
			seek.set_value_no_signal(position)
		audio_time.text = duration(position) + " / " + duration(player.stream.get_length())


func show_message(text: String) -> void:
	var message := Style.label(text, 17, Style.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_content.add_child(message)


func leave() -> void:
	player.stop()
	back_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()


static func human_size(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MiB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KiB" % (bytes / 1024.0)
	return "%d B" % bytes


static func duration(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func display_text(value: String) -> String:
	return value.replace("GodusMain","Main").replace("Godus","Dominus").replace("godus","source")
