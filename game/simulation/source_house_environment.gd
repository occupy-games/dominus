extends RefCounted
## Ordered source environment buffs following shrine modifiers (0x100b7744).

const Effects = preload("res://simulation/source_temple_effects.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")


static func valid(records: Variant) -> bool:
	if not records is Array or records.size()>16:
		return false
	for record: Variant in records:
		if not record is Dictionary or not record.get("unlock") is String or record["unlock"].is_empty() or not record.get("field") is String or record["field"].is_empty():
			return false
		if not Numbers.integer_between(record.get("kind"),0,3) or not Numbers.integer_between(record.get("operation"),0,1):
			return false
		if not Membership.source_float(record.get("value")) or not Membership.source_float(record.get("cap")):
			return false
		for flag: String in ["abode","monastery","farm","mine"]:
			if not Numbers.integer_between(record.get(flag),0,1):
				return false
	return true


static func valid_samples(nearby: Variant,beauty: Variant) -> bool:
	if not nearby is Array or nearby.size()!=3 or not valid_beauty_fraction(beauty):
		return false
	for count: Variant in nearby:
		if not Numbers.integer_between(count,0,2147483647):
			return false
	return true


static func valid_beauty_fraction(value: Variant) -> bool:
	return Membership.source_float(value) and float(value)>=0.0 and float(value)<=1.0


static func contribution(record: Dictionary,sample: float) -> float:
	var value := float(record["value"])
	var cap := float(record["cap"])
	var amount := value*sample
	if int(record["operation"])==1:
		amount=1.0+(value-1.0)*sample if int(record["kind"])==2 else pow(value,sample)
	return Terrain.f32(minf(amount,cap) if cap>=1.0 else maxf(amount,cap))


static func apply(values: Dictionary,records: Array,parameters: Dictionary,monastery: bool,nearby: Array,beauty: float,unlocked: Callable) -> void:
	# Counters are stored as tree, God Seed, rock. Buff IDs enumerate tree,
	# rock, beautification and God Seed.
	var samples := [Terrain.f32(float(nearby[0])),Terrain.f32(float(nearby[2])),beauty,Terrain.f32(float(nearby[1]))]
	for record: Dictionary in records:
		if not unlocked.call(record["unlock"]) or not Effects.house_applies(record,parameters,monastery):
			continue
		var field: String=record["field"]
		if not values.has(field):
			continue
		var before := float(values[field])
		var amount := contribution(record,samples[int(record["kind"])])
		values[field]=Terrain.f32(before+amount if int(record["operation"])==0 else before*amount)
