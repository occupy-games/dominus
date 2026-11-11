extends RefCounted
## Source 0x100b7e80. The stat getter and the global override are explicit
## inputs. A per-house override is separate from post-completion timers.

const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")


static func valid_inputs(house: Dictionary,modifiers: Dictionary,global_override: float) -> bool:
	if not house.get("reference_attached") is bool:
		return false
	if not Membership.source_float(global_override) or not Membership.source_float(house.get("build_time_override",0.0)):
		return false
	if not Membership.source_float(modifiers.get("build_time")) or not Membership.source_float(modifiers.get("farm_build_time")):
		return false
	if not Numbers.integer_between(house.get("special",0),0,4294967295):
		return false
	return Numbers.integer_between(house.get("attached_kind" if house["reference_attached"] else "profession",0),0,4294967295)


static func resolve(house: Dictionary,modifiers: Dictionary,global_override: float,stats: Callable) -> float:
	if global_override>0.0:
		return global_override
	var override := float(house.get("build_time_override",0.0))
	if override>0.0:
		return override
	var build_time := stat(stats,"build time")
	var target := Terrain.f32(build_time*float(modifiers["build_time"]))
	if int(house.get("special",0))!=0:
		var kind := int(house.get("attached_kind" if house["reference_attached"] else "profession",0))
		if kind==1:
			target=Terrain.f32(target*float(modifiers["farm_build_time"]))
	return target


static func stat(stats: Callable,field: String) -> float:
	var row: Variant=stats.call()
	if not row is Dictionary:
		return NAN
	var value: Variant=row.get(field)
	if not (value is float or value is int):
		return NAN
	return Terrain.f32(float(value))
