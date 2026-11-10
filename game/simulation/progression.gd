extends RefCounted
## Source-configured discovery, chest rewards, completed cards and power gates.

const SUPPORTED_POWERS := ["GodPower_Totem", "GodPower_TotemActivate", "GodPower_Beautify", "GodPower_FingerOfGod", "GodPower_PlaceSettlement_1", "GodPower_PlaceSettlement_2", "GodPower_PlaceSettlement_3"]
const Research = preload("res://simulation/research.gd")
const Economy = preload("res://simulation/campaign_economy.gd")
const RULES_VERSION := 12


static func initialize(rules: Dictionary, terrain: Variant, width: int) -> Dictionary:
	var result := {"rules":rules.duplicate(true),"discovered":[],"completed":[],"inventory":{},"chests":[],"shrines":rules["shrines"].duplicate(true),"objects":rules["objects"].duplicate(true),"unlocks":[],"powers":[],"max_rank":1,"abode_type":0,"totem_capacity":int(rules["config"].get("InitialTotemCapacity",4)),"totem":{},"beautified":[],"first_card_tick":-1,"age":1,"last_reward":"","revision":0}
	for original: Dictionary in rules["chests"]:
		var chest := original.duplicate(true)
		chest["height"] = int(chest.get("source_height",terrain[chest["z"]*width+chest["x"]]))-int(chest["depth"])
		chest["opened"] = false
		result["chests"].append(chest)
	for shrine: Dictionary in result["shrines"]:
		shrine["started"] = false
		shrine["complete"] = false
	result["rock_taps"]={}
	result["rock_revision"]=0
	result["active_powers"]={}
	result["reward_history"]={}
	result["research"]={}
	result["assigned_resources"]={}
	result["settlements"]=[]
	result["happiness"]=preload("res://simulation/happiness.gd").initial(rules)
	return canonical_numbers(result)


static func refresh(state: Dictionary) -> void:
	var p: Dictionary = state["progression"]
	p["next_population"]=0
	for row: Array in state["campaign"]["population_unlocks"]:
		if row.size()>1 and str(row[0]).is_valid_int() and int(row[0])>state["followers"].size():
			if p["next_population"]==0 or int(row[0])<int(p["next_population"]): p["next_population"]=int(row[0])
		if row.size()>1 and str(row[0]).is_valid_int() and state["followers"].size()>=int(row[0]) and row[1] != "Card_Expansion" and not p["rules"].get("research_cards",{}).has(row[1]): discover(p,row[1])
	for level: Dictionary in p["rules"].get("research_levels",[]):
		var total: int = state["followers"].size() if not level.has("resource") else int(state.get(level["resource"],0))
		if total>=int(level["population"]) and p["rules"].get("research_cards",{}).has(level["card"]): discover(p,level["card"])
	if p["first_card_tick"]>=0 and state["tick"]>=p["first_card_tick"]:
		for id: String in ordered_keys(p["rules"]["cards"]):
			if p["rules"]["cards"][id]["number"]==int(p["rules"]["config"].get("FirstCardIndex",1)): discover(p,id)
		p["first_card_tick"] = -1
	for id: String in ordered_keys(p["rules"]["cards"]):
		var card: Dictionary = p["rules"]["cards"][id]
		if not str(card["prerequisite"]).is_empty() and card["prerequisite"] in p["completed"]: discover(p,id)
	p["unlocks"].clear()
	p["powers"].clear()
	for key: String in ordered_keys(p["rules"]["unlocks"]):
		var lock: String = p["rules"]["unlocks"][key]
		if lock=="always" or lock in p["discovered"] or (lock.ends_with("_COMPLETED") and lock.trim_suffix("_COMPLETED") in p["completed"]):
			p["unlocks"].append(key)
			if key in SUPPORTED_POWERS: p["powers"].append(key)
	for power: String in SUPPORTED_POWERS:
		if preload("res://simulation/source_unlocks.gd").enabled(p,power) and not power in p["powers"]: p["powers"].append(power)
	var effect_unlocks: Array = p["rules"].get("economy",{}).get("production_modifiers",{}).keys()+p["rules"].get("economy",{}).get("abode_modifiers",{}).keys()
	for unlock: String in effect_unlocks:
		if preload("res://simulation/source_unlocks.gd").enabled(p,unlock) and not unlock in p["unlocks"]: p["unlocks"].append(unlock)
	for area: Dictionary in p["beautified"].duplicate():
		if state["tick"]>=area["until"]: p["beautified"].erase(area)


static func discover(p: Dictionary, id: String) -> void:
	if p["rules"].has("reward_cards") and not p["rules"]["reward_cards"].has(id): return
	if p["rules"]["cards"].has(id) and not id in p["discovered"]:
		p["discovered"].append(id)
		p["age"] = maxi(p["age"],int(p["rules"]["cards"][id]["age"]))
		p["revision"] += 1


static func inspect(state: Dictionary, command: Dictionary) -> Dictionary:
	var p: Dictionary = state["progression"]
	var kind: String = command.get("type","")
	var reject := {"ok":false,"cost":0,"reason":""}
	if kind in ["claim_card","research_card"]:
		var id: String = command.get("card","")
		if not id in p["discovered"] or id in p["completed"]: return reject
		var card: Dictionary = p["rules"]["cards"][id]
		if not implemented_card(p,id): return reject
		if not Research.definition(p,id).is_empty(): return Research.inspect(p,command)
		if kind=="research_card": return Research.inspect(p,command)
		var missing: Dictionary = payment(p,Research.remaining(p,id))["missing"]
		return {"ok":missing.is_empty(),"cost":0,"reason":card["title"],"missing":missing}
	if kind=="open_chest":
		for chest: Dictionary in p["chests"]:
			if chest["id"] != command.get("id"): continue
			var height: int = state["terrain"][chest["z"]*state["width"]+chest["x"]]
			var known: bool = p["rules"].has("reward_cards") or str(chest["card"]).is_empty() or p["rules"]["cards"].has(chest["card"])
			return {"ok":known and not chest["opened"] and chest["height"]>=0 and height<=chest["height"],"cost":0,"reason":"","chest":chest.duplicate(true)}
	if kind=="tap_object":
		var cell := int(command.get("cell",-1))
		if state.has("rocks") and cell>=0 and cell<state["rocks"].size() and state["rocks"][cell]>0 and int(state["terrain"][cell])>0 and (not state.has("rock_heights") or state["terrain"][cell]==state["rock_heights"][cell]) and int(p["rock_taps"].get(str(cell),0))<int(p["rules"]["config"].get("tapsToDestroyRock",2)): return {"ok":true,"cost":0,"reason":""}
		for object: Dictionary in p["objects"]:
			if object["id"]==command.get("id") and not object.get("removed",false): return {"ok":true,"cost":0,"reason":""}
	if kind=="use_power":
		var power: String = command.get("power","")
		if not power in p["powers"]: return reject
		var suffix := power.trim_prefix("GodPower_")
		var cost := int(p["rules"]["config"].get("belief_"+suffix,0))
		if cost<0: return reject
		if int(p["active_powers"].get(power,-1))>int(state["tick"]): cost=0
		if power=="GodPower_TotemActivate":
			if p["totem"].is_empty(): return reject
			if p["totem"].get("active",false): cost=int(p["rules"]["config"].get("belief_TotemActivate_Deactivate",cost))
		else:
			var x := int(command.get("x",-1))
			var z := int(command.get("z",-1))
			if x<0 or z<0 or x>=state["width"] or z>=state["width"] or state["terrain"][z*state["width"]+x]<=0: return reject
			if power=="GodPower_FingerOfGod" and command.has("home_id"):
				var target := false
				for home: Dictionary in state["homes"]:
					if int(home["id"])==int(command["home_id"]) and home.get("kind","")!="shrine" and x>=home["x"] and z>=home["z"] and x<home["x"]+int(home.get("span",2)) and z<home["z"]+int(home.get("span",2)): target=true; break
				if not target: return reject
		return {"ok":state["belief"]>=cost,"cost":cost,"reason":""}
	return reject


static func complete(state: Dictionary, id: String) -> void:
	var p: Dictionary = state["progression"]
	var card: Dictionary = p["rules"]["cards"][id]
	if Research.definition(p,id).is_empty():
		var plan := payment(p,Research.remaining(p,id))
		for resource: String in plan["debit"]: p["inventory"][resource]-=int(plan["debit"][resource])
	p["completed"].append(id)
	if not id in state["campaign"]["cards"]: state["campaign"]["cards"].append(id)
	if id.begins_with("Card_MaxRank_"): p["max_rank"] = maxi(p["max_rank"],int(id.get_slice("_",2)))
	if id.begins_with("Card_AbodeType_"): p["abode_type"] = maxi(p["abode_type"],int(id.get_slice("_",2))-1)
	if id=="Card_TotemCapacity": p["totem_capacity"] += 5 # Original card description/special-card effect.
	if p["rules"].get("research_cards",{}).get(id,{}).get("type")=="MASTER": p["age"]=maxi(int(p["age"]),int(p["rules"]["research_cards"][id]["era"])+1)
	p["revision"] += 1


static func resource_count(p: Dictionary, id: String) -> int:
	var canonical: String = p["rules"].get("sticker_aliases",{}).get(id,id)
	return int(p["inventory"].get(id,0))+(int(p["inventory"].get(canonical,0)) if canonical!=id else 0)


static func payment(p: Dictionary, requirements: Dictionary) -> Dictionary:
	var available: Dictionary = p["inventory"].duplicate(true)
	var debit := {}
	var missing := {}
	for resource: String in ordered_keys(requirements):
		var remaining := int(requirements[resource])
		var canonical: String = p["rules"].get("sticker_aliases",{}).get(resource,resource)
		var sources: Array = [resource] if resource==canonical else [resource,canonical]
		for id: String in sources:
			var amount := mini(remaining,int(available.get(id,0)))
			if amount>0:
				debit[id]=int(debit.get(id,0))+amount
				available[id]=int(available.get(id,0))-amount
				remaining-=amount
		if remaining>0: missing[resource]=remaining
	return {"debit":debit,"missing":missing}


static func reward(state: Dictionary, id: String) -> void:
	var p: Dictionary = state["progression"]
	if not p["rules"]["cards"].has(id): return
	var card: Dictionary = p["rules"]["cards"][id]
	if not p.has("reward_history"): p["reward_history"]={}
	p["reward_history"][id]=int(p["reward_history"].get(id,0))+1
	if card["type"]==1: p["inventory"][id]=int(p["inventory"].get(id,0))+1
	else:
		discover(p,id)
		if card.has("reward"):
			state["belief"] += card["reward"]["belief"]
			state["gems"] += card["reward"]["gems"]
	p["last_reward"] = id
	p["revision"] += 1


static func random_reward(p: Dictionary, random: RandomNumberGenerator) -> String:
	# Original desktop config: 50% missing components, 20% other useful
	# components, 30% random components, weighted by the required counts.
	var pools: Array = [{},{},{}]
	for id: String in ordered_keys(p["rules"]["cards"]):
		var card: Dictionary = p["rules"]["cards"][id]
		if int(card["age"])>int(p["age"]) or id in p["completed"]: continue
		var research := Research.definition(p,id)
		if not research.is_empty():
			var outstanding := maxi(0,int(research["research_needed"])-Research.points(p,id))
			if outstanding==0: continue
			for resource: String in ordered_keys(p["rules"].get("stickers",{})):
				var sticker: Dictionary=p["rules"]["stickers"][resource]
				var value := int(sticker.get("contributions",{}).get(research["research_type"],0))
				if value<=0 or sticker.get("internal",false) or int(sticker.get("era",1))>int(p["age"]) or not p["rules"]["cards"].has(resource): continue
				pools[2][resource]=int(pools[2].get(resource,0))+outstanding
				var needed_count := maxi(0,ceili(float(outstanding)/value)-Research.stock(p,resource))
				if needed_count>0:
					var pool := 0 if id in p["discovered"] else 1
					pools[pool][resource]=int(pools[pool].get(resource,0))+needed_count
			continue
		for resource: String in ordered_keys(card["requirements"]):
			if not p["rules"]["cards"].has(resource): continue
			if p["rules"].has("reward_cards") and not p["rules"]["reward_cards"].has(resource): continue
			var count := int(Research.remaining(p,id).get(resource,card["requirements"][resource]))
			if count<=0: continue
			pools[2][resource] = int(pools[2].get(resource,0))+count
			var pool: int = 0 if id in p["discovered"] else 1
			var missing := count-int(p["inventory"].get(resource,0))
			if missing>0: pools[pool][resource]=int(pools[pool].get(resource,0))+missing
	var config: Dictionary = p["rules"]["config"]
	var roll := random.randi_range(0,99)
	var needed := int(config.get("Cards_PercentChanceToGetCardYouNeed",50))
	var other := int(config.get("Cards_PercentChanceToGetOtherUsefulCard",20))
	var chosen: Dictionary = pools[0 if roll<needed else (1 if roll<needed+other else 2)]
	if chosen.is_empty(): chosen=pools[2]
	if chosen.is_empty(): return ""
	var total := 0
	for count: int in chosen.values(): total += count
	roll = random.randi_range(0,total-1)
	for id: String in ordered_keys(chosen):
		roll -= int(chosen[id])
		if roll<0: return id
	return ""


static func valid(p: Variant, width: int) -> bool:
	if not p is Dictionary: return false
	for key in ["rules","inventory","totem","rock_taps","active_powers"]:
		if not p.get(key) is Dictionary: return false
	for key in ["cards","unlocks","config"]:
		if not p["rules"].get(key) is Dictionary: return false
	if p["rules"].has("temple_repair_rules") and not preload("res://simulation/source_temple_repair.gd").valid_rules(p["rules"]["temple_repair_rules"]): return false
	if p["rules"]["config"].has("templeFixerFalloff"):
		var exponent: String=str(p["rules"]["config"]["templeFixerFalloff"])
		if not exponent.is_valid_float() or not preload("res://simulation/construction_work.gd").valid_exponent(float(exponent)): return false
	for house: Dictionary in p["rules"].get("houses",[]):
		if house.has("new_builder_contribution") and not preload("res://simulation/construction_work.gd").valid_exponent(house["new_builder_contribution"]): return false
	for plot: Dictionary in p["rules"].get("economy",{}).get("plots",{}).values():
		if plot.has("new_builder_contribution") and not preload("res://simulation/construction_work.gd").valid_exponent(plot["new_builder_contribution"]): return false
	if not Research.valid(p) or not Economy.valid(p) or not preload("res://simulation/campaign_chests.gd").valid(p): return false
	for key in ["discovered","completed","chests","shrines","objects","powers","unlocks","beautified"]:
		if not p.get(key) is Array or p[key].size()>2048: return false
	for key in ["max_rank","abode_type","totem_capacity","age","first_card_tick","revision"]:
		if not (p.get(key) is int or p.get(key) is float) or not is_finite(float(p[key])): return false
	if p["max_rank"]<1 or p["max_rank"]>6 or p["totem_capacity"]<1 or p["totem_capacity"]>512: return false
	for id: Variant in p["completed"]:
		if not id is String or not id in p["discovered"] or not p["rules"]["cards"].has(id): return false
	for id: Variant in p["inventory"]:
		var count: Variant = p["inventory"][id]
		if not id is String or not (count is int or count is float) or not is_finite(float(count)) or count<0 or int(count)!=count: return false
	for group in ["chests","shrines","objects"]:
		var ids := {}
		for entry: Variant in p[group]:
			if not entry is Dictionary or not entry.get("id") is String or ids.has(entry["id"]): return false
			ids[entry["id"]]=true
			for axis in ["x","z"]:
				if not (entry.get(axis) is int or entry.get(axis) is float) or not is_finite(float(entry[axis])) or entry[axis]<0 or entry[axis]>=width: return false
			if group=="chests" and (not entry.get("opened") is bool or not (entry.get("height") is int or entry.get("height") is float) or not entry.get("card") is String): return false
			if group=="shrines":
				for field: String in ["width","depth"]:
					if not entry.has(field): continue
					var extent: Variant=entry[field]
					if not (extent is int or extent is float) or not is_finite(float(extent)) or extent<0 or extent>1024: return false
				var elevation: Variant=entry.get("source_height")
				if elevation!=null and (not (elevation is int or elevation is float) or not is_finite(float(elevation)) or elevation<0 or elevation>255): return false
	return true


static func ordered_keys(data: Dictionary) -> Array:
	var keys := data.keys()
	keys.sort()
	return keys


static func implemented_card(p: Dictionary,id: String) -> bool:
	# Source advances can be researched independently of whether their later
	# unit or power command has a presentation/runtime implementation. Their
	# completed source IDs remain authoritative inputs to the unlock graph.
	var research := Research.definition(p,id)
	if not research.is_empty() and research.get("type","") in ["ADVANCE","MASTER"]: return true
	if id in Economy.POWERS.values(): return p["rules"].has("economy")
	# The source can unlock a power from an advance's discovery or completion.
	# Those advances are functional when their actual power command is supported.
	for power: String in SUPPORTED_POWERS:
		for condition: String in p["rules"].get("source_unlocks",{}).get(power,[]):
			if condition.trim_suffix("_COMPLETED")==id: return true
	if id in p["rules"].get("economy",{}).get("research_effects",[]): return true
	if id in ["Card_Spirituality","Card_DoubleClick","Card_AbodeType_2","Card_TotemCapacity"]: return true
	if id.begins_with("Card_MaxRank_"):
		var rank := int(id.get_slice("_",2))
		for house: Dictionary in p["rules"]["houses"]:
			if house["rank"]==rank and house["family"]<=1 and house.has("model_id"): return true
	return false


static func canonical_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key]=canonical_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(canonical_numbers(item))
		return result
	if value is float and is_finite(value) and value==int(value): return int(value)
	return value
