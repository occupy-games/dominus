extends RefCounted
## Holy Forest placement, population gate and original environment upgrades.

const CARD := "Card_Adv_GodSeed_1"
const POWER := "GodPower_GodSeed"
const FIRST_TREE := 15
const Terrain = preload("res://simulation/source_terrain.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Influence = preload("res://simulation/source_influence.gd")
const EnvironmentBuffs = preload("res://simulation/source_house_environment.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER:
		return false
	for key: String in ["population","cost","cost_increment"]:
		if not Numbers.integer_between(rules.get(key),0,1000000): return false
	for key: String in ["emerge_seconds","sea_height","sink_distance","happiness_multiplier","settlement_vision_radius"]:
		if not finite(rules.get(key)) or rules[key]<0: return false
	if rules["population"]==0 or rules["emerge_seconds"]==0 or not Numbers.integer_between(rules.get("rise"),0,1):
		return false
	for key: String in ["happiness_near","happiness_far"]:
		var values: Variant=rules.get(key)
		if not values is Array or values.size()!=2: return false
		for value: Variant in values:
			if not finite(value) or value<0 or value>1: return false
	if not rules.get("models") is Array or rules["models"].size()!=5:
		return false
	for model: Variant in rules["models"]:
		if not model is String or not model.begins_with("godseedtrees.group.bin:"): return false
	if not rules.get("upgrades") is Array or rules["upgrades"].size()!=2:
		return false
	for index in range(2):
		var row: Variant=rules["upgrades"][index]
		if not row is Dictionary or row.get("id")!="LvlUp_%s_%d"%[POWER,index+1] or row.get("unlock")!="Upgrade_%s_%d"%[POWER,index+1]:
			return false
		if row.get("role")!=["farm","mine"][index] or row.get("currency")!="GEMS" or not Numbers.integer_between(row.get("cost"),1,1000000):
			return false
		for key: String in ["button","title","description"]:
			if not row.get(key) is String or row[key].is_empty(): return false
	return rules.get("sound") is String and not rules["sound"].is_empty()


static func finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get("god_seed",{})


static func price(world: RefCounted,state: Dictionary,rules: Dictionary) -> int:
	var increment := float(rules["cost_increment"])
	if increment==0: return int(rules["cost"])
	var count := 0
	for tree: Dictionary in state["trees"]:
		if tree.has("planted_tick") and world.tree_at(int(tree["x"]),int(tree["z"])): count+=1
	return int(Terrain.f32(float(rules["cost"])+Terrain.f32(count*increment)))


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var reject := {"ok":false,"cost":0,"reason":""}
	var rules := rules_for(state)
	if rules.is_empty() or not Unlocks.enabled(state["progression"],POWER): return reject
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	if not finite(x) or not finite(z): return reject
	x=Terrain.f32(float(x))
	z=Terrain.f32(float(z))
	var width := int(state["width"])
	if x<0 or z<0 or x>=width or z>=width or not world.can_act_at(x,z): return reject
	var height := Terrain.surface_height(world.source_raw_height_at(x,z))
	if height<=float(rules["sea_height"]) or not world.source_seed_slot_available(int(x),int(z)): return reject
	var cost := price(world,state,rules)
	return {"ok":state["belief"]>=cost,"cost":cost,"reason":"","x":x,"z":z,
		"source_y":height-float(rules["sea_height"])}


static func tree(world: RefCounted,state: Dictionary,plan: Dictionary,random: RandomNumberGenerator) -> Dictionary:
	var rules := rules_for(state)
	var variant := (random.randi_range(0,32767)*5)>>15
	var angle := (random.randi_range(0,32767)*360)>>15
	var x := int(plan["x"])
	var z := int(plan["z"])
	return {"x":plan["x"],"z":plan["z"],"cell":z*int(state["width"])+x,"variant":FIRST_TREE+variant,
		"rotation":deg_to_rad(float(angle)),"source_y":plan["source_y"],"anchor_height":world.height_at(x,z),
		"model_id":rules["models"][variant],"planted_tick":int(state["tick"])+1}


static func valid_tree(tree: Dictionary,state: Dictionary) -> bool:
	var rules := rules_for(state)
	if rules.is_empty() or not tree.has("source_y") or not Numbers.integer_between(tree["variant"],FIRST_TREE,FIRST_TREE+4):
		return false
	return tree["model_id"]==rules["models"][int(tree["variant"])-FIRST_TREE] and Numbers.integer_between(tree["planted_tick"],1,int(state["tick"]))


static func raise_happiness(state: Dictionary,plan: Dictionary) -> void:
	var p: Dictionary=state["progression"]
	if not Unlocks.enabled(p,"Happiness"): return
	var rules := rules_for(state)
	var point := Vector2(plan["x"],plan["z"])
	var tribe := -1
	for home: Dictionary in state["homes"]:
		if not home.get("kind","") in ["","farm","mine","settlement"]: continue
		var radius := float(home.get("vision_radius",rules.get("settlement_vision_radius",0.0) if home.get("settlement_core",false) else 0.0))
		var center := Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]))
		if radius<=0 or center.distance_squared_to(point)>radius*radius: continue
		tribe=clampi(int(home.get("allegiance",0)),0,1)
		if tribe==0: break
	var near := tribe>=0
	if not near:
		var influence_rules: Dictionary=state["opening"]["definition"].get("influence_rules",{})
		tribe=0 if not state.has("source_influence") or Influence.allows(state["source_influence"]["raster"],int(point.x),int(point.y),false,influence_rules) else 1
	var key: String=["player","astari"][tribe]
	var amount: float=rules["happiness_near" if near else "happiness_far"][tribe]
	var happiness: Dictionary=p["happiness"]
	happiness[key]=clampf(float(happiness[key])+Terrain.f32(amount*float(rules["happiness_multiplier"])),0.0,1.0)


static func inspect_upgrade(state: Dictionary,id: Variant) -> Dictionary:
	var rules := rules_for(state)
	var p: Dictionary=state["progression"]
	if not rules.is_empty() and Unlocks.enabled(p,POWER):
		for upgrade: Dictionary in rules["upgrades"]:
			if upgrade["id"]!=id or Unlocks.enabled(p,upgrade["unlock"]): continue
			return {"ok":state["gems"]>=upgrade["cost"],"cost":0,"reason":"","upgrade":id,
				"resource_cost":{"gems":upgrade["cost"]}}
	return {"ok":false,"cost":0,"reason":""}


static func status(world: RefCounted,state: Dictionary) -> Dictionary:
	var rules := rules_for(state)
	if rules.is_empty(): return {}
	var offers: Array=[]
	var p: Dictionary=state["progression"]
	if Unlocks.enabled(p,POWER):
		for upgrade: Dictionary in rules["upgrades"]:
			if Unlocks.enabled(p,upgrade["unlock"]): continue
			offers.append({"next":upgrade,"affordable":state["gems"]>=upgrade["cost"]})
	return {"price":price(world,state,rules),"upgrades":offers}


static func harvest_rate(state: Dictionary,field: Dictionary,base: float) -> float:
	var count := int(field.get("nearby_seed_trees",0))
	if count==0: return base
	var rules := rules_for(state)
	for upgrade: Dictionary in rules.get("upgrades",[]):
		if upgrade["role"]!=field["kind"] or not Unlocks.enabled(state["progression"],upgrade["unlock"]): continue
		for buff: Dictionary in state["opening"]["definition"]["house_environment"]:
			if buff["kind"]==3 and buff["field"]=="belief modifier":
				return Terrain.f32(base*EnvironmentBuffs.contribution(buff,float(count)))
	return base
