extends RefCounted
## Source settlement upgrade purchases, compression limits and worker capacity.

const KEY := "settlement_upgrades"
const COMMAND := "campaign_settlement_upgrade"
const POWERS := {"builder":"GodPower_PlaceSettlement_1","farmer":"GodPower_PlaceSettlement_2","miner":"GodPower_PlaceSettlement_3"}
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.size()!=POWERS.size(): return false
	var ids := {}
	for power: String in POWERS.values():
		var spec: Variant=rules.get(power)
		if not spec is Dictionary or not spec.get("upgrades") is Array or spec["upgrades"].size()!=4: return false
		for key: String in ["radius","population","workers"]:
			if not Numbers.integer_between(spec.get(key),1,5000): return false
		for upgrade: Variant in spec["upgrades"]:
			if not upgrade is Dictionary or not upgrade.get("currency") in ["gems","wheat","ore"]: return false
			for key: String in ["id","unlock","title","button","description"]:
				if not upgrade.get(key) is String or upgrade[key].is_empty(): return false
			for key: String in ["radius","population","workers","cost"]:
				if not Numbers.integer_between(upgrade.get(key),1,5000): return false
			if ids.has(upgrade["id"]): return false
			ids[upgrade["id"]]=true
	return true


static func parameters(state: Dictionary,power: String) -> Dictionary:
	var definition: Dictionary=state["opening"]["definition"]
	var progression: Dictionary=state["progression"]
	var source: Dictionary=definition.get(KEY,{}).get(power,{})
	if source.is_empty():
		var spec: Dictionary=progression["rules"]["economy"]["settlements"][power]
		var kind: String={POWERS["builder"]:"builder_settlement",POWERS["miner"]:"mining_settlement"}.get(power,"")
		var setting: String=definition.get(kind,{}).get("radius_setting","SettCompRadius1")
		var config: Dictionary=progression["rules"].get("economy_source",{}).get("configuration",{})
		return {"radius":config.get(setting,spec["radius"]),"population":spec["max_population"]}
	var result:={"radius":int(source["radius"]),"population":int(source["population"]),"workers":int(source["workers"])}
	for upgrade: Dictionary in source["upgrades"]:
		if not Unlocks.enabled(progression,upgrade["unlock"]): continue
		for key: String in ["radius","population","workers"]: result[key]+=int(upgrade[key])
	return result


static func next_upgrade(state: Dictionary,power: String) -> Dictionary:
	var progression: Dictionary=state["progression"]
	if not power in progression["powers"]: return {}
	for offer: Dictionary in state["opening"]["definition"].get(KEY,{}).get(power,{}).get("upgrades",[]):
		if not Unlocks.enabled(progression,offer["unlock"]): return offer
	return {}


static func status(state: Dictionary) -> Dictionary:
	var result := {}
	var supported: Dictionary=state["progression"]["rules"].get("economy",{}).get("settlements",{})
	for power: String in POWERS.values():
		if not supported.has(power): continue
		var current:=parameters(state,power)
		var offer:=next_upgrade(state,power)
		if not offer.is_empty():
			current["next"]=offer.duplicate(true)
			current["affordable"]=int(state[offer["currency"]])>=int(offer["cost"])
		result[power]=current
	return result


static func inspect(state: Dictionary,id: Variant) -> Dictionary:
	for power: String in POWERS.values():
		var offer:=next_upgrade(state,power)
		if offer.get("id")!=id or offer.is_empty() or int(state[offer["currency"]])<int(offer["cost"]): continue
		return {"ok":true,"cost":0,"reason":"","upgrade":offer["id"],"resource_cost":{offer["currency"]:offer["cost"]}}
	return {"ok":false,"cost":0,"reason":""}


static func can_release(state: Dictionary,home: Dictionary) -> bool:
	if not state["opening"]["definition"].has(KEY): return true
	for item: Dictionary in state["progression"]["settlements"]:
		if item["id"]!=home.get("settlement_id",-1): continue
		var maximum: int=parameters(state,POWERS[item["role"]])["workers"]
		var deployed:=0
		for follower: Dictionary in state["followers"]:
			if follower.get("away_home",-1)!=home["id"] or follower["state"]=="indoors": continue
			deployed+=1
			if deployed>=maximum: return false
		break
	return true
