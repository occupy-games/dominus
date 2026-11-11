extends RefCounted
## Decoded original map bytes and balance tables, injected into the simulation.

static var definition: Dictionary = {}
static var loaded_key := ""


static func maps() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/maps.json"))
	if not data is Dictionary: return []
	var entries: Array=data.get("maps",[]).duplicate(true)
	var opening_path := "res://assets/original/campaign/homeworld6-opening.json"
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(opening_path)) if FileAccess.file_exists(opening_path) else null
	if manifest is Dictionary:
		for entry: Dictionary in entries:
			if entry["id"]!="homeworld6": continue
			entry["available"]=true
			entry["unavailable_reason"]=""
			entry["playable_through"]="Belief tutorial (24 followers)" if int(manifest.get("story_version",0))>=7 else "Power of Prayer (24 followers)"
			if int(manifest.get("story_version",0))>=8: entry["playable_through"]="Pit of Doom repair"
			if int(manifest.get("story_version",0))>=9 and FileAccess.file_exists("res://assets/original/campaign/leash-lesson.bin"):
				entry["playable_through"]="Leashing tutorial (50 followers)"
				if int(manifest.get("story_version",0))>=10: entry["playable_through"]="Dock and first voyage"
				if int(manifest.get("story_version",0))>=11: entry["playable_through"]="Farming and first harvest"
				if int(manifest.get("story_version",0))>=12: entry["playable_through"]="Super Fast Building"
				if int(manifest.get("story_version",0))>=14: entry["playable_through"]="Super Fast Building and Rain of Purity"
				if int(manifest.get("story_version",0))>=15: entry["playable_through"]="Super Fast Building, Rain of Purity and the Fountain"
				if int(manifest.get("story_version",0))>=20: entry["playable_through"]="Ark crossing to Weyworld"
	return entries


static func for_state(state: Dictionary) -> Dictionary:
	var campaign: Dictionary = state.get("campaign", {})
	if campaign.is_empty(): return {}
	var legacy: bool = not state.get("progression",{}).get("rules",{}).has("registered_scope")
	var id := str(campaign.get("map_id",campaign.get("map","Homeworld"))).to_lower()
	var result := preload("res://infrastructure/campaign_opening_content.gd").definition() if id=="homeworld6" and state.has("opening") else map_definition(id,legacy)
	if result.is_empty(): return {}
	if state.get("source_map", {}).get("height_sha256", result["height_sha256"]) != result["height_sha256"]: return {}
	return result


static func homeworld() -> Dictionary:
	return map_definition("homeworld")


static func map_definition(id: String,legacy: bool=false) -> Dictionary:
	if id=="homeworld6": return preload("res://infrastructure/campaign_opening_content.gd").definition()
	var key := id+":legacy" if id=="homeworld7" and legacy else id
	if definition.is_empty() or loaded_key != key:
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
		var registration := {}
		if id=="homeworld" or id=="homeworld7" and not legacy:
			var source: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/research-rules.json"))
			if not source is Dictionary: return {}
			if id=="homeworld":
				for name: String in ["initialmapobjects","rewardchests","influence_areas"]:
					var table := "initialworldsetup/"+name+".csv"
					if not source.get("tables",{}).has(table): return {}
					data["tables"][table]=source["tables"][table].duplicate(true)
			else:
				registration=source.get("world_registrations",{}).get(id,{})
				if registration.is_empty(): return {}
				registration=registration.duplicate(true)
				registration["source_sha256"]=source["source_sha256"]
				registration["executable_sha256"]=source["executable_sha256"]
				data["research_scope"]=registration["scope"]
		data["progression_rules"] = preload("res://infrastructure/progression_content.gd").rules(data)
		if not registration.is_empty() and not register_weyworld(data,registration): return {}
		definition = data
		loaded_key = key
	return definition.duplicate(true)


static func register_weyworld(data: Dictionary,registration: Dictionary) -> bool:
	var rules: Dictionary=data["progression_rules"]
	if rules.is_empty() or rules.get("research_scope")!=registration["scope"]: return false
	var sites := preload("res://infrastructure/temple_sites.gd").sites(registration["scope"],registration["source_sha256"])
	if sites.is_empty(): return false
	var influence_rules := preload("res://infrastructure/source_influence.gd").load_rules(registration["executable_sha256"],registration["source_sha256"])
	if influence_rules.is_empty(): return false
	var areas: Array=[]
	var expansion_sites := {}
	for row: Array in registration["influence_areas"].slice(1):
		if row.size()<7 or not str(row[2]).is_valid_float(): continue
		var unlock: String=row[0]
		areas.append({"unlock":unlock,"sculpt_unlock":row[1],"x":float(row[2]),"z":float(row[3]),
			"radius":float(row[4]),"force":int(row[5])!=0,"powers_only":int(row[6])!=0})
		for condition: String in rules["source_unlocks"].get(unlock,[]):
			if condition.begins_with("TEMPLE_COMPLETE_"): expansion_sites[condition.trim_prefix("TEMPLE_COMPLETE_")]=true
	for site: Dictionary in sites:
		if site["card"]=="Card_ExpansionOre" and expansion_sites.has(site["id"]): site["expands_influence"]=true
	var chests: Array=[]
	for row: Array in registration["rewardchests"].slice(1):
		if row.size()<7 or not str(row[0]).is_valid_int(): continue
		var x := int(row[2])
		var z := int(row[3])
		if x<0 or z<0 or x>=int(data["width"]) or z>=int(data["width"]): return false
		chests.append({"id":"reward:"+str(row[0]),"type":row[1],"x":x,"z":z,"depth":int(row[5]),
			"rotation":float(row[4]),"card":row[6],"source_height":int(data["bathymetry"][z*int(data["width"])+x])-int(data["sea_level"])})
	for row: Array in registration["info"]:
		if row[0]=="Config" and row[1] in ["InitialBelief","InitialWheat","InitialOre"]:
			data["configuration"][row[1]]=int(row[2])
		if row[0]=="Table" and row[1]=="House Values" and row[2]=="Wheat Consumed":
			for house: Dictionary in rules["houses"]:
				if int(house["rank"])==int(row[3]): house["wheat_cost"]=int(row[4])
	var harvest: Array=[]
	for site: Dictionary in registration.get("harvest_sites",[]):
		var specifications: Dictionary=rules["economy"]["plots"]
		var kind: String=site["kind"]
		var size := int(site["size"])
		for specification: Dictionary in specifications.values():
			if specification["kind"]!=kind or int(specification["span"])+1!=size: continue
			var plot := specification.duplicate(true)
			plot["anchor_x"]=int(site["x"])
			plot["anchor_z"]=int(site["z"])
			harvest.append(plot)
			break
	if harvest.size()!=registration.get("harvest_sites",[]).size() or harvest.is_empty(): return false
	data["free_harvest"]=harvest
	var arrival: Dictionary=registration.get("arrival",{}).duplicate(true)
	if arrival.is_empty(): return false
	var ark: Dictionary=arrival["ark"]
	var model_id: String=ark["model"]+".group.bin:dff1563f"
	var catalog: Dictionary=preload("res://infrastructure/asset_catalog.gd").model_records()
	for model: Dictionary in catalog.get("models",[]):
		if model["id"]==model_id and not model.get("building_assembly",{}).is_empty():
			ark["model_id"]=model_id
			break
	if not ark.has("model_id"): return false
	data["arrival"]=arrival
	var tutorial: Dictionary=registration.get("tutorial",{}).duplicate(true)
	var config: Dictionary=rules["economy_source"]["configuration"]
	var environment:=preload("res://infrastructure/plot_environment.gd").from_rows(registration.get("biomes",[]),config)
	if tutorial.is_empty() or environment.is_empty(): return false
	tutorial["environment"]=environment
	tutorial["leash"]={"hold_seconds":config["LeashFirstHoldTime"],"max_length":config["LeashMaxLength"],
		"follower_cost":int(config["LeashBeliefPerFollower"]),"home_cost":int(config["LeashBeliefPerHouse"]),
		"leash_size":config["LeashSize"],"leash_color":[config["LeashColour.x"],config["LeashColour.y"],config["LeashColour.z"],config["LeashOpacity"]]}
	tutorial["abodes"]=weyworld_abodes(registration,catalog)
	rules["weyworld"]=tutorial
	rules["registered_scope"]=registration["scope"]
	rules["registered_influence_rules"]=influence_rules
	rules["influence_areas"]=areas
	rules["influence_defaults"]=areas.duplicate(true)
	rules["registration_offset"]=[0,0]
	rules["shrines"]=sites
	rules["chests"]=chests
	rules["objects"]=[]
	return true


static func weyworld_abodes(registration: Dictionary,catalog: Dictionary) -> Dictionary:
	var values: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-rules.json"))
	var selection: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-selection.json"))
	if not values is Dictionary or not selection is Dictionary: return {}
	if values.get("source_sha256")!=registration["source_sha256"] or values.get("native",{}).get("executable_sha256")!=registration["executable_sha256"] or selection.get("table_sha256")!=values.get("table_sha256"): return {}
	var models: Dictionary={}
	for model: Dictionary in catalog.get("models",[]):
		if not model.get("building_assembly",{}).is_empty(): models[model["source"]+"/"+model["name"]]=model["id"]
	var result: Dictionary={}
	for row: Dictionary in selection["rows"]:
		var id: String=row["id"]
		var family:=int(id.get_slice("_",1)) if id.begins_with("AbodeType_") else -1
		if family<4 or family>7: continue
		var rank:=int(id.get_slice("_",3))
		var source: Dictionary=values["records"][id]
		var model_key: String=source["raw"]["Model Name"]+".group.bin/rank%d_loc1_var1_storey1"%rank
		if not models.has(model_key): continue
		var value: Dictionary=source["values"]
		result["%d:%d"%[family-4,rank]]={"unlock":row["unlock"],"source_house":id,"model_id":models[model_key],
			"family":family,"rank":rank,"name":source["raw"]["House Name"],"span":int(value["base size"]),
			"capacity":int(value["capacity"]),"breeder_count":int(value["breeder count"]),
			"build_capacity":int(value["build capacity"]),"new_builder_contribution":value["new builder contribution"],
			"build_ticks":roundi(float(value["build time"])*10),"birth_ticks":roundi(float(value["birth rate"])*10),
			"vision_radius":value["visionradius"],"min_belief":int(value["min belief"]),"max_belief":int(value["max belief"]),
			"belief_modifier":value["belief modifier"],"belief_multiplier":value["belief multiplier per peep in house"],
			"wheat_cost":int(value["wheat consumed"]),"ore_cost":int(value["ore consumed"])}
	return result


static func card_assets() -> Dictionary:
	return preload("res://infrastructure/current_card_content.gd").entries()
