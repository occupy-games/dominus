extends RefCounted
## Source starting values and passive decay; festival/tribal AI are separate work.


static func initial(rules: Dictionary) -> Dictionary:
	var config: Dictionary = rules.get("economy_source",{}).get("configuration",{})
	return {"player":float(config.get("PlayerStartingHappiness",0.2)),"astari":float(config.get("AstariStartingHappiness",0.3))}


static func advance(progression: Dictionary, seconds: float) -> void:
	if not progression.has("happiness"): progression["happiness"]=initial(progression["rules"])
	var config: Dictionary = progression["rules"].get("economy_source",{}).get("configuration",{})
	progression["happiness"]["player"]=clampf(float(progression["happiness"]["player"])+float(config.get("HappyDecayPerSec",0))*seconds,0,1)


static func valid(values: Variant) -> bool:
	if not values is Dictionary: return false
	for tribe: String in ["player","astari"]:
		var value: Variant = values.get(tribe)
		if not (value is float or value is int) or not is_finite(float(value)) or value<0 or value>1: return false
	return true
