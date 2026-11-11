extends RefCounted
## Query recovered named house fields from the base row, stored shrine mask
## and current scenery/beautification samples, in original order.

const Base = preload("res://simulation/source_house_base_stats.gd")
const Effects = preload("res://simulation/source_temple_effects.gd")
const EnvironmentBuffs = preload("res://simulation/source_house_environment.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Hash = preload("res://simulation/source_hash.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")


static func resolve(definition: Dictionary,house: Dictionary,attachment: Variant,unlocked: Callable) -> Dictionary:
	# Definition tables are validated when loading content or restoring a save.
	if not definition.has("house_base_stats") or not definition.has("temple_effects") or not definition.has("house_environment"):
		return {}
	if not Numbers.integer_between(house.get("house_index"),0,63) or not Numbers.integer_between(house.get("special"),0,4294967295) or not unlocked.is_valid():
		return {}
	var mask: Variant=house.get("mask",[0,0])
	if not Effects.valid_mask(mask) or not EnvironmentBuffs.valid_samples(house.get("nearby"),house.get("beauty_fraction")):
		return {}
	var row := Base.resolve(definition["house_base_stats"],int(house["house_index"]),attachment)
	if row.is_empty():
		return {}
	var kind: Variant=house.get("profession") if attachment==null else attachment["kind"]
	if not Numbers.integer_between(kind,0,4294967295):
		return {}
	var parameters := {"special":int(house["special"])!=0,"kind":kind,"model_type":Hash.text(row["id"])}
	var shrine: Dictionary=definition["temple_effects"]
	var values: Dictionary=row["values"]
	for record: Dictionary in Effects.house_modifiers(mask,parameters,shrine):
		var field := str(record["column"]).strip_edges().to_lower()
		if not values.has(field):
			continue
		var prior := float(values[field])
		var amount := float(record["value"])
		match int(record["operation"]):
			0: values[field]=Terrain.f32(prior+amount)
			1: values[field]=Terrain.f32(prior*amount)
	var monastery := Effects.house_is_monastery(parameters,shrine)
	EnvironmentBuffs.apply(values,definition["house_environment"],parameters,monastery,house["nearby"],float(house["beauty_fraction"]),unlocked)
	return row
