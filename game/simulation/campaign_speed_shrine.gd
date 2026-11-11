extends RefCounted
## Fitter Followers, the original Speed Shrine and its follower stat effects.

const KIND := "speed_shrine"
const CARD := "Card_Speed_1"
const POWER := "GodPower_PlaceSpeed"
const UPGRADE := "campaign_speed_shrine_upgrade"
const Monuments = preload("res://simulation/campaign_monuments.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get(KIND,{})


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER or rules.get("temple_type")!="Monument_Speed": return false
	for key: String in ["model","title_key","description_key"]:
		if not rules.get(key) is String or rules[key].is_empty(): return false
	for key: String in ["fields","width","depth","radius"]:
		if not Numbers.integer_between(rules.get(key),1,1024): return false
	if not rules.get("prices") is Array or rules["prices"].is_empty(): return false
	for price: Variant in rules["prices"]:
		if not Numbers.integer_between(price,1,1000000): return false
	if not rules.get("authored_sites") is Array or not rules.get("effects") is Array or rules["effects"].size()!=2: return false
	for id: Variant in rules["authored_sites"]:
		if not id is String or not id.is_valid_int(): return false
	for effect: Variant in rules["effects"]:
		if not effect is Dictionary or not effect.get("unlock") is String or not Membership.source_float(effect.get("multiplier")) or effect["multiplier"]<=0: return false
	if not rules.get("upgrades") is Array or rules["upgrades"].size()!=2: return false
	for upgrade: Variant in rules["upgrades"]:
		if not upgrade is Dictionary or not upgrade.get("currency") in ["wheat","ore"] or not Numbers.integer_between(upgrade.get("cost"),1,1000000): return false
		for key: String in ["id","unlock","button","title","description"]:
			if not upgrade.get(key) is String or upgrade[key].is_empty(): return false
		if upgrade.has("radius") and not Numbers.integer_between(upgrade["radius"],int(rules["radius"]),1024): return false
	return true


static func authored(state: Dictionary) -> Array:
	var rules:=rules_for(state)
	if rules.is_empty(): return []
	var sites: Array=state.get("progression",{}).get("shrines",[])
	return sites.filter(func(site: Dictionary) -> bool:
		return site["id"] in rules["authored_sites"] and site.get("model_id")==rules["model"] and site.get("type")==rules["temple_type"])


static func initialize(state: Dictionary) -> void:
	for site: Dictionary in authored(state):
		if not site.has("affiliation_due"):
			site.merge({"complete":true,"settlement_id":-1,"affiliation_due":0.0},true)


static func discover(state: Dictionary,fields: int,events: Array) -> void:
	var rules:=rules_for(state)
	if rules.is_empty(): return
	var p: Dictionary=state["progression"]
	if fields>=int(rules["fields"]) and not CARD in p["discovered"]:
		preload("res://simulation/progression.gd").discover(p,CARD)
		if CARD in p["discovered"]:
			events.append({"type":"card_discovered","card":CARD})
			events.append({"type":"campaign_autosave"})
	if not POWER in p["powers"] and Unlocks.enabled(p,POWER):
		p["powers"].append(POWER)
		p["revision"]+=1


static func parameters(state: Dictionary,rules: Dictionary) -> Dictionary:
	var p: Dictionary=state["progression"]
	var radius: float=rules["radius"]
	var factors: Array=[]
	for upgrade: Dictionary in rules["upgrades"]:
		if upgrade.has("radius") and Unlocks.enabled(p,upgrade["unlock"]): radius=upgrade["radius"]
	for effect: Dictionary in rules["effects"]:
		if Unlocks.enabled(p,effect["unlock"]): factors.append(effect["multiplier"])
	return {"radius":radius,"factors":factors}


static func status(state: Dictionary) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty(): return {}
	return Monuments.status(state,KIND,rules,POWER in state["progression"]["powers"],parameters(state,rules))


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	return Monuments.inspect(world,state,command,rules_for(state),status(state),UPGRADE)


static func movement_areas(state: Dictionary,shrines: Array,raw_height: Callable) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty(): return {}
	var sites: Array=[]
	var owners: Dictionary={}
	var parameters_:=parameters(state,rules)
	for shrine: Dictionary in shrines:
		if shrine.get("kind",shrine.get("type")) not in [KIND,rules["temple_type"]]: continue
		if owners.is_empty() and int(shrine["settlement_id"])!=-1: owners=Monuments.settlement_sites(state,raw_height)
		sites.append(Monuments.area(shrine,parameters_["radius"],owners))
	return {} if sites.is_empty() else {"sites":sites,"owners":owners,"factors":parameters_["factors"]}


static func route_speed(base: float,point: Vector2,areas: Dictionary,raw_height: Callable) -> float:
	if areas.is_empty(): return base
	var sampled:=false
	var at: Array=[point.x,point.y,0.0]
	for site: Dictionary in areas["sites"]:
		# The original broad phase uses the shrine radius, then the inherited
		# settlement sphere can further restrict which followers receive its mask.
		var distance:=point.distance_squared_to(Vector2(site["x"],site["z"]))
		if distance>float(site["radius"])*float(site["radius"]): continue
		if not sampled and int(site["settlement_id"])!=-1:
			at[2]=Terrain.surface_height(raw_height.call(point.x,point.y))
			sampled=true
		if not Membership._contains(site,at,areas["owners"]): continue
		# Overlapping shrines OR identical effect bits. Apply each unlocked
		# row once in table order, including the source's second multiplier.
		for factor: float in areas["factors"]: base=Terrain.f32(base*factor)
		return base
	return base


static func inspect_building(world: RefCounted,state: Dictionary,id: Variant) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty(): return {}
	var candidates: Array=authored(state) if id is String else state["props"]
	for shrine: Dictionary in candidates:
		if shrine["id"]==id and shrine.get("kind",KIND)==KIND:
			return Monuments.details(world,state,shrine,rules,parameters(state,rules)["radius"])
	return {}
