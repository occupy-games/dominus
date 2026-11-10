extends RefCounted
## Original plot food quote (0x10235bd0) and affordability predicates.
## Settlement coverage and the per-tick counted-house total are supplied state.

const Terrain = preload("res://simulation/source_terrain.gd")
const Houses = preload("res://simulation/source_houses.gd")
const Biomes = preload("res://simulation/source_biomes.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func valid_content(content: Variant) -> bool:
	if not content is Dictionary or not content.get("rules") is Dictionary or not content.get("costs") is Array or content["costs"].is_empty() or content["costs"].size()>64: return false
	for key: String in ["half","height_scale","ore_minimum"]:
		var value: Variant=content["rules"].get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return false
	if content["rules"]["half"]<=0 or content["rules"]["half"]>1 or content["rules"]["height_scale"]<=0: return false
	for i in range(content["costs"].size()):
		var row: Variant=content["costs"][i]
		if not row is Dictionary or not Schedule.integer_between(row.get("index"),i,i) or not row.get("id") is String or row["id"].is_empty(): return false
		var amount: Variant=row.get("food")
		if not (amount is int or amount is float) or not is_finite(float(amount)) or absf(float(amount))>1000000000000: return false
	return true


static func valid_definition(definition: Dictionary) -> bool:
	var content: Variant=definition.get("plot_cost")
	if not valid_content(content) or not Houses.valid(definition.get("house_selection")) or not Biomes.valid(definition.get("plot_environment")): return false
	if content["costs"].size()!=definition["house_selection"].size(): return false
	for i in range(content["costs"].size()):
		if content["costs"][i]["id"]!=definition["house_selection"][i]["id"]: return false
	return true


static func valid_plot(plot: Dictionary) -> bool:
	if not Schedule.integer_between(plot.get("size"),1,16): return false
	for key: String in ["x","z","height"]:
		var value: Variant=plot.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>10000: return false
	return true


static func quote(plot: Dictionary,mode: int,definition: Dictionary,unlocked: Callable,settlement: Callable,counted_houses: int) -> Dictionary:
	if not valid_definition(definition) or not unlocked.is_valid() or not settlement.is_valid(): return {}
	if mode!=1: return {"amount":0.0}
	if not Schedule.integer_between(counted_houses,-2147483648,2147483647) or not valid_plot(plot): return {}
	var content: Dictionary=definition["plot_cost"]
	var configuration: Dictionary=definition["plot_environment"]["configuration"]
	var rules: Dictionary=content["rules"]
	var height := Terrain.f32(float(plot["height"]))
	var band := Biomes.band(Terrain.f32(float(int(height/float(rules["height_scale"])))),configuration)
	# The cost wrapper passes scheme zero to the selector, independently of the
	# plot's actual biome and placement offset. Preserve the source conversion.
	var biome := 0
	for i in range(1,4):
		if Terrain.f32(float(configuration["biome%dIndex"%i]))==0.0:
			biome=i
			break
	var house := Houses.choose(definition["house_selection"],int(plot["size"]),band,biome,unlocked,0,false,bool(unlocked.call("HousesBiomeLocked")))
	if house.is_empty(): return {"amount":0.0}
	var half := float(int(plot["size"]))*float(rules["half"])
	var position := [Terrain.f32(Terrain.f32(float(plot["x"]))+half),Terrain.f32(Terrain.f32(float(plot["z"]))+half),height]
	var membership := int(settlement.call(position))
	var spends: bool=unlocked.call("FoodSpending")
	var multiplier := int(membership==4294967295 and counted_houses>0 and spends)
	return {"amount":Terrain.f32(float(multiplier)*Terrain.f32(float(content["costs"][int(house["index"])]["food"])))}


static func affordable(amount: float,mode: int,food: int,ore: int,rules: Dictionary) -> bool:
	if mode==1: return float(food)>=amount
	if mode==2: return float(ore)>=float(rules["ore_minimum"])
	return true


static func affordable_both(amount: float,food: int,ore: int,rules: Dictionary) -> bool:
	return float(food)>=amount and float(ore)>=float(rules["ore_minimum"])
