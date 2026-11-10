extends RefCounted
## Compose the original ordinary follower start with the full source factory
## and logical target bookkeeping. Action/path execution is a caller service;
## reserving a worker does not establish arrival or active construction work.

const Start = preload("res://simulation/source_build_start.gd")
const Factory = preload("res://simulation/source_house_factory.gd")
const References = preload("res://simulation/source_target_references.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Cost = preload("res://simulation/source_plot_cost.gd")


static func start_priced(state: Dictionary,definition: Dictionary,parameters: Dictionary,services: Dictionary,events: Array) -> bool:
	if not Cost.valid_definition(definition) or not Schedule.integer_between(parameters.get("counted_houses"),-2147483648,2147483647): return false
	if not Registry.valid(state.get("plots")) or not Schedule.integer_between(parameters.get("plot"),0,1023): return false
	var id := int(parameters["plot"])
	if not state["plots"]["active"].has(id) or not Cost.valid_plot(state["plots"]["slots"][id]): return false
	var priced: Dictionary=services.duplicate()
	priced["cost"]=func(plot: Dictionary,mode: int) -> float:
		var result := Cost.quote(plot,mode,definition,services["unlocked"],services["settlement"],int(parameters["counted_houses"]))
		return float(result["amount"])
	return start(state,definition,parameters,priced,events)


static func start(state: Dictionary,definition: Dictionary,parameters: Dictionary,services: Dictionary,events: Array) -> bool:
	# Reject unavailable composition dependencies before the original protocol's
	# first payment. Pool exhaustion itself still happens after payment.
	if not Start.valid_rules(definition.get("build_start_rules")) or not References.valid_rules(definition.get("target_reference_rules")): return false
	if not preload("res://simulation/source_house_pool.gd").valid(state.get("houses")) or not Registry.valid(state.get("plots")): return false
	if not preload("res://simulation/source_house_constructor.gd").valid_content(definition.get("house_constructor")) or not preload("res://simulation/source_plot_conversion.gd").valid_rules(definition.get("plot_conversion_rules")): return false
	if not preload("res://simulation/source_houses.gd").valid(definition.get("house_selection")) or not preload("res://simulation/source_biomes.gd").valid(definition.get("plot_environment")): return false
	if not state.get("follower") is Dictionary or state["follower"].is_empty() or not References.valid_follower(state["follower"]) or not References.valid_shape(state.get("target")) or not References.valid_counters(state.get("counters")): return false
	if not state.get("identities") is Dictionary or not Schedule.integer_between(state["identities"].get("counter"),0,4294967295): return false
	for key: String in ["plot","kind","clock","local_owner"]:
		if not Schedule.integer_between(parameters.get(key),0,9223372036854775807): return false
	if int(parameters["kind"])>2 or int(parameters["local_owner"])>7 or not parameters.get("special") is bool: return false
	if not (parameters.get("seconds") is int or parameters.get("seconds") is float) or not is_finite(float(parameters["seconds"])): return false
	if not state.get("position") is Array or state["position"].size()!=3: return false
	for value: Variant in state["position"]:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	for key: String in ["unlocked","ground","random_word","nearby","field","mine_roll","attach","settlement","food_enabled","cost","spend","payment_effect","skill","transition","effect","rectangle"]:
		if not services.get(key) is Callable or not services[key].is_valid(): return false
	var plot_id := int(parameters["plot"])
	if not state["plots"]["active"].has(plot_id): return false
	var follower: Dictionary=state["follower"]
	var actor := {"owner":int(follower["owner"]),"settlement":int(follower["settlement_index"])&0xffffffff,"position":state["position"].duplicate()}
	var protocol: Dictionary=services.duplicate()
	protocol["factory"]=func(_plot: Dictionary,owner: int,settlement: int,kind: int,special: bool) -> Dictionary:
		var input := {"plot":plot_id,"owner":owner,"settlement":settlement,"kind":kind,"special":special,"clock":int(parameters["clock"]),"seconds":float(parameters["seconds"])}
		var result := Factory.create(state["houses"],state["plots"],state["identities"],definition,input,services,events)
		return result.get("house",{})
	protocol["target"]=func(reference: Dictionary,action: int) -> void:
		var incoming := {"identity":int(reference["identity"]),"entity":int(reference["building"]),"position":reference["position"].duplicate(),"flag":bool(reference["flag"])}
		References.assign(state["target"],incoming,follower,{"houses":state["houses"]["slots"],"plots":{}},state["counters"],definition["target_reference_rules"],action,services["skill"],int(parameters["local_owner"]))
	return Start.start(actor,state["plots"]["slots"][plot_id].duplicate(true),int(parameters["kind"]),bool(parameters["special"]),definition["build_start_rules"],protocol)
