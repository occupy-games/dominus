extends RefCounted
## Source desktop cliff tool: the researched cap applies to a held face.

const CARD := "Card_CliffSculptingLevel1"
const POWER := "GodPower_CliffSculpt"


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER: return false
	var numbers:=preload("res://simulation/source_plot_schedule.gd")
	if not numbers.integer_between(rules.get("population"),1,100000) or not numbers.integer_between(rules.get("layers"),2,63): return false
	for key: String in ["belief_multiplier","belief_threshold"]:
		var value: Variant=rules.get(key)
		if not (value is float or value is int) or not is_finite(value) or value<=0: return false
	if not rules.get("layers_label") is String or not rules.get("upgrades",[]) is Array: return false
	var previous: int=rules["layers"]
	var ids: Dictionary={}
	for upgrade: Variant in rules.get("upgrades",[]):
		if not upgrade is Dictionary or not upgrade.get("id") is String or ids.has(upgrade["id"]): return false
		if not numbers.integer_between(upgrade.get("layers"),previous+1,63) or not numbers.integer_between(upgrade.get("cost"),1,1000000): return false
		if not upgrade.get("currency") in ["gems","wheat","ore"]: return false
		for key: String in ["button","title","description"]:
			if not upgrade.get(key) is String: return false
		ids[upgrade["id"]]=true
		previous=upgrade["layers"]
	return true


static func layers(state: Dictionary) -> int:
	var rules: Dictionary=state.get("opening",{}).get("definition",{}).get("cliff_sculpt",{})
	if rules.is_empty() or not POWER in state["progression"]["powers"]: return 0
	var cap: int=rules["layers"]
	var flags: Dictionary=state["progression"].get("script_unlocks",{})
	for upgrade: Dictionary in rules.get("upgrades",[]):
		if not flags.get(upgrade["id"],false): break
		cap=upgrade["layers"]
	return cap


static func status(state: Dictionary) -> Dictionary:
	var cap:=layers(state)
	if cap==0: return {}
	var result:={"layers":cap}
	for upgrade: Dictionary in state["opening"]["definition"]["cliff_sculpt"].get("upgrades",[]):
		if int(upgrade["layers"])<=cap: continue
		result["next"]=upgrade.duplicate(true)
		result["affordable"]=int(state.get(upgrade["currency"],0))>=int(upgrade["cost"])
		break
	return result


static func inspect_upgrade(state: Dictionary,id: Variant) -> Dictionary:
	var current:=status(state)
	var next: Dictionary=current.get("next",{})
	if next.is_empty() or next["id"]!=id or not current["affordable"]:
		return {"ok":false,"cost":0,"reason":""}
	return {"ok":true,"cost":0,"reason":"","resource_cost":{next["currency"]:next["cost"]},"upgrade":next["id"]}


static func target(height: int,high: int,low: int,cap: int,extend: bool) -> int:
	if extend: return maxi(height,mini(height+cap,mini(high,low+cap)))
	return mini(height,maxi(height-cap,maxi(low,high-cap)))


static func belief_units(change: int,rules: Dictionary) -> float:
	if change<rules["belief_threshold"]: return float(change)
	return float(change)*(1.0+float(change)*float(rules["belief_multiplier"]))
