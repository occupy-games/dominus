extends RefCounted
## Original Homeworld gift placement and the per-object celebration reaction.

const CARD := "Card_Adv_Fountain"
const POWER := "GodPower_PlaceGiftFountain"


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER: return false
	if not rules.get("model") is String or rules["model"].is_empty(): return false
	var numbers:=preload("res://simulation/source_plot_schedule.gd")
	for key: String in ["population","width","depth","gems"]:
		if not numbers.integer_between(rules.get(key),1,10000): return false
	for key: String in ["radius","reaction_seconds","happiness"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<=0: return false
	return rules["happiness"]<=1


static func bounds(fountain: Dictionary,rules: Dictionary) -> Rect2i:
	return Rect2i(fountain["x"],fountain["z"],rules["width"],rules["depth"])


static func find(state: Dictionary,id: Variant) -> Dictionary:
	for prop: Dictionary in state["props"]:
		if prop.get("kind")=="fountain" and prop["id"]==id: return prop
	return {}


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var result:={"ok":false,"cost":0,"reason":""}
	var rules: Dictionary=state["opening"]["definition"].get("fountain",{})
	if rules.is_empty() or not POWER in state["progression"]["powers"]: return result
	if command["type"]=="campaign_fountain_tap":
		var fountain:=find(state,command.get("id"))
		result["ok"]=not fountain.is_empty() and int(state["tick"])>=int(fountain["reaction_until"]) and world.can_act_at(fountain["x"],fountain["z"])
		return result
	if state.get("gems",0)<rules["gems"] or state["props"].size()>=4096: return result
	for axis: String in ["x","z"]:
		var value: Variant=command.get(axis)
		if not (value is int or value is float) or not is_finite(value) or value<0 or value>=state["width"]: return result
	var at:=Vector2i(roundi(command["x"]),roundi(command["z"]))
	var area:=bounds({"x":at.x,"z":at.y},rules)
	if not world.source_clear_footprint(area): return result
	var near_abode:=false
	for home: Dictionary in state["homes"]:
		if not str(home.get("kind","")).is_empty() or home["progress"]<home["build_ticks"]: continue
		var anchor:=Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]))
		if anchor.distance_to(Vector2(at))<=float(rules["radius"]):
			near_abode=true
			break
	if near_abode:
		result.merge({"ok":true,"x":at.x,"z":at.y,"resource_cost":{"gems":rules["gems"]}},true)
	return result


static func place(state: Dictionary,plan: Dictionary) -> Dictionary:
	var rules: Dictionary=state["opening"]["definition"]["fountain"]
	var fountain:={"kind":"fountain","id":state["next_id"],"model_id":rules["model"],
		"x":plan["x"],"z":plan["z"],"turns":0,"reaction_until":0}
	state["next_id"]+=1
	state["props"].append(fountain)
	return fountain


static func celebrate(state: Dictionary,id: Variant,seconds: float) -> void:
	var fountain:=find(state,id)
	var rules: Dictionary=state["opening"]["definition"]["fountain"]
	fountain["reaction_until"]=int(state["tick"])+ceili(float(rules["reaction_seconds"])/seconds)
	var happiness: Dictionary=state["progression"]["happiness"]
	happiness["player"]=clampf(float(happiness["player"])+float(rules["happiness"]),0,1)
