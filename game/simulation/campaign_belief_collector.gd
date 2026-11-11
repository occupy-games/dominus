extends RefCounted
## Source collection monument and its timed abode scan.

const CARD := "Card_Adv_BeliefCollection"
const POWER := "GodPower_PlaceBeliefCollect"
const KIND := "belief_collector"
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER: return false
	for key: String in ["model","temple_type","title_key","description_key"]:
		if not rules.get(key) is String or rules[key].is_empty(): return false
	for key: String in ["population","width","depth"]:
		if not Numbers.integer_between(rules.get(key),1,10000): return false
	for key: String in ["radius","interval","wait","multiplier"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<=0: return false
	if not rules.get("prices") is Array or rules["prices"].is_empty(): return false
	for price: Variant in rules["prices"]:
		if not Numbers.integer_between(price,1,1000000): return false
	if not rules.get("upgrades") is Array: return false
	for upgrade: Variant in rules["upgrades"]:
		if not upgrade is Dictionary or upgrade.get("currency")!="gems": return false
		if not Numbers.integer_between(upgrade.get("cost"),1,1000000): return false
		for key: String in ["id","button","title","description"]:
			if not upgrade.get(key) is String: return false
		for key: String in ["radius","multiplier"]:
			var value: Variant=upgrade.get(key)
			if not (value is int or value is float) or not is_finite(value) or value<=0: return false
	return true


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get(KIND,{})


static func bounds(prop: Dictionary,rules: Dictionary) -> Rect2i:
	return Rect2i(prop["x"],prop["z"],rules["width"],rules["depth"])


static func status(state: Dictionary) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty(): return {}
	var result:={"radius":rules["radius"],"multiplier":rules["multiplier"]}
	var count:=0
	for prop: Dictionary in state["props"]:
		if prop.get("kind")==KIND: count+=1
	result["price"]=rules["prices"][mini(count,rules["prices"].size()-1)]
	result["can_place"]=POWER in state["progression"]["powers"] and int(state["belief"])>=int(result["price"])
	if not POWER in state["progression"]["powers"]: return result
	var flags: Dictionary=state["progression"].get("script_unlocks",{})
	for upgrade: Dictionary in rules["upgrades"]:
		if not flags.get(upgrade["id"],false):
			result["next"]=upgrade.duplicate(true)
			result["affordable"]=int(state.get("gems",0))>=int(upgrade["cost"])
			break
		result["radius"]=upgrade["radius"]
		result["multiplier"]=upgrade["multiplier"]
	return result


static func inspect_upgrade(state: Dictionary,id: Variant) -> Dictionary:
	var current:=status(state)
	var next: Dictionary=current.get("next",{})
	if next.is_empty() or next["id"]!=id or not current["affordable"]: return {"ok":false,"cost":0,"reason":""}
	return {"ok":true,"cost":0,"reason":"","resource_cost":{"gems":next["cost"]},"upgrade":next["id"]}


static func inspect_place(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var current:=status(state)
	var result:={"ok":false,"cost":0,"reason":""}
	if not current.get("can_place",false) or state["props"].size()>=4096: return result
	var width: int=state["width"]
	for axis: String in ["x","z"]:
		var value: Variant=command.get(axis)
		if not (value is int or value is float) or not is_finite(value) or value<0 or value>=width: return result
	var at:=Vector2i(roundi(command["x"]),roundi(command["z"]))
	var rules:=rules_for(state)
	if not world.source_clear_footprint(bounds({"x":at.x,"z":at.y},rules)): return result
	return {"ok":true,"cost":current["price"],"reason":"","x":at.x,"z":at.y}


static func place(state: Dictionary,plan: Dictionary,tick_seconds: float) -> void:
	var rules:=rules_for(state)
	state["props"].append({"kind":KIND,"id":state["next_id"],"model_id":rules["model"],"x":plan["x"],"z":plan["z"],
		"turns":0,"ready_since":int(state["tick"])-ceili(float(rules["wait"])/tick_seconds)})
	state["next_id"]+=1


static func advance(state: Dictionary,tick_seconds: float,events: Array) -> void:
	var rules:=rules_for(state)
	if rules.is_empty() or not POWER in state["progression"]["powers"]: return
	var tick: int=state["tick"]
	if tick%maxi(1,roundi(float(rules["interval"])/tick_seconds))!=0: return
	var current:=status(state)
	var wait_ticks:=ceili(float(rules["wait"])/tick_seconds)
	var radius_squared:=float(current["radius"])*float(current["radius"])
	for prop: Dictionary in state["props"]:
		if prop.get("kind")!=KIND: continue
		if prop.has("ready_since") and tick-int(prop["ready_since"])<wait_ticks: continue
		var abode:={}
		var center:=Vector2(prop["x"],prop["z"])
		for home: Dictionary in state["homes"]:
			if home.get("kind","")!="" or home.has("settlement_id") or home["progress"]<home["build_ticks"]: continue
			if int(home["stored"])<=0 or int(home["stored"])<int(home.get("min_belief",1)): continue
			var at:=Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]))
			if center.distance_squared_to(at)<=radius_squared:
				abode=home
				break
		if abode.is_empty():
			prop.erase("ready_since")
		elif not prop.has("ready_since"):
			prop["ready_since"]=tick
		else:
			var amount:=int(Terrain.f32(float(abode["stored"])*Terrain.f32(float(current["multiplier"]))))
			abode["stored"]=0
			state["belief"]+=amount
			state["collected"]+=amount
			events.append({"type":"belief_collector_collected","home_id":abode["id"],"collector_id":prop["id"],"amount":amount})


static func inspect_building(state: Dictionary,id: Variant) -> Dictionary:
	for prop: Dictionary in state["props"]:
		if prop.get("kind")!=KIND or prop["id"]!=id: continue
		var rules:=rules_for(state)
		return {"entity":"temple","kind":"shrine","id":id,"site_type":rules["temple_type"],"complete":true,"started":true,
			"occupants":0,"capacity":0,"belief":0,"radius":status(state)["radius"],
			"title_key":rules["title_key"],"description_key":rules["description_key"]}
	return {}
