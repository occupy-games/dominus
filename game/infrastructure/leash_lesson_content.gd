extends RefCounted
## Inject the original tutorial's recovered terrain and construction models.

const BASE := "res://assets/original/campaign/"


static func definition() -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(BASE+"leash-lesson.json"))
	if not data is Dictionary or data.get("mission")!=3: return {}
	var terrain:=FileAccess.get_file_as_bytes(BASE+"leash-lesson.bin")
	var hashing:=HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(terrain)
	if terrain.size()!=int(data["width"])*int(data["width"]) or hashing.finish().hex_encode()!=data["terrain_sha256"]: return {}
	var opening:=preload("res://infrastructure/campaign_opening_content.gd").definition()
	if opening.is_empty() or opening["story"]["source_sha256"]!=data["source_sha256"] or not opening["story"].has("mud_hut"): return {}
	var hut: Dictionary=opening["story"]["mud_hut"]
	data["home_model"]=hut["model_id"]
	data["home_capacity"]=int(hut["values"]["capacity"])
	data["home_span"]=int(hut["values"]["base size"])
	data["occupied_home_span"]=ceili(float(hut["values"]["bbwidth"]))
	for site: Dictionary in opening["story"]["temple_sites"]:
		if site["type"]==data["temple"]["type"] and not site["model_id"].is_empty():
			data["temple"]["model_id"]=site["model_id"]
			data["temple"]["span"]=ceili(float(site["nav_size"]))
			break
	if not data["temple"].has("model_id"): return {}
	data["follower_values"]=opening["progression_rules"].get("followers",{})
	data["terrain"]=terrain
	return data
