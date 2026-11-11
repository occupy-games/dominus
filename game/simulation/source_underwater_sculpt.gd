extends RefCounted
## Source depths and non-granite underwater belief quotes.

const CARD := "Card_UnderWaterSculpt"
const KEY := "underwater_sculpt"
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get(KEY,{})


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("unlock")!="DeepWaterSculpt": return false
	if not Numbers.integer_between(rules.get("population"),1,100000) or not Numbers.integer_between(rules.get("sea_level"),1,63): return false
	if not Numbers.integer_between(rules.get("shallow_level"),0,int(rules["sea_level"])-1): return false
	for key: String in ["belief_threshold","belief_multiplier"]:
		if not finite_nonnegative(rules.get(key)): return false
	var curve: Variant=rules.get("cost_curve")
	if not curve is Array or curve.size()!=8: return false
	var previous:=-1
	for knot: Variant in curve:
		if not knot is Array or knot.size()!=2 or not Numbers.integer_between(knot[0],previous+1,255) or not finite_nonnegative(knot[1]): return false
		previous=int(knot[0])
	return int(curve[0][0])<int(rules["shallow_level"]) and previous>=int(rules["sea_level"])


static func finite_nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=0


static func minimum_layer(state: Dictionary) -> int:
	var rules:=rules_for(state)
	if rules.is_empty(): return 0
	var raw:=0 if Unlocks.enabled(state["progression"],rules["unlock"]) else int(rules["shallow_level"])
	return raw-int(rules["sea_level"])


static func cost(before: int,after: int,rules: Dictionary) -> float:
	var low:=mini(before,after)
	var high:=maxi(before,after)
	var curve: Array=rules["cost_curve"]
	var amount:=0.0
	if high>int(curve.back()[0]):
		# The original overflow branch replaces the accumulated quote.
		for knot: Array in curve: amount=maxf(amount,knot[1])
	else:
		for raw in range(low,mini(high,int(curve[0][0]))): amount=Terrain.f32(amount+float(curve[0][1]))
		for index in range(curve.size()-1):
			var left: Array=curve[index]
			var right: Array=curve[index+1]
			var slope:=Terrain.f32(1.0/(float(right[0])-float(left[0])))
			for raw in range(maxi(low,int(left[0])),mini(high,int(right[0]))):
				var rate:=float(left[1])+(float(right[1])-float(left[1]))*(raw-int(left[0]))*slope
				amount=Terrain.f32(amount+rate)
	var change:=high-low
	var multiplier:=Terrain.f32(1.0+change*Terrain.f32(rules["belief_multiplier"])) if change>=float(rules["belief_threshold"]) else 1.0
	return Terrain.f32(amount*multiplier)
