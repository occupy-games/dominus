extends RefCounted
## The authored manual-start map and source callback data, independently loadable.
## Not yet advertised as a complete campaign in the campaign picker.


static func definition() -> Dictionary:
	var path := "res://assets/original/campaign/homeworld6-opening.json"
	if not FileAccess.file_exists(path): return {}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/"+data["story_definition"]))
	var houses: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-rules.json"))
	if not houses is Dictionary or houses.get("source_sha256")!=story["source_sha256"] or houses.get("native",{}).get("executable_sha256")!=story["day_cycle"]["executable_sha256"]: return {}
	story["first_abode_values"]=houses["records"]["AbodeType_0_Rank_1"].duplicate(true)
	story["first_abode_provenance"]={"table":houses["table"],"table_sha256":houses["table_sha256"],"native_routine":houses["native"]["routine"],"executable_sha256":houses["native"]["executable_sha256"]}
	var selection: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-selection.json"))
	if not selection is Dictionary or selection.get("source_sha256")!=houses["source_sha256"] or selection.get("table_sha256")!=houses["table_sha256"] or selection.get("executable_sha256")!=houses["native"]["executable_sha256"]: return {}
	if not preload("res://simulation/source_houses.gd").valid(selection.get("rows")): return {}
	story["house_selection"]=selection["rows"].duplicate(true)
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
	story["plot_environment"]=preload("res://infrastructure/plot_environment.gd").from_rows(story["tables"]["initialworldsetup6/biomes.csv"],rules.get("economy_source",{}).get("configuration",{}))
	if story["plot_environment"].is_empty(): return {}
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
