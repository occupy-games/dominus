extends RefCounted
## Read-only access to supplied original game assets; missing content stays unavailable.


func landscape_texture() -> Texture2D:
	var path := "res://assets/extracted/sprites/landscapeDiffuse.png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func chest_glint() -> Dictionary:
	const manifest := "res://assets/original/chest_glint.json"
	const atlas := "res://assets/extracted/VFX/Textures/Misc.png"
	if not FileAccess.file_exists(manifest) or not ResourceLoader.exists(atlas):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not data is Dictionary or data.get("version")!=1:
		return {}
	var source: Dictionary = data.get("source",{})
	if source.get("atlas")!="VFX/Textures/Misc.png" or source.get("atlas_sha256")!=FileAccess.get_sha256(atlas):
		return {}
	var texture := load(atlas) as Texture2D
	var dimensions: Array = data.get("atlas_size",[])
	if texture==null or dimensions.size()!=2 or texture.get_width()!=int(dimensions[0]) or texture.get_height()!=int(dimensions[1]):
		return {}
	data["texture"]=texture
	return data


func follower_assets(opening: bool = false) -> Dictionary:
	var result := animated_assets("followers")
	if opening:
		var roles := {"idle":"default_stand_1","drowning":"default_drowning","hugging_give":"default_stand_1_hug_1_give","hugging_take":"default_stand_1_hug_1_take","worshipping":"default_worship_1","scared":"scared_stand_1"}
		var catalog := preload("res://infrastructure/asset_catalog.gd").new()
		catalog.read_models()
		var recovered := catalog.actor_data("follower.group.bin:7c293053",roles)
		if recovered.get("bones",[])==result["bones"]:
			for role: String in recovered.get("clips",{}): result["clips"][role]=recovered["clips"][role]
	result["audio_cues"] = {}
	var events: Array = []
	for pair: Array in [["idle", "default_stand_1"], ["walking", "default_walk_1"], ["building", "default_hammer_ground_1"]]:
		var cues := preload("res://infrastructure/audio_events.gd").cues("follower.group.bin", pair[1])
		result["audio_cues"][pair[0]] = cues
		for cue: Dictionary in cues: events.append(cue["event"])
	result["audio_events"] = preload("res://infrastructure/audio_events.gd").events(events)
	return result


func animated_assets(name: String) -> Dictionary:
	var path := "res://assets/original/" + name + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("models") is Array:
		return {}
	for model: Dictionary in data["models"]:
		model["texture_resource"] = load("res://assets/original/" + str(model["texture"]))
	return data


func scenery_assets() -> Dictionary:
	var path := "res://assets/original/scenery.json"
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {}
	var imposter_data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/tree_imposters.json"))
	if imposter_data is Dictionary:
		imposter_data["texture"]=load(imposter_data["atlas"])
		var palette: Image=(load("res://assets/extracted/sprites/colours_DNA.png") as Texture2D).get_image()
		imposter_data["foliage_color"]=palette.get_pixel(10,20)
		imposter_data["trunk_color"]=palette.get_pixel(16,20)
		data["trees"]["imposters"]=imposter_data
		var whole: Array=[]
		for i in range(data["trees"]["models"].size()):
			var model: Dictionary=data["trees"]["models"][i]
			for pair: Array in [[0x6b9b87dd,0],[0xb895c49e,2],[0x0590015f,10]]:
				var variant: int=int(model["resource_id"])-int(pair[0])
				if variant>=0 and variant<5:
					model["imposter_index"]=int(pair[1])*5+variant
					whole.append(i)
		data["trees"]["standing"]=whole
	for group: Dictionary in data.values():
		for model: Dictionary in group["models"]:
			model["texture_resource"] = load("res://assets/original/" + model["texture"])
			model["has_alpha"] = false # Solid geometry; alpha is not a blend-mode declaration.
			model["source_shader"] = "shdrTree" if group["source"] == "trees.group.bin" else ""
			model["source_model_id"]=str(group["source"])+":%08x"%int(model["resource_id"])
	# Resolve the same original boulders for independent campaign previews and
	# the front end. Loading them only in FrontEnd left source captures rockless.
	var catalog := preload("res://infrastructure/asset_catalog.gd").new()
	catalog.read_models()
	data["rocks"]={"models":[]}
	for index in range(7):
		var model := catalog.model_data("boulders.group.bin:%08x" % (0x662d9a43+index))
		if not model.is_empty(): data["rocks"]["models"].append(model)
	# Authored Godseed trees use their own original package, not a normal-tree
	# variant sharing the same resource name/hash in another package.
	data["trees"]["variant_count"]=data["trees"]["standing"].size()
	var native_path := "res://assets/original/campaign/homeworld6-scenery.json"
	var native_types: Variant = JSON.parse_string(FileAccess.get_file_as_string(native_path)) if FileAccess.file_exists(native_path) else null
	if native_types is Dictionary:
		for kind in range(15,20):
			var model := catalog.model_data(native_types["types"][str(kind)]["model_id"])
			if model.is_empty(): continue
			model["source_model_id"]=native_types["types"][str(kind)]["model_id"]
			data["trees"]["standing"].append(data["trees"]["models"].size())
			data["trees"]["models"].append(model)
	return data


func terrain_palette() -> Array[Color]:
	# Original swatches selected against the supplied original 2.4 video: warm sandy
	# low terraces and muted yellow-green uplands. No repeating diffuse texture.
	# The complete original biome-to-palette table remains unresolved.
	var image: Image = (load("res://assets/extracted/sprites/colours_DNA.png") as Texture2D).get_image()
	var colors: Array[Color] = []
	# Reference-selected original swatches, preserved without the previous
	# brightness boost. Complete original biome selection is still unresolved.
	for level in range(1,64):
		var point := Vector2i(54,41) if level <= 3 else (Vector2i(2,38) if level <= 12 else Vector2i(27,42))
		colors.append(image.get_pixelv(point))
	return colors


func audio_assets() -> Dictionary:
	# Roles are prototype assignments; numeric IDs preserve the bank provenance.
	var paths := {
		"music": "GodusMain_675198389.ogg",
		"home": "GodusMain_18482418.wav",
		"sheep": "GodusMain_25985861.wav",
		"collect": "BubbleTunes_1104729.wav",
		"rejected": "GodusMain_26271517.wav",
		"victory": "BubbleTunes_8056764.wav",
	}
	var result := {}
	for role: String in paths:
		var path: String = "res://assets/original/audio/" + paths[role]
		if ResourceLoader.exists(path):
			result[role] = load(path)
	var source_events := preload("res://infrastructure/audio_events.gd")
	result.merge(source_events.events(["PLAYSOUND_SCULPTLOOP", "STOPSOUND_SCULPTLOOP", "PLAYSOUND_FOLLOWERSTATEREACTTOCHEST", "PLAYSOUND_FOLLOWERSTATECELEBRATECARD", "Pit of Doom sacrifice", "Fountain celebration", "Shrine belief collection", "PLAYSOUND_GODSEED", "Finger of God impact", "Swamp cast", "Meteor Strike launch", "Meteor Strike impact", "PLAYSOUND_METEORIMPACTWATER"]))
	result["beautify_loop"] = source_events.beautify_loop()
	result["rain_loop"] = source_events.rain_loop()
	return result
