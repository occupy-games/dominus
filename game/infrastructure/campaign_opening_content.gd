extends RefCounted
## The authored manual-start map and source callback data, independently loadable.
## The campaign picker exposes its supported opening and current endpoint.


static func definition() -> Dictionary:
	var path := "res://assets/original/campaign/homeworld6-opening.json"
	if not FileAccess.file_exists(path): return {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/"+data["story_definition"]))
	var houses: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-rules.json"))
	if not houses is Dictionary or houses.get("source_sha256")!=story["source_sha256"] or houses.get("native",{}).get("executable_sha256")!=story["day_cycle"]["executable_sha256"]: return {}
	story["first_abode_values"]=houses["records"]["AbodeType_0_Rank_1"].duplicate(true)
	var first_model: String=story["first_abode_values"]["raw"]["Model Name"]+".group.bin:dff1563f"
	var mud_hut: Dictionary=houses["records"]["AbodeType_1_Rank_1"]
	var mud_hut_group: String=mud_hut["raw"]["Model Name"]+".group.bin"
	var mud_lodge: Dictionary=houses["records"]["AbodeType_1_Rank_2"]
	var mud_lodge_group: String=mud_lodge["raw"]["Model Name"]+".group.bin"
	var timeline_steps: Array=story.get("timeline_steps",[])
	var script_type := int(timeline_steps[4].get("abode_type",-1)) if timeline_steps.size()>4 else -1
	var fountain: Dictionary=story.get("fountain",{})
	var fountain_model_found:=false
	var collector: Dictionary=story.get("belief_collector",{})
	var collector_model_found:=false
	for model: Dictionary in preload("res://infrastructure/asset_catalog.gd").model_records().get("models",[]):
		if model.get("building_assembly",{}).is_empty(): continue
		if model["id"]==fountain.get("model",""): fountain_model_found=true
		if model["id"]==collector.get("model",""): collector_model_found=true
		if model["id"]==first_model: story["first_abode_model"]=first_model
		if script_type>=0 and model["source"]==mud_hut_group and model["name"]=="rank1_loc1_var1_storey1":
			story["mud_hut"]={"source_id":"AbodeType_1_Rank_1","model_id":model["id"],"values":mud_hut["values"].duplicate(true),"name":mud_hut["raw"]["House Name"],"script_type":script_type}
		if script_type>=0 and model["source"]==mud_lodge_group and model["name"]=="rank2_loc1_var1_storey1":
			story["mud_lodge"]={"model_id":model["id"],"values":mud_lodge["values"],"name":mud_lodge["raw"]["House Name"],"script_type":script_type,"rank":2,"family":1}
		for rank in range(1,5):
			var id: String="AbodeType_%d_Rank_%d"%[2 if rank<=2 else 3,rank]
			var row: Dictionary=houses["records"][id]
			if model["source"]==row["raw"]["Model Name"]+".group.bin" and model["name"]=="rank%d_loc1_var1_storey1"%rank:
				if not story.has("wooden_abodes"): story["wooden_abodes"]={}
				story["wooden_abodes"][id]={"model_id":model["id"],"name":row["raw"]["House Name"],"values":row["values"],"rank":rank}
		for rank in [5,6]:
			var id: String="StoneHouse_Rank_%d"%rank
			var row: Dictionary=houses["records"][id]
			if model["source"]==row["raw"]["Model Name"]+".group.bin" and model["name"]=="rank%d_loc1_var1_storey1"%rank:
				if not story.has("stone_abodes"): story["stone_abodes"]={}
				story["stone_abodes"][id]={"model_id":model["id"],"name":row["raw"]["House Name"],"values":row["values"],"rank":rank}
	story["first_abode_provenance"]={"table":houses["table"],"table_sha256":houses["table_sha256"],"native_routine":houses["native"]["routine"],"executable_sha256":houses["native"]["executable_sha256"]}
	var selection: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-selection.json"))
	if not selection is Dictionary or selection.get("source_sha256")!=houses["source_sha256"] or selection.get("table_sha256")!=houses["table_sha256"] or selection.get("executable_sha256")!=houses["native"]["executable_sha256"]: return {}
	if not preload("res://simulation/source_houses.gd").valid(selection.get("rows")): return {}
	story["house_selection"]=selection["rows"].duplicate(true)
	story["house_base_stats"]=preload("res://infrastructure/house_base_stats.gd").load_content(houses,selection)
	if story["house_base_stats"].is_empty(): return {}
	story["build_candidate_values"]=preload("res://infrastructure/build_candidates.gd").load_values(story["day_cycle"]["executable_sha256"],story["source_sha256"],houses["table_sha256"])
	if story["build_candidate_values"].is_empty(): return {}
	story["plot_conversion_rules"]=preload("res://infrastructure/plot_conversion.gd").load_rules(story["day_cycle"]["executable_sha256"])
	if story["plot_conversion_rules"].is_empty(): return {}
	story["build_start_rules"]=preload("res://infrastructure/build_start.gd").load_rules(story["day_cycle"]["executable_sha256"])
	if story["build_start_rules"].is_empty(): return {}
	story["plot_cost"]=preload("res://infrastructure/plot_cost.gd").load_content(story["day_cycle"]["executable_sha256"],story["source_sha256"],houses["table_sha256"])
	if story["plot_cost"].is_empty(): return {}
	story["house_constructor"]=preload("res://infrastructure/house_constructor.gd").load_content(story["day_cycle"]["executable_sha256"],story["source_sha256"],houses["table_sha256"])
	if story["house_constructor"].is_empty(): return {}
	story["house_pool_rules"]=preload("res://infrastructure/house_pool.gd").load_rules(story["day_cycle"]["executable_sha256"])
	if story["house_pool_rules"].is_empty(): return {}
	story["target_reference_rules"]=preload("res://infrastructure/target_references.gd").load_rules(story["day_cycle"]["executable_sha256"])
	if story["target_reference_rules"].is_empty(): return {}
	story["action_sequences"]=preload("res://infrastructure/action_sequences.gd").load_content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["action_sequences"].is_empty(): return {}
	story["action_entry"]=preload("res://infrastructure/action_entry.gd").load_content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["action_entry"].is_empty(): return {}
	story["action_controller"]=preload("res://infrastructure/action_controller.gd").load_content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["action_controller"].is_empty(): return {}
	var storm_chests := preload("res://infrastructure/storm_chests.gd").load_content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if storm_chests.is_empty() or not storm_chests["scopes"].get(story["scope"],{}).get("available",false): return {}
	story["storm_chest_rules"]=storm_chests["rules"].duplicate(true)
	story["chest_placement_rules"]=storm_chests["placement_rules"].duplicate(true)
	story["chest_factory_rules"]=storm_chests["factory_rules"].duplicate(true)
	story["chest_core_rules"]=storm_chests["core_rules"].duplicate(true)
	story["chest_lifetime_rules"]=storm_chests["lifetime_rules"].duplicate(true)
	story["availability_rules"]=storm_chests["availability_rules"].duplicate(true)
	story["sticker_selection_rules"]=preload("res://infrastructure/sticker_selection.gd").load_rules(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["sticker_selection_rules"].is_empty(): return {}
	story["temple_sites"]=preload("res://infrastructure/temple_sites.gd").sites(story["scope"],story["source_sha256"])
	if story["temple_sites"].is_empty(): return {}
	var ark: Dictionary=story.get("ark",{})
	if not ark.is_empty():
		for site: Dictionary in story["temple_sites"]:
			if site["model_id"].is_empty(): continue
			if site["id"]==ark["site_id"] and site["type"]=="Wayland_Ark" and site["x"]==ark["position"][0] and site["z"]==ark["position"][1]:
				ark["model_id"]=site["model_id"]
			elif site["type"]=="Shrine_OreLandExp" and site["x"]==ark["beacon"][0] and site["z"]==ark["beacon"][1]:
				ark["beacon_id"]=site["id"]
		if not ark.has("model_id") or not ark.has("beacon_id"): return {}
	var shrine_position: Dictionary=story["constants"].get("FIRST_SHRINE",{})
	for site: Dictionary in story["temple_sites"]:
		if site["x"]==shrine_position.get("x") and site["z"]==shrine_position.get("y") and site["card"]=="Card_Expansion" and not site["model_id"].is_empty():
			story["first_shrine_id"]=site["id"]
			break
	var pit: Dictionary=story["constants"].get("DISCOVERY",{})
	for site: Dictionary in story["temple_sites"]:
		if site["x"]==pit.get("x") and site["z"]==pit.get("y") and site["card"]==story["constants"].get("CARD_DISCOVERY") and not site["model_id"].is_empty():
			story["discovery_site_id"]=site["id"]
			break
	var dock: Dictionary=story["constants"].get("EVENT_TEMPLE",{})
	for site: Dictionary in story["temple_sites"]:
		if site["x"]==dock.get("x") and site["z"]==dock.get("y") and site["type"]=="Dock_Event" and not site["model_id"].is_empty():
			story["dock_site_id"]=site["id"]
			break
	story["temple_repair_rules"]=preload("res://infrastructure/temple_repair.gd").load_rules(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["temple_repair_rules"].is_empty(): return {}
	story["temple_terrain_rules"]=preload("res://infrastructure/temple_terrain.gd").load_rules(story["day_cycle"]["executable_sha256"])
	if story["temple_terrain_rules"].is_empty(): return {}
	story["temple_footprint_rules"]=preload("res://infrastructure/temple_terrain.gd").footprint_rules(story["day_cycle"]["executable_sha256"])
	if story["temple_footprint_rules"].is_empty(): return {}
	story["temple_frame_rules"]=preload("res://infrastructure/temple_terrain.gd").frame_rules(story["day_cycle"]["executable_sha256"])
	if story["temple_frame_rules"].is_empty(): return {}
	var membership := preload("res://infrastructure/temple_membership.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if membership.is_empty(): return {}
	story["temple_membership_rules"]=membership["rules"]
	story["temple_membership_radii"]=membership["radii"]
	story["temple_modifiers"]=preload("res://infrastructure/temple_modifiers.gd").records(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["temple_modifiers"].is_empty(): return {}
	story["temple_effects"]=preload("res://infrastructure/temple_effects.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["temple_effects"].is_empty(): return {}
	var environment := preload("res://infrastructure/house_environment.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if environment.is_empty(): return {}
	story["house_environment"]=environment["records"]
	story["house_surroundings_rules"]=environment["surroundings"]
	story["building_foundation_rules"]=preload("res://infrastructure/building_foundation.gd").rules(story["day_cycle"]["executable_sha256"])
	if story["building_foundation_rules"].is_empty(): return {}
	story["house_terrain_rules"]=preload("res://infrastructure/house_terrain_frame.gd").rules(story["day_cycle"]["executable_sha256"])
	if story["house_terrain_rules"].is_empty(): return {}
	story["progression_modifier_rules"]=preload("res://infrastructure/house_terrain_frame.gd").modifiers(story["day_cycle"]["executable_sha256"])
	if story["progression_modifier_rules"].is_empty(): return {}
	story["reward_dispatch_rules"]=preload("res://infrastructure/reward_dispatch.gd").load_rules(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["reward_dispatch_rules"].is_empty(): return {}
	story["unlock_dispatch"]=preload("res://infrastructure/unlock_dispatch.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"],story["scope"])
	if story["unlock_dispatch"].is_empty(): return {}
	var reward_queue := preload("res://infrastructure/reward_queue.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if reward_queue.is_empty(): return {}
	story["reward_queue_rules"]=reward_queue["rules"]
	story["special_reward_cards"]=reward_queue["special"]
	var card_research := preload("res://infrastructure/card_research.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"],story["scope"])
	if card_research.is_empty(): return {}
	story["card_research_rules"]=card_research["rules"]
	story["source_research_cards"]=card_research["cards"]
	story["source_research_stickers"]=card_research["stickers"]
	story["bound_sticker_selection_rules"]=preload("res://infrastructure/sticker_selection.gd").bound_rules(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["bound_sticker_selection_rules"].is_empty(): return {}
	story["reward_catalog"]=preload("res://infrastructure/reward_catalog.gd").content(story["day_cycle"]["executable_sha256"],story["source_sha256"],story["scope"])
	if story["reward_catalog"].is_empty(): return {}
	story["era_rules"]=preload("res://infrastructure/era_progression.gd").rules(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["era_rules"].is_empty(): return {}
	story["storm_chest_areas"]=storm_chests["scopes"][story["scope"]]["areas"].duplicate(true)
	var motion: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/rock-motion.json"))
	if not motion is Dictionary or motion.get("source_sha256")!=story["source_sha256"] or motion.get("executable_sha256")!=story["day_cycle"]["executable_sha256"]: return {}
	story["rock_motion_config"]={"duration":motion["duration"],"sea_height":motion["sea_height"],"capacity":motion["capacity"]}
	if not preload("res://simulation/source_rock_motion.gd").valid_config(story["rock_motion_config"]): return {}
	var trees: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/tree-response.json"))
	if not trees is Dictionary or trees.get("source_sha256")!=story["source_sha256"] or trees.get("executable_sha256")!=story["day_cycle"]["executable_sha256"]: return {}
	story["tree_response_config"]={}
	for key: String in ["duration","sea_height","vertical_scale","minimum_scale","encouragement_scale"]: story["tree_response_config"][key]=trees[key]
	if not preload("res://simulation/source_tree_response.gd").valid_config(story["tree_response_config"]): return {}
	story["plot_resize_rules"]=preload("res://infrastructure/plot_resize.gd").load_rules(story["day_cycle"]["executable_sha256"])
	if story["plot_resize_rules"].is_empty(): return {}
	story["plot_field"]=preload("res://infrastructure/plot_field.gd").load_field(data["pack_sha256"])
	if story["plot_field"].is_empty(): return {}
	story["influence_rules"]=preload("res://infrastructure/source_influence.gd").load_rules(story["day_cycle"]["executable_sha256"],story["source_sha256"])
	if story["influence_rules"].is_empty(): return {}
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/opening-rules.json"))
	data["story"]=story
	data["tables"]=opening["tables"]
	data["configuration"]=opening["configuration"]
	data["configuration"]["InitialBelief"]=0 # TrailStep00.onListening: SetBelief(0).
	data["research_scope"]=story["scope"]
	data["automatic_settlement"]=false
	for pair: Array in [["terrain",{"path":data["height_data"],"sha256":data["height_sha256"]}],["tree",data["fields"]["tree"]],["rock",data["fields"]["rock"]]]:
		var bytes := FileAccess.get_file_as_bytes("res://assets/original/"+pair[1]["path"])
		if bytes.size()!=1024*1024: return {}
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if hash.finish().hex_encode()!=pair[1]["sha256"]: return {}
		if pair[0]=="terrain":
			data["bathymetry"]=bytes
			story["raw_floor"]=bytes
			var terrain := PackedByteArray()
			terrain.resize(bytes.size())
			for index in range(bytes.size()): terrain[index]=maxi(0,int(bytes[index])-19)
			data["terrain"]=terrain
		else: data[pair[0]+"_field"]=bytes
	var scenery := preload("res://infrastructure/source_scenery.gd").load_layout(story,data["terrain"],{"terrain":data["height_sha256"],"tree":data["fields"]["tree"]["sha256"],"rock":data["fields"]["rock"]["sha256"]})
	if scenery.is_empty(): return {}
	data["source_trees"]=scenery["trees"]
	data.erase("tree_field") # Its validated density bytes have been resolved offline.
	data["rock_field"]=scenery["rock_field"]
	data["source_scenery"]=scenery["provenance"]
	story["rock_objects"]=scenery["rocks"]
	var rules: Dictionary = preload("res://infrastructure/progression_content.gd").rules(data)
	if not collector.is_empty():
		if not preload("res://simulation/campaign_belief_collector.gd").valid_rules(collector) or not rules["research_cards"].has(collector["card"]): return {}
		if not collector_model_found: story.erase("belief_collector")
	if story.has("cliff_sculpt"):
		var cliff: Dictionary=story["cliff_sculpt"]
		if not preload("res://simulation/campaign_cliff_sculpt.gd").valid_rules(cliff) or not rules["research_cards"].has(cliff["card"]): return {}
	if not fountain.is_empty():
		if not preload("res://simulation/campaign_fountain.gd").valid_rules(fountain) or not rules["research_cards"].has(fountain["card"]): return {}
		if not fountain_model_found: story.erase("fountain")
	if story.has("rain"):
		var rain: Dictionary=story["rain"]
		if not preload("res://simulation/campaign_rain.gd").valid_rules(rain) or not rules["research_cards"].has(rain["card"]): return {}
	if story.has("pit_clips"):
		var economy: Dictionary=rules["economy_source"]
		var config: Dictionary=economy["configuration"]
		var sacrifice:={"clips":story["pit_clips"]["clips"],"gems":[],"gem_delay":config["SacrificeGemSaveDelay"],
			"audio_delay":config.get("SacrificeSFXFollowerDelay",story["pit_clips"]["audio_delay"]),"roll_divisor":story["pit_clips"]["roll_divisor"],
			"beam_delay":config["SacrificeMainVFXDelayﾠ"],
			"birth_factor":config.get("SacrificedBirthRateFac",story["pit_clips"]["birth_factor"]),
			"settlement_birth_factor":config.get("SacrificedBirthRateFacSett",story["pit_clips"]["settlement_birth_factor"])}
		for slot: String in ["A","B","C","D","E"]:
			sacrifice["gems"].append([config["SacrificeGemProb"+slot],config["SacrificeGemVal"+slot]])
		for row: Array in economy["tables"]["balance/happiness.csv"]:
			if row.size()>2 and row[1]=="Sacrifice": sacrifice["happiness"]=float(row[2]); break
		if not preload("res://simulation/campaign_pit.gd").valid_rules(sacrifice): return {}
		story["pit_sacrifice"]=sacrifice
		story["pit_beam"]["height_offset"]=config["SacrificeBeamVFXOffY"]
	var levels: Array=story["tables"][story["scope"]+"/populationlevels.csv"]
	var ordinal := 0
	var milestones:={"Card_AbodeType1_Rank1":"growth_population_card","Card_RepairTemple":"timeline_population_card",
		"Card_GenerateBelief":"shrine_population_card","Card_Adv_Leash_1":"leash_population_card","Card_Settlement_Farming":"farming_population_card",
		"Card_Settlement_Mine":"mining_population_card"}
	story["housing_advances"]=[]
	for row: Array in levels:
		if row.size()<2 or not str(row[0]).is_valid_int() or str(row[1]).is_empty(): continue
		ordinal+=1
		var source_id: String=row[1]
		var housing: bool=source_id in ["Card_AbodeType2_Rank1","Card_AbodeType2_Rank2"] and story.get("wooden_abodes",{}).has("AbodeType_2_Rank_"+source_id.right(1))
		housing=housing or source_id=="Card_AbodeType1_Rank2" and story.has("mud_lodge")
		if not milestones.has(source_id) and not housing: continue
		var bindings: Array=rules["card_bindings"].get(source_id,[])
		var runtime_id: String=bindings[0] if not bindings.is_empty() else source_id
		if not rules["research_cards"].has(runtime_id): continue
		var milestone:={"source_id":source_id,"id":runtime_id,"population":int(row[0]),"ordinal":ordinal}
		if housing: story["housing_advances"].append(milestone)
		else: story[milestones[source_id]]=milestone
	if story.has("farming_population_card"):
		var farming: Dictionary=rules["economy"]["settlements"]["GodPower_PlaceSettlement_2"]
		farming["cost"]=story["constants"]["FARM_BELIEF_COST"]
		var core: Dictionary=houses["records"]["Settlement_Farmer_1"]["values"]
		story["farming_core"]={"span":int(core["base size"]),"breeders":int(core["breeder count"]),
			"birth_ticks":maxi(1,roundi(float(core["birth rate"])*10))}
	var builder: Dictionary=story.get("builder_settlement",{})
	if not builder.is_empty():
		rules["economy"]["settlements"][builder["power"]]["cost"]=builder["cost"]
		var core: Dictionary=houses["records"]["Settlement_Builder_1"]["values"]
		story["builder_core"]={"span":int(core["base size"]),"breeders":int(core["breeder count"]),
			"birth_ticks":maxi(1,roundi(float(core["birth rate"])*10))}
	var mining: Dictionary=story.get("mining_settlement",{})
	if not mining.is_empty() and story.has("mining_population_card"):
		rules["economy"]["settlements"][mining["power"]]["cost"]=mining["cost"]
		var core: Dictionary=houses["records"]["Settlement_Miner_1"]["values"]
		story["mining_core"]={"span":int(core["base size"]),"breeders":int(core["breeder count"]),
			"birth_ticks":maxi(1,roundi(float(core["birth rate"])*10))}
		story["ore_advances"]=[]
		for row: Array in story["tables"][story["scope"]+"/orelevels.csv"]:
			if row.size()<2 or not str(row[0]).is_valid_int() or not rules["research_cards"].has(row[1]): continue
			if row[1] in ["Card_RepairTemple_2","Card_WheatBuff_1"] or row[1] in ["Card_AbodeType3_Rank5","Card_AbodeType3_Rank6"] and story.get("stone_abodes",{}).has("StoneHouse_Rank_"+row[1].right(1)):
				story["ore_advances"].append({"id":row[1],"mines":int(row[0])})
	if story.has("authored_fields"):
		story["grain_advances"]=[]
		for row: Array in story["tables"][story["scope"]+"/grainlevels.csv"]:
			if row.size()<2 or not str(row[0]).is_valid_int() or not rules["research_cards"].has(row[1]): continue
			if row[1]=="Card_GrainToBuild":
				story["grain_building_card"]={"id":row[1],"fields":int(row[0])}
			elif row[1]=="Card_Settlement_Follower" and story.has("builder_core") or row[1] in ["Card_AbodeType2_Rank3","Card_AbodeType2_Rank4"] and story.get("wooden_abodes",{}).has("AbodeType_3_Rank_"+row[1].right(1)):
				story["grain_advances"].append({"id":row[1],"fields":int(row[0])})
		if not story.has("grain_building_card"): return {}
		for field: Dictionary in story["authored_fields"]:
			var selection_row: Dictionary={}
			for row: Dictionary in story["house_selection"]:
				if row["kind"]==1 and row["size"]==field["size"]: selection_row=row; break
			if selection_row.is_empty(): return {}
			var rank:=int(str(selection_row["id"]).trim_prefix("Farm_Rank_"))
			var spec: Dictionary=rules["economy"]["plots"].get("farm:%d"%rank,{})
			if spec.is_empty(): return {}
			field.merge(spec,true)
			field["span"]=int(selection_row["size"])
			field["source_index"]=int(selection_row["index"])
	story["plot_environment"]=preload("res://infrastructure/plot_environment.gd").from_rows(story["tables"]["initialworldsetup6/biomes.csv"],rules.get("economy_source",{}).get("configuration",{}))
	if story["plot_environment"].is_empty(): return {}
	var chest_position: Dictionary=story["constants"]["FIRST_CHEST"]
	story["authored_sticker_chests"]=[]
	var fallback_chests: Array=[]
	for row: Array in story["tables"][story["scope"]+"/rewardchests.csv"]:
		if row.size()<7 or not str(row[0]).is_valid_int(): continue
		var chest:={"id":int(row[0]),"type":row[1],"x":float(row[2]),"z":float(row[3]),"rotation":float(row[4]),"depth":float(row[5]),"reward":row[6]}
		if row[6].is_empty():
			fallback_chests.append(chest)
			continue
		if not rules["stickers"].has(row[6]) or not rules["cards"].has(row[6]): continue
		if chest["x"]==float(chest_position["1"]) and chest["z"]==float(chest_position["2"]): story["first_chest"]=chest
		else: story["authored_sticker_chests"].append(chest)
	# The saved handles for fixed rewards continue to identify the same sites.
	story["authored_sticker_chests"].append_array(fallback_chests)
	story["source_chest_stickers"]=true
	if not story.has("first_chest"): return {}
	# Keep original Homeworld6 temple coordinates; never transplant older sites.
	rules["chests"]=[]
	rules["shrines"]=story["temple_sites"].duplicate(true)
	rules["objects"]=[]
	rules["influence_areas"]=[]
	rules["registration_offset"]=[0,0]
	rules["config"]["tapsToDestroyRock"]=int(story["object_config"]["taps_to_destroy_rock"])
	for row: Array in story["tables"]["initialworldsetup6/influence_areas.csv"]:
		if row.size()>6 and str(row[2]).is_valid_float(): rules["influence_areas"].append({"unlock":row[0],"sculpt_unlock":row[1],"x":float(row[2]),"z":float(row[3]),"radius":float(row[4]),"force":int(row[5])!=0,"powers_only":int(row[6])!=0})
	rules["influence_defaults"]=rules["influence_areas"].duplicate(true)
	data["progression_rules"]=rules
	return data
