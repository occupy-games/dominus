extends RefCounted
## Read-only adapter for the generated catalog. Never touches simulation state.

const PATH := "res://assets/library/catalog.json"
const PREVIEW_ROOT := "res://assets/extracted/"
static var shared_models: Dictionary = {}
var entries: Array = []
var error_message := ""
var preview_count := 0
var assemblies: Array = []
var models: Array = []
var unsupported_models: Array = []
var model_index: Dictionary = {}


func read_catalog() -> void:
	entries.clear()
	error_message = ""
	preview_count = 0
	assemblies.clear()
	models = []
	unsupported_models = []
	model_index.clear()
	if not FileAccess.file_exists(PATH):
		error_message = "The asset library has not been built yet.\nRun from the repository root:\n\npython3 tools/assets.py inventory\npython3 tools/assets.py library"
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("assets") is Array:
		error_message = "The asset catalog could not be read. Rebuild it with python3 tools/assets.py library."
		return
	for entry: Variant in data["assets"]:
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("format") is String:
			error_message = "The asset catalog contains invalid entries. Rebuild the library."
			return
	entries = data["assets"]
	preview_count = int(data.get("preview_count", 0))
	assemblies = data.get("assemblies", [])
	read_models()
	if FileAccess.file_exists("res://assets/original/followers.json"):
		for entry: Dictionary in entries:
			if entry["path"] == "follower.group.bin":
				entry["character"] = true
	var audio_path := "res://assets/original/audio_catalog.json"
	if FileAccess.file_exists(audio_path):
		var audio: Variant = JSON.parse_string(FileAccess.get_file_as_string(audio_path))
		if audio is Dictionary:
			for record: Dictionary in audio.get("assets", []):
				var relative: String = record["path"]
				var path := "res://assets/original/" + relative
				entries.append({"path": "Decoded/" + record["package"] + "/" + relative.get_file(),
					"category": "original_music" if record["music_track"] else "original_audio",
					"format": relative.get_extension(), "size": FileAccess.get_file_as_bytes(path).size(),
					"sha256": record["source_media_sha256"], "preview": "@original/" + relative,
					"text_excerpt": "Source: " + record["source"]})
				preview_count += 1


static func model_records() -> Dictionary:
	if shared_models.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/models/catalog.json"))
		if data is Dictionary: shared_models = preload("res://simulation/immutable_data.gd").freeze(data)
	return shared_models


func read_models() -> void:
	var data := model_records()
	models = data.get("models", [])
	unsupported_models = data.get("unsupported", [])
	model_index.clear()
	for descriptor: Dictionary in models: model_index[descriptor["id"]] = descriptor


func character_data() -> Dictionary:
	return preload("res://infrastructure/game_content.gd").new().follower_assets()


func model_definitions() -> Dictionary:
	var definitions := {}
	for descriptor: Dictionary in models:
		if descriptor["material_status"] != "source_texture": continue
		definitions[descriptor["id"]] = {"name": descriptor["name"]}
	return definitions


func model_data(id: String) -> Dictionary:
	if model_index.has(id):
		var descriptor: Dictionary = model_index[id]
		var path: String = descriptor["geometry"]
		if path.is_absolute_path() or ".." in path.split("/"):
			return {}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/models/" + path))
		if not data is Dictionary:
			return {}
		var texture: String = data.get("texture", "")
		data["texture_resource"] = load("res://assets/original/models/" + texture) if not texture.is_empty() else null
		data["descriptor"] = descriptor
		return data
	return {}


func assembly_data(id: String) -> Dictionary:
	for descriptor: Dictionary in assemblies:
		if descriptor["id"] != id:
			continue
		var relative: String = descriptor["model"]
		if relative.is_absolute_path() or ".." in relative.split("/"):
			return {}
		var path := "res://assets/library/" + relative
		if not FileAccess.file_exists(path):
			return {}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or not data.get("parts") is Array:
			return {}
		var textures: Dictionary = {}
		for part: Dictionary in data["parts"]:
			var texture: String = part.get("texture", "")
			if not textures.has(texture):
				textures[texture] = preview_resource({"preview": texture})
			part["texture_resource"] = textures[texture]
		return data
	return {}


func inspection_data(id: String) -> Dictionary:
	var data := model_data(id)
	if data.is_empty(): return {}
	var descriptor: Dictionary = data["descriptor"]
	data["environment"] = descriptor.get("environment", "land")
	data["building"] = building_data(id)
	var sound_names: Array = []
	var motion: Dictionary = descriptor.get("motion", {})
	if motion.has("skin"):
		var skin := animation_clip(motion["skin"])
		if not skin.is_empty():
			data["animation"] = {"bones": skin["bones"], "bindings": skin["bindings"],
				"clips": motion["clips"], "unsupported": motion.get("unsupported", []), "resolve_clip": animation_clip}
			data["animation"]["cues"] = {}
			for clip: Dictionary in motion["clips"]:
				var cues := preload("res://infrastructure/audio_events.gd").cues(descriptor["source"], clip["name"])
				data["animation"]["cues"][clip["name"]] = cues
				for cue: Dictionary in cues: sound_names.append(cue["event"])
	var lifecycle: Dictionary = descriptor.get("lifecycle", {})
	data["sequences"] = []
	for key: String in ["stages", "ranks"]:
		var stages: Array = []
		for stage: Dictionary in lifecycle.get(key, []):
			var component := model_data(stage["model_id"])
			if not component.is_empty():
				stages.append({"name": stage["name"], "model": component, "building": building_data(stage["model_id"]), "part_number": stage.get("part_number", 0)})
		if stages.size() > 1:
			data["sequences"].append({"name": "Construction stages" if key == "stages" else "Rank progression", "stages": stages})
	if not data["building"].is_empty(): sound_names.append_array(["PLAYSOUND_FOLLOWERHAMMERGROUND", "PLAYSOUND_FOLLOWERSTATEFINISHBUILDING"])
	data["audio_events"] = preload("res://infrastructure/audio_events.gd").events(sound_names)
	return data


func building_data(id: String) -> Dictionary:
	if not model_index.has(id): return {}
	var descriptor: Dictionary = model_index[id]
	var info: Dictionary = descriptor.get("building_assembly", {})
	if info.is_empty(): return {}
	var result := info.duplicate(true)
	for component: Dictionary in result["components"]:
		component["model"] = model_data(component["model_id"])
	return result


func animation_clip(relative: String) -> Dictionary:
	if not relative.begins_with("motion/") or ".." in relative.split("/"): return {}
	var path := "res://assets/original/models/" + relative
	if not FileAccess.file_exists(path): return {}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}


func preview_resource(entry: Dictionary) -> Resource:
	var relative: String = entry.get("preview", "")
	if relative.is_empty() or relative.is_absolute_path() or ".." in relative.split("/"):
		return null
	var path := PREVIEW_ROOT + relative
	if relative.begins_with("@original/"):
		path = "res://assets/original/" + relative.trim_prefix("@original/")
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func unit_data(id: String) -> Dictionary:
	var data := inspection_data(id)
	if data.is_empty() or not data.has("animation"): return {}
	var motion: Dictionary = data["animation"]
	var model := data.duplicate(false)
	model["bindings"] = motion["bindings"]
	var clips := {}
	for descriptor: Dictionary in motion["clips"]:
		var clip: Dictionary = motion["resolve_clip"].call(descriptor["path"])
		if not clip.is_empty(): clips[descriptor["name"]]=clip
	return {"bones":motion["bones"],"models":[model],"clips":clips,"audio_cues":motion.get("cues",{}),"audio_events":data.get("audio_events",{})}


func actor_data(id: String, roles: Dictionary) -> Dictionary:
	# Challenge actors load only their active clips, not the entire follower library.
	var model := model_data(id)
	if model.is_empty(): return {}
	var motion: Dictionary = model.get("descriptor",{}).get("motion",{})
	if not motion.has("skin"): return {}
	var skin := animation_clip(motion["skin"])
	if skin.is_empty(): return {}
	model["bindings"]=skin["bindings"]
	var clips := {}
	var cues := {}
	var events: Array = []
	var loaded_clips := {}
	for role: String in roles:
		for descriptor: Dictionary in motion.get("clips",[]):
			if descriptor["name"]!=roles[role]: continue
			if not loaded_clips.has(descriptor["path"]): loaded_clips[descriptor["path"]]=animation_clip(descriptor["path"])
			if loaded_clips[descriptor["path"]].is_empty(): continue
			clips[role]=loaded_clips[descriptor["path"]]
			cues[role]=preload("res://infrastructure/audio_events.gd").cues(model["descriptor"]["source"],descriptor["name"])
			for cue: Dictionary in cues[role]: events.append(cue["event"])
	if not clips.has("idle"): return {}
	return {"source":id,"bones":skin["bones"],"models":[model],"clips":clips,"audio_cues":cues,"audio_events":preload("res://infrastructure/audio_events.gd").events(events)}


func worker_data(role: String) -> Dictionary:
	if not role in ["farmer","miner"]: return {}
	var farmer := role=="farmer"
	var roles := {"idle":"farmer_stand_1" if farmer else "default_stand_1","walking":"farmer_walk_1" if farmer else "default_walk_1","building":"default_hammer_ground_1","carrying":"farmer_carry_wheat" if farmer else "default_walk_1"}
	roles["farming" if farmer else "mining"]="farmer_harvest_wheat" if farmer else "default_pickaxe_1"
	var result := actor_data("follower.group.bin:7c293053" if farmer else "follower.group.bin:4ed5c36d",roles)
	if result.is_empty(): return {}
	result["source"]="worker:"+role
	result["attachments"]=[]
	var parts: Array = [["5e319cc9",[]],["1bc47100",["farming"]],["10a3261e",["carrying"]]] if farmer else [["a323d276",[]],["ad63aeca",["mining"]]]
	for pair: Array in parts:
		var part := actor_part("follower.group.bin:"+pair[0],result["bones"],pair[1])
		if not part.is_empty(): result["attachments"].append(part)
	return result


func astari_archer_data(rules: Dictionary) -> Dictionary:
	if rules.is_empty(): return {}
	var result:=masked_astari_data(rules["roster"],rules["parts"]["male_AstariMask"],rules["clips"])
	if result.is_empty(): return {}
	for key: String in ["bow","bow_pull","arrow"]:
		var part:=actor_part(rules["parts"][key],result["bones"],rules["attachments"].get(key,[]))
		if part.is_empty(): return {}
		result["attachments"].append(part)
	return result


func astari_civilian_data(base: Dictionary,rules: Dictionary) -> Dictionary:
	if rules.is_empty(): return {}
	var result:=masked_astari_data(rules["bodies"],rules["mask"],rules["clips"])
	if not result.is_empty() and result["bones"]==base.get("bones",[]):
		result["clips"]=base["clips"].merged(result["clips"],true)
		result["audio_cues"]=base.get("audio_cues",{}).merged(result["audio_cues"],true)
		result["audio_events"]=base.get("audio_events",{}).merged(result["audio_events"],true)
	return result


func masked_astari_data(bodies: Array,mask_id: String,clips: Dictionary) -> Dictionary:
	var result:=actor_data(bodies[0],clips)
	if result.is_empty() or result["clips"].size()!=clips.size(): return {}
	var female:=actor_part(bodies[1],result["bones"],[])
	var mask:=actor_part(mask_id,result["bones"],[])
	if female.is_empty() or mask.is_empty(): return {}
	result["models"].append(female)
	result["attachments"]=[mask]
	return result


func arrow_reaction_data(base: Dictionary,rules: Dictionary) -> Dictionary:
	if base.is_empty() or rules.is_empty(): return {}
	var roles: Dictionary={"idle":rules["clips"]["idle"]}
	for clip: String in rules["hit_durations"]: roles[clip]=clip
	var original:=actor_data(rules["roster"][0],roles)
	if original.is_empty() or original["bones"]!=base["bones"] or original["clips"].size()!=roles.size(): return {}
	var result:=base.duplicate(false)
	result["clips"]=base["clips"].merged(original["clips"])
	result["attachments"]=base.get("attachments",[]).duplicate()
	result["audio_cues"]=base.get("audio_cues",{}).merged(original["audio_cues"])
	result["audio_events"]=base.get("audio_events",{}).merged(original["audio_events"])
	for side: String in ["front","rear"]:
		var arrow:=actor_part(rules["parts"]["arrow_"+side],base["bones"],rules["hit_reactions"][side])
		if not arrow.is_empty(): result["attachments"].append(arrow)
	return result


func actor_part(id: String,bones: Array,states: Array) -> Dictionary:
	var part:=model_data(id)
	if part.is_empty(): return {}
	var skin:=animation_clip(part["descriptor"].get("motion",{}).get("skin",""))
	if skin.is_empty() or skin["bones"]!=bones: return {}
	part["bindings"]=skin["bindings"]
	part["visible_states"]=states
	return part
