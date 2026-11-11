extends RefCounted
## Converts original CSV records to plain, persistable gameplay configuration.

static func rules(definition: Dictionary) -> Dictionary:
	var tables: Dictionary = definition["tables"]
	var result := {"cards":{},"unlocks":{},"chests":[],"shrines":[],"objects":[],"config":definition["configuration"].duplicate(true),"houses":[]}
	result["version"]=preload("res://simulation/progression.gd").RULES_VERSION
	result["influence_areas"]=[]
	var offset := Vector2.ZERO
	for row: Array in tables.get("initialworldsetup/influence_areas.csv",[]):
		if row.size()>4 and row[0]=="Default": offset=Vector2(definition["followers"][0]["x"],definition["followers"][0]["z"])-Vector2(float(row[1]),float(row[2]))
	result["registration_offset"]=[offset.x,offset.y]
	for row: Array in tables.get("initialworldsetup/influence_areas.csv",[]):
		if row.size()>4 and str(row[1]).is_valid_float(): result["influence_areas"].append({"unlock":row[0],"x":float(row[1])+offset.x,"z":float(row[2])+offset.y,"radius":float(row[3]),"force":int(row[4])!=0})
	result["object_belief"]={}
	for row: Array in tables.get("assets/map_object_values.csv",[]):
		if row.size()>6 and str(row[0]).is_valid_int(): result["object_belief"][str(row[0])]=int(row[6])
	for row: Array in tables.get("balance/config.csv",[]):
		if row.size()>1 and not str(row[0]).begins_with("#") and not str(row[0]).is_empty(): result["config"][row[0]] = row[1]
	for row: Array in tables.get("balance/cards.csv",[]):
		if row.size()<23 or not str(row[0]).begins_with("Card_"): continue
		var requirements := {}
		for index in range(3):
			if not str(row[17+index]).is_empty() and int(row[20+index])>0: requirements[row[17+index]] = int(row[20+index])
		result["cards"][row[0]] = {"id":row[0],"type":int(row[2]),"number":int(row[4]),"age":int(row[10]),"prerequisite":row[11],"title":row[12],"description":row[16],"requirements":requirements}
	# Initial card data supplies the authoritative starting requirements; the
	# cards.csv rows also provide the presentation names and images.
	for row: Array in tables.get("initialworldsetup/carddata.csv",[]):
		if row.size()<16 or not result["cards"].has(row[0]): continue
		var card: Dictionary = result["cards"][row[0]]
		card["type"] = int(row[2])
		card["age"] = int(row[8])
		card["prerequisite"] = row[9]
		card["requirements"] = {}
		for index in range(3):
			if not str(row[10+index]).is_empty() and int(row[13+index])>0: card["requirements"][row[10+index]] = int(row[13+index])
	for row: Array in tables.get("balance/specialcards.csv",[]):
		if row.size()>3 and result["cards"].has(row[0]): result["cards"][row[0]]["reward"] = {"gems":int(row[1]),"belief":int(row[2]),"followers":int(row[3])}
	for row: Array in tables.get("balance/unlocks.csv",[]):
		if row.size()>1 and not str(row[0]).is_empty() and not str(row[0]).begins_with("#"): result["unlocks"][row[0]]=row[1]
	var family := -1
	var models: Dictionary = preload("res://infrastructure/asset_catalog.gd").model_records()
	for row: Array in tables.get("balance/housevalues.csv",[]):
		if str(row[0]).begins_with("#"): family += 1
		if row.size()>28 and str(row[0]).is_valid_int():
			var house := {"family":family,"rank":int(row[0]),"name":row[1],"span":int(row[2])-1,"capacity":int(row[3]),"build_ticks":maxi(1,roundi(float(row[6])*10)),"birth_ticks":maxi(1,roundi(float(row[16])*10)),"min_belief":int(row[24]),"max_belief":int(row[25])}
			house["vision_radius"]=float(row[44]) if row.size()>44 else 15.0
			house["build_capacity"]=float(row[4])
			house["new_builder_contribution"]=float(row[28])
			house["breeder_count"]=int(row[7])
			house["belief_modifier"]=float(row[13])
			house["belief_multiplier"]=float(row[14])
			var group := "mudhut.group.bin" if family==0 else "hiend_primitive.group.bin"
			for model: Dictionary in models.get("models",[]):
				if model["source"]==group and model["name"]=="rank%d_loc1_var1_storey1" % int(row[0]) and not model.get("building_assembly",{}).is_empty(): house["model_id"]=model["id"]
			if family==0 and int(row[0])==1: house["model_id"]="tents.group.bin:dff1563f"
			result["houses"].append(house)
	for row: Array in tables.get("initialworldsetup/initialmapobjects.csv",[]):
		if row.size()<7 or not str(row[1]).is_valid_float(): continue
		if str(row[0]).begins_with("treasure"):
			result["chests"].append({"id":"initial:%d" % result["chests"].size(),"type":row[0],"x":int(row[1]),"z":int(row[2]),"rotation":float(row[3]),"depth":int(row[5]),"card":row[6]})
		elif str(row[0]).begins_with("rock"):
			result["objects"].append({"id":"rock:%d" % result["objects"].size(),"type":row[0],"x":int(row[1]),"z":int(row[2]),"taps":0})
	for row: Array in tables.get("initialworldsetup/rewardchests.csv",[]):
		if row.size()<7 or not str(row[0]).is_valid_int(): continue
		result["chests"].append({"id":"reward:"+str(row[0]),"type":row[1],"x":int(row[2]),"z":int(row[3]),"rotation":float(row[4]),"depth":int(row[5]),"card":row[6]})
	for row: Array in tables.get("initialworldsetup/templepositions.csv",[]):
		if row.size()>8 and str(row[7]).begins_with("Card_") and str(row[8]).is_valid_float():
			result["shrines"].append({"id":str(row[6]),"type":row[0],"x":int(row[1]),"z":int(row[2]),"card":row[7],"build_ticks":maxi(1,roundi(float(row[8])*10)),"rotation":float(row[4]) if str(row[4]).is_valid_float() else 0.0,"source_builders":int(row[9]) if row.size()>9 and str(row[9]).is_valid_int() else 0,"model_id":""})
	for chest: Dictionary in result["chests"]:
		chest["source_x"]=chest["x"]
		chest["source_z"]=chest["z"]
		chest["x"]+=int(offset.x)
		chest["z"]+=int(offset.y)
		if chest["x"]>=0 and chest["z"]>=0 and chest["x"]<definition["width"] and chest["z"]<definition["width"]:
			chest["source_height"]=int(definition["bathymetry"][chest["z"]*definition["width"]+chest["x"]])-int(definition["sea_level"])
	result["chests"]=result["chests"].filter(func(item: Dictionary) -> bool: return item.has("source_height"))
	for group: String in ["shrines","objects"]:
		for item: Dictionary in result[group]:
			item["source_x"]=item["x"]
			item["source_z"]=item["z"]
			item["x"]+=int(offset.x)
			item["z"]+=int(offset.y)
		result[group]=result[group].filter(func(item: Dictionary) -> bool: return item["x"]>=0 and item["z"]>=0 and item["x"]<definition["width"] and item["z"]<definition["width"])
	preload("res://infrastructure/research_content.gd").extend_rules(result,definition.get("research_scope","initialworldsetup6"))
	var source: Dictionary=preload("res://infrastructure/research_content.gd").source
	result["beautify_rules"]=preload("res://infrastructure/beautify.gd").rules(source["executable_sha256"],source["source_sha256"])
	if result["beautify_rules"].is_empty(): return {}
	var environment := preload("res://infrastructure/house_environment.gd").content(source["executable_sha256"],source["source_sha256"])
	for buff: Dictionary in environment.get("records",[]):
		if buff["kind"]==2 and buff["field"]=="belief modifier" and buff["abode"]==1:
			result["abode_beauty"]={"buff":buff,"surroundings":environment["surroundings"]}
			break
	var supply := preload("res://infrastructure/storm_chests.gd").load_content(source["executable_sha256"],source["source_sha256"])
	if not supply.is_empty():
		var scope: Dictionary=supply["scopes"].get(result["research_scope"],{})
		if scope.get("available",false):
			result["chest_supply"]={"areas":scope["areas"].duplicate(true),"sampling":supply["rules"].duplicate(true),"factory":supply["factory_rules"].duplicate(true),"minimum_seconds":float(supply["configuration"]["OfflineStormDelaySecsMin"]),"maximum_seconds":float(supply["configuration"]["OfflineStormDelaySecsMax"]),"padding":float(supply["configuration"]["ChestSpawnPadding"])}
	result["temple_repair_rules"]=preload("res://infrastructure/temple_repair.gd").load_rules(source["executable_sha256"],source["source_sha256"])
	if result["temple_repair_rules"].is_empty(): return {}
	result["config"]["templeFixerFalloff"]=result["temple_repair_rules"]["exponent"]
	# Resolve each authored site through the original type -> generic type ->
	# model mapping. A beacon must not be displayed as a God Power shrine.
	var type_rows: Dictionary={}
	for row: Array in result.get("economy_source",{}).get("tables",{}).get("balance/templetypes.csv",[]):
		if row.size()>9 and not str(row[0]).begins_with("#"): type_rows[str(row[0])]=row
	var generic_rows: Dictionary={}
	for row: Array in result.get("economy_source",{}).get("tables",{}).get("balance/templegenerictypes.csv",[]):
		if row.size()>3: generic_rows[str(row[0])]=row
	for site: Dictionary in result["shrines"]:
		# The enabled compatibility campaigns use the earlier table schema. Match
		# its named power/expansion shrines to the corresponding supplied 2.4
		# class; preserve the legacy positions, rewards and explicit builders.
		var source_type: String=site["type"]
		if source_type in ["shrine1x1","shrine2x2","shrineLandExp"]: source_type="Shrine_LandExp" if site["card"]=="Card_Expansion" else "Shrine_GodPower"
		var row: Array=type_rows.get(source_type,[])
		if row.is_empty(): continue
		site["build_capacity"]=int(site["source_builders"]) if int(site["source_builders"])>0 else int(row[6])
		site["build_priority"]=float(row[9])
		var generic: Array=generic_rows.get(row[1],[])
		if generic.is_empty(): continue
		site["width"]=float(generic[1])
		site["depth"]=float(generic[2])
		if site.get("source_height")==null:
			site["source_height"]=int(definition["bathymetry"][int(site["z"])*int(definition["width"])+int(site["x"])])
		var source_model: String=str(generic[3])+".group.bin"
		for model: Dictionary in models.get("models",[]):
			if model["source"]==source_model and model["id"].ends_with(":dff1563f") and not model.get("building_assembly",{}).is_empty(): site["model_id"]=model["id"]; break
	result["influence_defaults"]=result["influence_areas"].duplicate(true)
	return result


static func power_assets(definition: Dictionary) -> Dictionary:
	var result := {}
	var sheet: Texture2D = load("res://assets/extracted/sprites/Icon_GodPowers_NewSheet.png")
	var ids := {"GodPower_TotemActivate":1,"GodPower_Totem":2,"GodPower_Beautify":9,"GodPower_FingerOfGod":19,"GodPower_RainOfPurity":20}
	for power: String in ids:
		for row: Array in definition["tables"].get("gui/miracledata.csv",[]):
			if row.size()<9 or not str(row[0]).is_valid_int() or int(row[0])!=ids[power]: continue
			var atlas := AtlasTexture.new()
			atlas.atlas=sheet
			atlas.region=Rect2((int(row[1])%8)*128,floori(int(row[1])/8.0)*128,128,128)
			var alternate := AtlasTexture.new()
			alternate.atlas=sheet
			alternate.region=Rect2((int(row[2])%8)*128,floori(int(row[2])/8.0)*128,128,128)
			result[power]={"texture":atlas,"alternate":alternate,"title":row[5],"alt_title":row[7]}
	return result
