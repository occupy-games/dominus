extends RefCounted
## Original 0x1006b4d0 protocol over explicit pure simulation services.
## This is the ordinary follower path, not the Lua instant-build shortcut.

const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["builder_action","farmer_action","miner_action","target_action"]:
		if not Schedule.integer_between(rules.get(key),0,255): return false
	var half: Variant=rules.get("half")
	return (half is float or half is int) and is_finite(float(half)) and half>0 and half<=1


static func start(actor: Dictionary,plot: Dictionary,kind: int,special: bool,rules: Dictionary,services: Dictionary) -> bool:
	# Validate the transaction's available services before the first mutation.
	# Services own their normal simulation state; none may be presentation or I/O.
	if not valid_rules(rules) or not Schedule.integer_between(actor.get("owner"),0,7) or kind<0 or kind>2: return false
	if not Schedule.integer_between(actor.get("settlement"),0,4294967295): return false
	if not actor.get("position") is Array or actor["position"].size()!=3: return false
	for value: Variant in actor["position"]:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	for key: String in ["settlement","food_enabled","cost","spend","factory","payment_effect","target","transition","effect","rectangle"]:
		if not services.get(key) is Callable or not services[key].is_valid(): return false
	var settlement: int=int(actor["settlement"]) if special else int(services["settlement"].call(actor["position"].duplicate()))
	var paid := 0.0
	# The original checks this gate even for specialized workers.
	var spends: bool=services["food_enabled"].call()
	if spends and not special:
		paid=Terrain.f32(float(services["cost"].call(plot,1)))
		# Preserve native ordering, including a charge before allocation failure
		# and a zero-cost payment call. The caller's affordability gate is separate.
		services["spend"].call(paid)
	var house: Dictionary=services["factory"].call(plot,int(actor["owner"]),settlement,kind,special)
	if house.is_empty(): return false
	if paid>0.0: services["payment_effect"].call(house,1.0,1,1)
	# Native type-one references copy identity but retain their initialized
	# (-1,-1) position; they do not copy the building's world coordinates.
	var target := {"identity":int(house["identity"]),"building":int(house["id"]),"position":[-1.0,-1.0],"flag":true}
	services["target"].call(target,int(rules["target_action"]))
	var action := int(rules["builder_action"])
	if special and kind==1: action=int(rules["farmer_action"])
	elif special and kind==2: action=int(rules["miner_action"])
	services["transition"].call(action)
	services["effect"].call(house,4294967295,5,1)
	var radius := Terrain.f32(float(house["size"])*float(rules["half"]))
	var x := Terrain.f32(float(house["position"][0]))
	var z := Terrain.f32(float(house["position"][1]))
	services["rectangle"].call([Terrain.f32(x-radius),Terrain.f32(z-radius),Terrain.f32(x+radius),Terrain.f32(z+radius)])
	return true
