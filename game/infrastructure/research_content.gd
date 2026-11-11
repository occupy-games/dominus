extends RefCounted
## Current source research is injected as plain data, independently of card art.

static var source: Dictionary = {}


static func extend_rules(rules: Dictionary, scope_name: String = "initialworldsetup6") -> void:
	if source.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/research-rules.json"))
		if raw is Dictionary: source=raw
	if source.is_empty(): return
	if not source["scopes"].has(scope_name): return
	var scope: Dictionary = source["scopes"][scope_name]
	rules["research_scope"]=scope_name
	var card_definitions: Dictionary = source["scopes"]["initialworldsetup6"]["cards"].duplicate(true) if scope_name=="initialworldsetup7" else {}
	card_definitions.merge(scope["cards"],true)
	# Earlier playable advances retain their own source typed definition when
	# the newer campaign removed/renamed that advance.
	for old: String in preload("res://infrastructure/current_card_content.gd").ALIASES:
		var canonical: String=preload("res://infrastructure/current_card_content.gd").ALIASES[old]
		if rules["cards"].has(old) and not card_definitions.has(old) and not card_definitions.has(canonical) and source["scopes"]["initialworldsetup"]["cards"].has(old):
			card_definitions[old]=source["scopes"]["initialworldsetup"]["cards"][old].duplicate(true)
	var catalog: Dictionary = preload("res://infrastructure/current_card_content.gd").entries()
	rules["research_cards"]={}
	rules["research_levels"]=scope["population_levels"].duplicate(true)
	for pair: Array in [["grain","wheat"],["ore","ore"]]:
		for row: Dictionary in scope["currency_levels"][pair[0]]:
			rules["research_levels"].append({"population":int(row["population"]),"card":row["card"],"resource":pair[1]})
	rules["source_unlocks"]=scope["unlocks"].duplicate(true)
	rules["card_bindings"]={}
	for old: String in preload("res://infrastructure/current_card_content.gd").ALIASES:
		var canonical: String = preload("res://infrastructure/current_card_content.gd").ALIASES[old]
		if not rules["cards"].has(old): continue
		if not rules["card_bindings"].has(canonical): rules["card_bindings"][canonical]=[]
		rules["card_bindings"][canonical].append(old)
	rules["vegetation"]={"taps_to_clear":int(source["configuration"].get("tapsToDestroyTree",1)),"belief":{}}
	for row: Array in source["tables"]["assets/map_object_values.csv"]:
		if row.size()>6 and str(row[0]).is_valid_int() and int(row[0])<20: rules["vegetation"]["belief"][str(row[0])]=int(row[6])
	rules["stickers"]=source["stickers"].duplicate(true)
	rules["reward_cards"]={}
	for id: String in catalog:
		if catalog[id].get("available",false) and not catalog[id].get("internal",false) and not str(catalog[id].get("title","")).is_empty(): rules["reward_cards"][id]=true
	for id: String in rules["stickers"]:
		if rules["stickers"][id].get("internal",false) or not rules["reward_cards"].has(id): continue
		var art: Dictionary=catalog[id]
		rules["cards"][id]={"id":id,"type":1,"number":int(art.get("number",0)),"age":maxi(1,int(rules["stickers"][id]["era"])),"prerequisite":"","title":art["title"],"description":art.get("description",""),"requirements":{}}
	rules["sticker_aliases"]={}
	for id: String in preload("res://infrastructure/current_card_content.gd").ALIASES:
		var canonical: String = preload("res://infrastructure/current_card_content.gd").ALIASES[id]
		if canonical.begins_with("Sticker_"):
			rules["sticker_aliases"][id]=canonical
			if not rules["stickers"].has(canonical): rules["reward_cards"].erase(id); rules["reward_cards"].erase(canonical)
	for id: String in card_definitions:
		var card: Dictionary = card_definitions[id]
		if card["type"]=="POWER" and not rules["cards"].has(id):
			rules["cards"][id]={"id":id,"type":0,"number":0,"age":1,"prerequisite":"","title":catalog.get(id,{}).get("title",id),"description":catalog.get(id,{}).get("description",""),"requirements":{},"power":card["power"]}
		if card["type"]=="POWER" and rules["cards"].has(id): rules["cards"][id]["power"]=card["power"]
		if not card["type"] in ["ADVANCE","MASTER"]: continue
		var legacy_binding := false
		for old: String in preload("res://infrastructure/current_card_content.gd").ALIASES:
			if preload("res://infrastructure/current_card_content.gd").ALIASES[old]==id and rules["cards"].has(old): legacy_binding=true
		if legacy_binding:
			for old: String in preload("res://infrastructure/current_card_content.gd").ALIASES:
				if preload("res://infrastructure/current_card_content.gd").ALIASES[old]==id and rules["cards"].has(old): rules["research_cards"][old]=card.duplicate(true)
			continue
		if not catalog.has(id) or not catalog[id].get("available",false): continue
		rules["research_cards"][id]=card.duplicate(true)
		var art: Dictionary = catalog[id]
		# Keep old recipe columns addressable in existing Update.csv files. Typed
		# research validates these advances; the legacy recipe is not displayed.
		var previous: Dictionary = rules["cards"].get(id,{})
		rules["cards"][id]={"id":id,"type":2,"number":int(art.get("number",0)),"age":maxi(1,int(card["era"])),"prerequisite":card["prerequisite"],"title":art["title"],"description":art["description"],"requirements":previous.get("requirements",{}).duplicate(true)}
	for level: Dictionary in rules["research_levels"]:
		if rules["cards"].has(level["card"]): continue
		for binding: String in rules["card_bindings"].get(level["card"],[]):
			if rules["cards"].has(binding): level["card"]=binding; break
	if scope_name!="initialworldsetup7":
		for level: Dictionary in source["scopes"]["initialworldsetup"]["population_levels"]:
			if card_definitions.has(level["card"]) and not scope["cards"].has(level["card"]) and rules["research_cards"].has(level["card"]):
				rules["research_levels"].append(level.duplicate(true))
	rules["economy_source"]={"configuration":source["configuration"].duplicate(true),"tables":source["tables"].duplicate(true)}
	rules["economy"]={"settlements":{},"plots":{},"jobs":{},"production_modifiers":{},"abode_modifiers":{},"research_effects":[]}
	var economy: Dictionary = rules["economy"]
	for row: Array in source["tables"]["balance/templetypes.csv"]:
		if row.size()<5 or not row[0] in ["Settlement_Builder","Settlement_Farming","Settlement_Gem"]: continue
		var number := ["Settlement_Builder","Settlement_Farming","Settlement_Gem"].find(row[0])+1
		var role: String = ["builder","farmer","miner"][number-1]
		economy["settlements"]["GodPower_PlaceSettlement_%d"%number]={"role":role,"radius":float(row[3]),"vision_radius":float(row[4]),"cost":int(source["configuration"].get("belief_Settlement_Use%d"%number,0)),"max_population":int(source["configuration"]["Settlement%sMaxPop"%role.capitalize()]),"model_id":"towncentre.group.bin:dff1563f"}
		economy["settlements"]["GodPower_PlaceSettlement_%d"%number]["statue_id"]="settlementstatues.group.bin:"+["19b106ed","da98f503","c738faa1"][number-1]
	for row: Array in source["tables"]["balance/jobs.csv"]:
		if row.size()>8 and row[0] in ["LOC_JOB_FARMER","LOC_JOB_MINER"]:
			economy["jobs"][str(row[0]).trim_prefix("LOC_JOB_").to_lower()]={"start_stamina":float(row[6]),"finish_stamina":float(row[7]),"stamina_decay":float(row[8])}
	for row: Array in source["tables"]["balance/housevalues.csv"]:
		if row.size()>58 and str(row[4]).begins_with("Base_Rank_"):
			for house: Dictionary in rules["houses"]:
				if int(house["rank"])==int(row[0]):
					house["wheat_cost"]=int(row[57])
					house["ore_cost"]=int(row[58])
		if row.size()<32 or not str(row[0]).is_valid_int() or not row[4].begins_with("Farm_Rank_") and not row[4].begins_with("Mine_Rank_"): continue
		var kind := "farm" if row[4].begins_with("Farm_") else "mine"
		var rank := int(row[0])
		var model := "%s.group.bin:%s"%["hiend_farms" if kind=="farm" else "miningfields",["dff1563f","90cbbc80","41a622c1","f2808902","a35aef43","54355584"][rank-1]]
		economy["plots"]["%s:%d"%[kind,rank]]={"kind":kind,"rank":rank,"span":int(row[11])-1,"capacity":1,"build_ticks":maxi(1,roundi(float(row[18])*10)),"birth_ticks":1,"breeder_count":0,"min_belief":int(row[29]),"max_belief":int(row[30]),"harvest_rate":float(row[30])*float(row[31]),"model_id":model,"vision_radius":float(row[14]),"build_capacity":1}
		economy["plots"]["%s:%d"%[kind,rank]]["new_builder_contribution"]=float(row[22])
		economy["plots"]["%s:%d"%[kind,rank]]["wheat_cost"]=int(row[57])
		economy["plots"]["%s:%d"%[kind,rank]]["ore_cost"]=int(row[58])
	# Source modifier row numbers are one-based data rows, excluding comments.
	var house_rows: Array = source["tables"]["balance/housevalues.csv"].filter(func(row: Array) -> bool: return row.size()>4 and str(row[0]).is_valid_int())
	for entry: Dictionary in source["modifiers"]:
		var fields: Array = entry["fields"]
		if fields.size()!=5 or fields[0]!="Table" or fields[1]!="House Values" or not fields[2] in ["Belief Modifier","Build Time"]: continue
		var index := int(fields[3])-1
		if index<0 or index>=house_rows.size() or not str(fields[4]).begins_with("m"): continue
		var house: Array = house_rows[index]
		var unlock: String = entry["unlock"]
		if fields[2]=="Build Time" and str(house[4]).begins_with("Base_Rank_"):
			if not economy["abode_modifiers"].has(unlock): economy["abode_modifiers"][unlock]={}
			economy["abode_modifiers"][unlock][str(house[0])]=float(str(fields[4]).trim_prefix("m"))
			continue
		if fields[2]!="Belief Modifier": continue
		var kind := "farm" if str(house[4]).begins_with("Farm_") else ("mine" if str(house[4]).begins_with("Mine_") else "")
		if kind.is_empty(): continue
		if not economy["production_modifiers"].has(unlock): economy["production_modifiers"][unlock]={}
		economy["production_modifiers"][unlock]["%s:%s"%[kind,house[0]]]=float(str(fields[4]).trim_prefix("m"))
	var effect_unlocks: Array = economy["production_modifiers"].keys()+economy["abode_modifiers"].keys()
	for unlock: String in effect_unlocks:
		for condition: String in scope["unlocks"].get(unlock,[]):
			if condition.ends_with("_COMPLETED") and rules["research_cards"].has(condition.trim_suffix("_COMPLETED")):
				economy["research_effects"].append(condition.trim_suffix("_COMPLETED"))
