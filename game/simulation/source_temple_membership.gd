extends RefCounted
## Original timed temple affiliation and containment. Candidate order is the
## source active-list order; later containing settlements overwrite earlier ones.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func source_float(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and Terrain.f32(float(value))==float(value)


static func valid_rules(rules: Variant) -> bool:
	return rules is Dictionary and source_float(rules.get("interval_half")) and float(rules["interval_half"])>0 and source_float(rules.get("random_divisor")) and float(rules["random_divisor"])>0


static func valid_site(site: Variant) -> bool:
	if not site is Dictionary or not site.get("is_settlement") is bool or not Numbers.integer_between(site.get("handle"),0,65534) or not Numbers.integer_between(site.get("settlement_id"),-1,2147483647): return false
	for key: String in ["x","z","height","radius"]:
		if not source_float(site.get(key)) or absf(float(site[key]))>1000000: return false
	return true


static func valid(state: Variant) -> bool:
	return valid_site(state) and source_float(state.get("affiliation_due"))


static func valid_sites(sites: Variant) -> bool:
	if not sites is Array or sites.size()>65535: return false
	var seen := {}
	for site: Variant in sites:
		if not valid_site(site) or seen.has(int(site["handle"])): return false
		seen[int(site["handle"])]=true
	return true


static func valid_owners(owners: Variant) -> bool:
	if not owners is Dictionary or owners.size()>65535: return false
	for key: Variant in owners:
		if not key is String or not key.is_valid_int() or key!=str(int(key)) or not Numbers.integer_between(int(key),0,2147483647): return false
		var owner: Variant=owners[key]
		if not owner is Dictionary: return false
		for field: String in ["x","z","height","radius"]:
			if not source_float(owner.get(field)) or absf(float(owner[field]))>1000000: return false
	return true


static func valid_point(point: Variant) -> bool:
	if not point is Array or point.size()!=3: return false
	for value: Variant in point:
		if not source_float(value) or absf(float(value))>1000000: return false
	return true


static func contains(site: Dictionary,point: Array,owners: Dictionary) -> bool:
	if not valid_site(site) or not valid_point(point) or not valid_owners(owners): return false
	return _contains(site,point,owners)


static func _contains(site: Dictionary,point: Array,owners: Dictionary) -> bool:
	var center: Dictionary=site
	var inherited: bool=int(site["settlement_id"])!=-1 and not site["is_settlement"]
	if inherited:
		center=owners.get(str(int(site["settlement_id"])),{})
		if center.is_empty(): return false
	var dx := float(point[0])-float(center["x"])
	var dz := float(point[1])-float(center["z"])
	var height := 0.0
	if inherited:
		dx=Terrain.f32(dx); dz=Terrain.f32(dz)
		height=Terrain.f32(float(point[2])-float(center["height"]))
	var squared := Terrain.f32(dx*dx+dz*dz+height*height)
	var radius_squared := float(center["radius"])*float(center["radius"])
	if not inherited: radius_squared=Terrain.f32(radius_squared)
	return squared<radius_squared if inherited else squared<=radius_squared


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for key: String in ["handle","settlement_id"]: result[key]=int(result[key])
	for key: String in ["x","z","height","radius","affiliation_due"]: result[key]=float(result[key])
	return result


static func refresh(state: Dictionary,sites: Array,owners: Dictionary,rules: Dictionary,clock: Callable,random_word: Callable,service: Callable) -> Dictionary:
	var rejected := {"ok":false,"refreshed":false}
	if not valid(state) or not valid_sites(sites) or not valid_owners(owners) or not valid_rules(rules) or not clock.is_valid() or not random_word.is_valid() or not service.is_valid(): return rejected
	service.call("refresh_modifiers",[])
	var now: Variant=clock.call(0)
	if not source_float(now): return rejected
	if float(state["affiliation_due"])>=float(now): return {"ok":true,"refreshed":false}
	if int(state["settlement_id"])==-1 and not state["is_settlement"]:
		var point: Array=[state["x"],state["z"],state["height"]]
		for site: Dictionary in sites:
			if site["is_settlement"] and _contains(site,point,owners): state["settlement_id"]=int(site["settlement_id"])
	var word: Variant=random_word.call()
	if not Numbers.integer_between(word,0,32767): return rejected
	var normalized := Terrain.f32(float(word)/float(rules["random_divisor"]))
	var half := float(rules["interval_half"])
	var offset := Terrain.f32(normalized*half+half)
	var later: Variant=clock.call(0)
	if not source_float(later): return rejected
	state["affiliation_due"]=Terrain.f32(float(later)+half+offset)
	return {"ok":true,"refreshed":true}
