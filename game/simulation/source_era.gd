extends RefCounted
## Original period/sticker-era cache. Unlock predicates and period effects are
## pure simulation services. A render query must operate on a detached cache.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func initial() -> Dictionary:
	return {"cache_valid":false,"period":0,"era":0}


static func valid(state: Variant) -> bool:
	return state is Dictionary and state.get("cache_valid") is bool and Numbers.integer_between(state.get("period"),0,4294967295) and Numbers.integer_between(state.get("era"),0,4294967295)


static func restore(saved: Variant) -> Dictionary:
	if not saved is Dictionary or not saved.get("cache_valid") is bool: return {}
	# Old research-only saves have no derived period/era values. Invalidate them
	# instead of retaining a valid flag for values that were never computed.
	if not saved.has("period") and not saved.has("era"): return initial()
	if not valid(saved): return {}
	return {"cache_valid":saved["cache_valid"],"period":int(saved["period"]),"era":int(saved["era"])}


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Numbers.integer_between(rules.get("maximum"),0,12): return false
	for field: String in ["period_template","era_template"]:
		if not rules.get(field) is String or rules[field].count("%d")!=1 or rules[field].length()>128 or rules[field].to_utf8_buffer().has(0): return false
	return true


static func refresh(cache: Dictionary,global_cache: Dictionary,rules: Dictionary,service: Callable) -> bool:
	if not valid(cache) or not valid(global_cache) or not valid_rules(rules) or not service.is_valid(): return false
	if cache["cache_valid"]: return true
	cache["cache_valid"]=true
	cache["era"]=0
	var period := 0
	for index in range(int(rules["maximum"]),-1,-1):
		if period!=0: break
		if bool(service.call("unlocked",[rules["period_template"].replace("%d",str(index))])): period=index
	for index in range(int(rules["maximum"]),-1,-1):
		if int(cache["era"])!=0: break
		if bool(service.call("unlocked",[rules["era_template"].replace("%d",str(index))])): cache["era"]=index
	if int(cache["period"])!=period:
		cache["period"]=period
		if period!=0 and period!=1:
			# The native refresh explicitly reenters the global cache before
			# notifying, even when the current cache already is the global one.
			refresh(global_cache,global_cache,rules,service)
			service.call("period_changed",[int(global_cache["period"])])
	return true


static func era(cache: Dictionary,rules: Dictionary,service: Callable) -> int:
	if not refresh(cache,cache,rules,service): return 0
	return int(cache["era"])


static func sticker_era(progression: Dictionary,rules: Dictionary) -> int:
	if rules.is_empty(): return int(progression.get("age",1))
	return era(initial(),rules,func(name: String,args: Array) -> bool:
		return name=="unlocked" and Unlocks.enabled(progression,args[0]))
