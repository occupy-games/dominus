extends RefCounted
## Original bulk follower modifier refresh (0x1006d050). Spatial candidates and
## temporary-node release belong to explicit simulation services. No fallback
## scan substitutes for an unavailable source spatial index.

const Effects = preload("res://simulation/source_temple_effects.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Foundation = preload("res://simulation/source_building_foundation.gd")


class FoundationContext extends RefCounted:
	var state: Dictionary
	var rules: Dictionary
	var service: Callable
	var overlay: Callable
	var ground: Callable
	var ok := true

	func route(name: String,args: Array) -> Variant:
		if name=="refresh_house_geometry":
			ok=Foundation.scan(state,rules,service,overlay,ground)
			return ok
		return service.call(name,args)


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Numbers.integer_between(rules.get("query_tag"),0,4294967295) or not Numbers.integer_between(rules.get("max_candidates"),1,4096): return false
	if not rules.get("query_flags") is Array or rules["query_flags"].size()!=6: return false
	for flag: Variant in rules["query_flags"]:
		if not Numbers.integer_between(flag,0,4294967295): return false
	return true


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not state.get("followers") is Array or state["followers"].size()>65535 or not state.get("actors") is Dictionary or state["actors"].size()>65535: return false
	for key: Variant in state["actors"]:
		if not key is String or not key.is_valid_int() or key!=str(int(key)) or not Numbers.integer_between(int(key),0,2147483647): return false
		var actor: Variant=state["actors"][key]
		if not actor is Dictionary or not Effects.valid_mask(actor.get("mask")) or not Effects.valid_mask(actor.get("extra_mask")): return false
	var seen := {}
	for follower: Variant in state["followers"]:
		if not follower is Dictionary or not Numbers.integer_between(follower.get("handle"),0,65534) or not Numbers.integer_between(follower.get("stats_ref"),-1,2147483647) or not Membership.valid_point(follower.get("position")): return false
		var handle := int(follower["handle"])
		if seen.has(handle): return false
		seen[handle]=true
		if int(follower["stats_ref"])!=-1 and not state["actors"].has(str(int(follower["stats_ref"]))): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for follower: Dictionary in result["followers"]:
		for key: String in ["handle","stats_ref"]: follower[key]=int(follower[key])
		for i in range(3): follower["position"][i]=float(follower["position"][i])
	for actor: Dictionary in result["actors"].values():
		for field: String in ["mask","extra_mask"]:
			for i in range(2): actor[field][i]=int(actor[field][i])
	return result


static func valid_candidates(candidates: Variant,followers: Dictionary,maximum: int) -> bool:
	if not candidates is Array or candidates.size()>maximum: return false
	var seen := {}
	for node: Variant in candidates:
		if not node is Dictionary or not Numbers.integer_between(node.get("token"),0,maximum-1) or not Numbers.integer_between(node.get("follower"),-1,65534): return false
		if seen.has(int(node["token"])): return false
		seen[int(node["token"])]=true
		if int(node["follower"])!=-1 and not followers.has(int(node["follower"])): return false
	return true


static func refresh(state: Dictionary,sites: Array,owners: Dictionary,rules: Dictionary,query: Callable,release: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not Effects.valid_sites(sites,owners) or not query.is_valid() or not release.is_valid(): return false
	var followers := {}
	for follower: Dictionary in state["followers"]:
		followers[int(follower["handle"])]=follower
		# Only attached active followers are cleared. Unreferenced actor records
		# and permanent masks are not part of this native pass.
		if int(follower["stats_ref"])!=-1: state["actors"][str(int(follower["stats_ref"]))]["mask"]=[0,0]
	var flags: Array=rules["query_flags"]
	for site: Dictionary in sites:
		var mask: Array=site["follower_modifiers"]
		if int(mask[0])==0 and int(mask[1])==0: continue
		# The broad-phase request uses the site's own source center and radius.
		# Actual containment below can inherit a different settlement sphere.
		var candidates: Variant=query.call(int(rules["query_tag"]),float(site["x"]),float(site["z"]),float(site["radius"]),int(flags[0]),int(flags[1]),int(flags[2]),int(flags[3]),int(flags[4]),int(flags[5]))
		if candidates==null: continue
		# Query/release are trusted simulation services. A malformed service
		# response cannot grant a bonus; earlier source-ordered clearing remains.
		if not valid_candidates(candidates,followers,int(rules["max_candidates"])): return false
		for node: Dictionary in candidates:
			var handle := int(node["follower"])
			if handle!=-1:
				var follower: Dictionary=followers[handle]
				if int(follower["stats_ref"])!=-1 and Membership._contains(site,follower["position"],owners):
					var actor: Dictionary=state["actors"][str(int(follower["stats_ref"]))]
					for i in range(2): actor["mask"][i]=int(actor["mask"][i])|int(mask[i])
			release.call(int(node["token"]))
	return true


static func valid_house(state: Variant) -> bool:
	return state is Dictionary and Membership.valid_point(state.get("position")) and Effects.valid_mask(state.get("mask")) and state.get("reference_attached") is bool


static func restore_house(saved: Variant) -> Dictionary:
	if not valid_house(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for i in range(3): result["position"][i]=float(result["position"][i])
	for i in range(2): result["mask"][i]=int(result["mask"][i])
	return result


static func refresh_house(state: Dictionary,sites: Array,owners: Dictionary,service: Callable) -> bool:
	if not valid_house(state) or not Effects.valid_sites(sites,owners) or not service.is_valid(): return false
	# Original 0x100b6e10 refreshes masks even when the geometry callback is
	# suppressed by an attached reference. Unchanged masks still notify.
	state["mask"]=Effects._collect(state["position"],sites,owners,1)
	if not state["reference_attached"]: service.call("refresh_house_geometry",[])
	return true


static func restore_house_foundation(saved: Variant) -> Dictionary:
	if not valid_house(saved) or not Foundation.valid(saved): return {}
	return Foundation.restore(restore_house(saved))


static func refresh_house_foundation(state: Dictionary,sites: Array,owners: Dictionary,rules: Dictionary,service: Callable,overlay: Callable,ground: Callable) -> bool:
	if not Foundation.valid(state) or not Foundation.valid_rules(rules) or not service.is_valid() or not overlay.is_valid() or not ground.is_valid(): return false
	var context := FoundationContext.new()
	context.state=state; context.rules=rules; context.service=service
	context.overlay=overlay; context.ground=ground
	return refresh_house(state,sites,owners,context.route) and context.ok
