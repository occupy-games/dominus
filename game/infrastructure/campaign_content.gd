extends RefCounted
## Decoded original map bytes and balance tables, injected into the simulation.

static var definition: Dictionary = {}
static var loaded_id := ""


static func maps() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/maps.json"))
	return data.get("maps", []).duplicate(true) if data is Dictionary else []


static func for_state(state: Dictionary) -> Dictionary:
	var campaign: Dictionary = state.get("campaign", {})
	if campaign.is_empty(): return {}
	var result := map_definition(str(campaign.get("map_id", campaign.get("map", "Homeworld"))).to_lower())
	if result.is_empty(): return {}
	if state.get("source_map", {}).get("height_sha256", result["height_sha256"]) != result["height_sha256"]: return {}
	return result


static func homeworld() -> Dictionary:
	return map_definition("homeworld")


static func map_definition(id: String) -> Dictionary:
	if definition.is_empty() or loaded_id != id:
		var selected := {}
		for entry: Dictionary in maps():
			if entry["id"] == id and entry.get("available", false): selected = entry; break
		if selected.is_empty(): return {}
		var path := "res://assets/original/" + str(selected["definition"])
		if not FileAccess.file_exists(path): return {}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary: return {}
		if data.has("balance_definition"):
			var balance: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/" + str(data["balance_definition"])))
			if not balance is Dictionary: return {}
			data["tables"] = balance["tables"]
			data["configuration"] = balance["configuration"]
		var raw := FileAccess.get_file_as_bytes("res://assets/original/" + data["height_data"])
		if raw.size() != int(data["width"]) * int(data["width"]): return {}
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(raw)
		if digest.finish().hex_encode() != str(data["height_sha256"]): return {}
		data["terrain"] = PackedByteArray()
		data["terrain"].resize(raw.size())
		for index in range(raw.size()): data["terrain"][index] = maxi(0, int(raw[index]) - int(data["sea_level"]))
		data["bathymetry"] = raw
		for kind: String in ["rock", "tree"]:
			var field: Dictionary = data.get("fields", {}).get(kind, {})
			if field.is_empty(): return {}
			var values := FileAccess.get_file_as_bytes("res://assets/original/" + str(field["path"]))
			if values.size() != raw.size(): return {}
			digest.start(HashingContext.HASH_SHA256)
			digest.update(values)
			if digest.finish().hex_encode() != field["sha256"]: return {}
			data[kind + "_field"] = values
		data["rock_field"]=preload("res://simulation/scenery_density.gd").rocks(data["rock_field"],int(data["width"]),data["terrain"])
		data["rock_density_version"]=1
		if id=="homeworld":
			var source: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/research-rules.json"))
			if not source is Dictionary: return {}
			for name: String in ["initialmapobjects","rewardchests","influence_areas"]:
				var key := "initialworldsetup/"+name+".csv"
				if not source.get("tables",{}).has(key): return {}
				data["tables"][key]=source["tables"][key].duplicate(true)
		data["progression_rules"] = preload("res://infrastructure/progression_content.gd").rules(data)
		definition = data
		loaded_id = id
	return definition.duplicate(true)


static func card_assets() -> Dictionary:
	return preload("res://infrastructure/current_card_content.gd").entries()
