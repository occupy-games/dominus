extends RefCounted
## Placed Shrine of Capacity and its original house-stat effect.

const KIND := "capacity_shrine"
const CARD := "Card_Capacity_1"
const POWER := "GodPower_PlaceCapacity"
const UPGRADE := "campaign_capacity_upgrade"
const Monuments = preload("res://simulation/campaign_monuments.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get(KIND,{})


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER: return false
	for key: String in ["model","temple_type","title_key","description_key"]:
		if not rules.get(key) is String or rules[key].is_empty(): return false
	for key: String in ["population","width","depth","radius","bonus"]:
		if not Numbers.integer_between(rules.get(key),1,10000): return false
	if not rules.get("prices") is Array or rules["prices"].is_empty(): return false
	for price: Variant in rules["prices"]:
		if not Numbers.integer_between(price,1,1000000): return false
	if not rules.get("upgrades") is Array or rules["upgrades"].size()!=2: return false
	var ids := {}
	for upgrade: Variant in rules["upgrades"]:
		if not upgrade is Dictionary or not upgrade.get("currency") in ["wheat","gems"]: return false
		if not Numbers.integer_between(upgrade.get("cost"),1,1000000): return false
		for key: String in ["id","button","title","description"]:
			if not upgrade.get(key) is String or upgrade[key].is_empty(): return false
		if ids.has(upgrade["id"]): return false
		ids[upgrade["id"]]=true
		if not upgrade.has("radius") and not upgrade.has("bonus"): return false
		for key: String in ["radius","bonus"]:
			if upgrade.has(key) and not Numbers.integer_between(upgrade[key],int(rules[key]),10000): return false
	return true


static func parameters(state: Dictionary,rules: Dictionary) -> Dictionary:
	var effect := {"radius":rules["radius"],"bonus":rules["bonus"]}
	var unlocks: Dictionary=state["progression"].get("script_unlocks",{})
	for upgrade: Dictionary in rules["upgrades"]:
		if not unlocks.get(upgrade["id"],false): continue
		for key: String in effect:
			if upgrade.has(key): effect[key]=upgrade[key]
	return effect


static func status(state: Dictionary) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty(): return {}
	return Monuments.status(state,KIND,rules,POWER in state["progression"]["powers"],parameters(state,rules))


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	return Monuments.inspect(world,state,command,rules_for(state),status(state),UPGRADE)


static func effects(state: Dictionary,raw_height: Callable) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty(): return {}
	var sites: Array=[]
	var owners := {}
	var current:=parameters(state,rules)
	for shrine: Dictionary in state["props"]:
		if shrine.get("kind")!=KIND: continue
		if sites.is_empty() and not state["progression"]["settlements"].is_empty(): owners=Monuments.settlement_sites(state,raw_height)
		sites.append(Monuments.area(shrine,current["radius"],owners))
	return {} if sites.is_empty() else {"sites":sites,"owners":owners,"bonus":current["bonus"],"raw_height":raw_height}


static func capacity(home: Dictionary,effect: Dictionary) -> int:
	var base:=int(home.get("capacity",2))
	if effect.is_empty() or home.get("kind","")!="" or home.get("allegiance",0)!=0 or home.get("settlement_core",false): return base
	var x:=float(home.get("anchor_x",home["x"]))
	var z:=float(home.get("anchor_z",home["z"]))
	var point: Array=[x,z,0.0]
	var sampled:=false
	for site: Dictionary in effect["sites"]:
		if not sampled and int(site["settlement_id"])!=-1:
			point[2]=Terrain.surface_height(effect["raw_height"].call(x,z))
			sampled=true
		if Membership._contains(site,point,effect["owners"]): return base+int(effect["bonus"])
	return base


static func inspect_building(world: RefCounted,state: Dictionary,id: Variant) -> Dictionary:
	var rules:=rules_for(state)
	for shrine: Dictionary in state["props"]:
		if shrine.get("kind")!=KIND or shrine["id"]!=id: continue
		return Monuments.details(world,state,shrine,rules,parameters(state,rules)["radius"])
	return {}
