extends RefCounted
## Contiguous original affiliation -> terrain/elevation -> repair update.
## Clock, seeded randomness and terrain are explicit simulation services.
## The caller still owns deferred rewards, spatial registration, motion and
## final removal; this protocol cannot enable an incomplete campaign by itself.

const Membership = preload("res://simulation/source_temple_membership.gd")
const Frame = preload("res://simulation/source_temple_frame.gd")
const Repair = preload("res://simulation/source_temple_repair.gd")
const Modifiers = preload("res://simulation/source_temple_modifiers.gd")


class Context extends RefCounted:
	var state: Dictionary
	var service: Callable

	func route(name: String,args: Array) -> Variant:
		var result: Variant=service.call(name,args)
		# The membership and work passes query the same native type. Keep it
		# authoritative rather than permitting contradictory service answers.
		if name=="is_settlement": return bool(state["is_settlement"])
		return result


class ModifierContext extends RefCounted:
	var state: Dictionary
	var records: Array
	var unlocked: Callable
	var service: Callable

	func route(name: String,args: Array) -> Variant:
		var result: Variant=service.call(name,args)
		if name=="refresh_modifiers": return Modifiers.refresh(state,records,unlocked,service)
		return result


static func valid(state: Variant) -> bool:
	return Membership.valid(state) and Frame.valid(state) and Repair.valid(state) and int(state["start_block"])==int(state["transition_mode"])


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	return Membership.restore(Repair.restore(Frame.restore(saved)))


static func advance(state: Dictionary,rules: Dictionary,sites: Array,owners: Dictionary,totals: Dictionary,delta: float,mode: int,player: int,clock: Callable,random_word: Callable,raw_ground: Callable,world_ground: Callable,service: Callable) -> Dictionary:
	var rejected := {"ok":false,"completed":false,"refreshed":false}
	for key: String in ["membership","frame","phase","footprint","repair"]:
		if not rules.get(key) is Dictionary: return rejected
	# Validate the later passes before the first modifier/clock/RNG callback.
	# Invalid saved state or configuration must not partially refresh ownership.
	if not valid(state) or not Membership.valid_rules(rules["membership"]) or not Membership.valid_sites(sites) or not Membership.valid_owners(owners) or not clock.is_valid() or not random_word.is_valid(): return rejected
	if not Frame.valid_repair_inputs(state,rules["frame"],rules["phase"],rules["footprint"],rules["repair"],totals,delta,player,raw_ground,world_ground,service): return rejected
	var membership := Membership.refresh(state,sites,owners,rules["membership"],clock,random_word,service)
	if not membership["ok"]: return rejected
	var context := Context.new()
	context.state=state
	context.service=service
	var frame := Frame.advance_repair(state,rules["frame"],rules["phase"],rules["footprint"],rules["repair"],totals,delta,mode,player,raw_ground,world_ground,context.route)
	return {"ok":frame["ok"],"completed":frame["completed"],"refreshed":membership["refreshed"]}


static func advance_modifiers(state: Dictionary,rules: Dictionary,records: Array,sites: Array,owners: Dictionary,totals: Dictionary,delta: float,mode: int,player: int,clock: Callable,random_word: Callable,unlocked: Callable,raw_ground: Callable,world_ground: Callable,service: Callable) -> Dictionary:
	if not Modifiers.valid(state) or not Modifiers.valid_records(records) or not unlocked.is_valid(): return {"ok":false,"completed":false,"refreshed":false}
	var context := ModifierContext.new()
	context.state=state
	context.records=records
	context.unlocked=unlocked
	context.service=service
	if not service.is_valid(): return {"ok":false,"completed":false,"refreshed":false}
	return advance(state,rules,sites,owners,totals,delta,mode,player,clock,random_word,raw_ground,world_ground,context.route)
