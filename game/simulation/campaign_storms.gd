extends RefCounted
## The regular in-game weather clock. Chest placement runs once at storm end.

const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Placement = preload("res://simulation/source_chest_placement.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["StormRegularity","StormTimeOfDay","StormLikelihood","stormLengthMin","stormLengthMax","ChestWidth"]:
		if not Placement.finite(rules.get(key)) or float(rules[key])<0: return false
	return rules["StormRegularity"]>0 and rules["StormTimeOfDay"]<1 and rules["StormLikelihood"]<=1 and rules["stormLengthMin"]>0 and rules["stormLengthMax"]>=rules["stormLengthMin"]


static func valid(saved: Variant,rules: Variant) -> bool:
	return valid_rules(rules) and saved is Dictionary and Numbers.integer_between(saved.get("window"),0,2147483647) and Numbers.integer_between(saved.get("serial"),0,2147483647) and Placement.finite(saved.get("remaining")) and saved["remaining"]>=0 and saved["remaining"]<=rules["stormLengthMax"]


static func advance(opening: Dictionary,unlocked: bool,seconds: float,word: Callable) -> bool:
	var definition: Dictionary=opening["definition"]
	var rules: Dictionary=definition.get("storm_timing",{})
	if rules.is_empty(): return false
	var clock: Dictionary=opening["clock"]
	var day_fraction := Terrain.f32(float(clock["time"])/float(definition["day_cycle"]["period"]))
	var day := Terrain.f32(float(clock.get("days",0))+day_fraction)
	var window := maxi(0,floori(Terrain.f32((day-Terrain.f32(float(rules["StormTimeOfDay"])))/float(rules["StormRegularity"]))))
	if not opening.has("storm"):
		if unlocked: opening["storm"]={"window":window,"remaining":0.0,"serial":0}
		return false
	var storm: Dictionary=opening["storm"]
	var crossed := window>int(storm["window"])
	storm["window"]=window
	if storm["remaining"]>0:
		storm["remaining"]=maxf(0.0,float(storm["remaining"])-seconds)
		return storm["remaining"]==0
	if not unlocked or not crossed: return false
	var divisor := float(definition["storm_chest_rules"]["random_divisor"])
	if Terrain.f32(float(word.call())/divisor)<=float(rules["StormLikelihood"]):
		storm["remaining"]=Terrain.f32(lerpf(float(rules["stormLengthMin"]),float(rules["stormLengthMax"]),Terrain.f32(float(word.call())/divisor)))
	return false
