extends RefCounted
## The held miracle spends belief and encourages worked fields on fixed ticks.

const POWER := "GodPower_RainOfPurity"
const CARD := "Card_Adv_RainOfPurity_1"


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("power")!=POWER or rules.get("card")!=CARD: return false
	for key: String in ["fields","cost_per_second","radius","growth_bonus"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<=0: return false
	return int(rules["fields"])==rules["fields"]


static func valid_point(command: Variant,width: int) -> bool:
	if not command is Dictionary: return false
	for axis: String in ["x","z"]:
		var value: Variant=command.get(axis)
		if not (value is int or value is float) or not is_finite(value) or value<0 or value>=width: return false
	return true


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary,seconds: float) -> Dictionary:
	var rules: Dictionary=state["opening"]["definition"].get("rain",{})
	var result:={"ok":false,"cost":0,"reason":""}
	if rules.is_empty() or not POWER in state["progression"]["powers"] or not valid_point(command,state["width"]): return result
	result["ok"]=world.can_act_at(command["x"],command["z"]) and state["belief"]>=tick_cost(rules,seconds)
	return result


static func tick_cost(rules: Dictionary,seconds: float) -> int:
	return roundi(float(rules["cost_per_second"])*seconds)


static func advance(world: RefCounted,state: Dictionary,seconds: float) -> Dictionary:
	var cast: Dictionary=state["opening"].get("rain_cast",{})
	if cast.is_empty(): return {}
	if not inspect(world,state,cast,seconds)["ok"]:
		state["opening"].erase("rain_cast")
		return {}
	var rules: Dictionary=state["opening"]["definition"]["rain"]
	state["belief"]-=tick_cost(rules,seconds)
	return {"point":Vector2(cast["x"],cast["z"]),"radius":rules["radius"],"growth_bonus":rules["growth_bonus"]}


static func field_multiplier(field: Dictionary,rain: Dictionary) -> float:
	if rain.is_empty() or field["kind"]!="farm": return 1.0
	var low:=Vector2(field["x"],field["z"])-Vector2.ONE*0.5
	var high:=low+Vector2.ONE*float(field["span"])
	var point: Vector2=rain["point"]
	var nearest:=point.clamp(low,high)
	if point.distance_squared_to(nearest)>float(rain["radius"])*float(rain["radius"]): return 1.0
	return 1.0+float(rain["growth_bonus"])
