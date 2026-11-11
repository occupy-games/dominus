extends RefCounted
## Original voyage metadata and verified, untranslated terrain crops.

const BASE := "res://assets/original/adventures/"
static var progress_path := preload("res://infrastructure/save_paths.gd").directory().path_join("voyages.json")
static var cached_reward_rules: Dictionary = {}


static func missions() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE+"catalog.json"))
	return data.get("missions", []).duplicate(true) if data is Dictionary else []


static func first_voyage_id() -> String:
	var first: Array=missions().filter(func(entry: Dictionary) -> bool: return entry["family"]=="event_01" and int(entry["order"])==1)
	if first.size()==1 and first[0]["available"]: return first[0]["id"]
	return ""


static func definition(id: String, difficulty: int = 0) -> Dictionary:
	var selected := {}
	for entry: Dictionary in missions():
		if entry["id"] == id:
			var mode: Dictionary = entry.get("difficulties",[])[clampi(difficulty,0,2)] if entry.has("difficulties") else entry
			if mode.get("available",false):
				selected=entry.duplicate(true)
				selected.merge(mode,true)
			break
	if selected.is_empty(): return {}
	if selected.has("definition"):
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE+selected["definition"]))
		if not source is Dictionary: return {}
		selected=source
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/opening-rules.json"))
	var config := {"id":id,"name":selected["name"],"width":int(selected["width"]),
		"sea_level":19,"height_sha256":selected["fields"]["terrain"]["sha256"],
		"tables":opening["tables"],"configuration":{"InitialBelief":selected["belief"]},
		"automatic_settlement":false,"followers":[{"x":selected["dock"][0],"z":selected["dock"][1]}],
		"voyage":selected}
	for kind: String in ["terrain","tree","rock","gem"]:
		var field: Dictionary = selected["fields"][kind]
		var raw := FileAccess.get_file_as_bytes(BASE+field["path"])
		if raw.size()!=int(selected["width"])*int(selected["width"]): return {}
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(raw)
		if digest.finish().hex_encode()!=field["sha256"]: return {}
		if kind=="terrain":
			config["bathymetry"]=raw
			var heights := PackedByteArray()
			heights.resize(raw.size())
			for i in range(raw.size()): heights[i]=maxi(0,int(raw[i])-19)
			config["terrain"]=heights
		else: config[kind+"_field"]=raw
	return config


static func for_state(state: Dictionary) -> Dictionary:
	if not state.has("voyage"): return {}
	var result := definition(str(state["voyage"]["definition"]["id"]),int(state["voyage"]["definition"].get("difficulty",0)))
	return result if result.get("height_sha256","")==state.get("source_map",{}).get("height_sha256","") else {}


static func read_progress() -> Dictionary:
	var path := progress_path
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return {}
	if data.get("version")==2: data=data.get("missions",{})
	var result := {}
	for id: String in data:
		if not data[id] is Dictionary: continue
		var entry := {}
		for key: String in ["stars","score","rescued"]:
			var value: Variant = data[id].get(key)
			if not (value is int or value is float) or not is_finite(value) or value<0 or value!=int(value): break
			entry[key]=int(value)
		if entry.size()==3 and entry["stars"]<=3: result[id]=entry
	return result


static func reward_rules() -> Dictionary:
	if cached_reward_rules.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE+"reward-rules.json"))
		if not data is Dictionary: return {}
		data["aliases"]=preload("res://infrastructure/current_card_content.gd").ALIASES.duplicate(true)
		cached_reward_rules=preload("res://simulation/immutable_data.gd").freeze(data)
	return cached_reward_rules


static func power_assets(definition: Dictionary) -> Dictionary:
	var result := {}
	var source := preload("res://infrastructure/current_card_content.gd")
	var relevant: Array = definition.get("unlocks",{}).keys()+definition.get("script_powers",[])
	for entry: Dictionary in source.entries().values():
		var power := str(entry.get("power",""))
		if not power in relevant or not entry.get("available",false): continue
		result[power]={"texture":source.image(entry),"title":entry["title"]}
	return result


static func read_profile() -> Dictionary:
	var profile := preload("res://simulation/voyage_rewards.gd").empty()
	if not FileAccess.file_exists(progress_path): return profile
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
	if not data is Dictionary: return profile
	profile["missions"]=read_progress()
	if data.get("version")!=2: return profile
	if str(data.get("rng_state","")).is_valid_int(): profile["rng_state"]=str(data["rng_state"])
	for field: String in ["earned","claimed"]:
		if not data.get(field) is Dictionary: return profile
		for id: String in data[field]:
			var value: Variant = data[field][id]
			if field=="claimed":
				if value is bool and value: profile[field][id]=true
			elif (value is int or value is float) and is_finite(value) and value>=0 and value==int(value): profile[field][id]=int(value)
	return profile


static func write_progress(progress: Dictionary) -> bool:
	var path := progress_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(progress,"\t"))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK
