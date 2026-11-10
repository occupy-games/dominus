extends RefCounted
## Original 0x10140ded..0x101410c8, before spatial refresh and repair work.
## The caller owns obstruction collection and the earlier timer update. Effects
## are plain intents; neither audio nor rendering decides whether a site dies.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Footprint = preload("res://simulation/source_temple_footprint.gd")


class FootprintContext extends RefCounted:
	var state: Dictionary
	var site: Dictionary
	var rules: Dictionary
	var ground: Callable
	var service: Callable

	func route(name: String,args: Array) -> Variant:
		if name=="refresh_footprint":
			state["obstruction"]=Footprint.count(site,rules,ground)
			return null
		return service.call(name,args)


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("special_types") is Array or rules["special_types"].size()!=3: return false
	for value: Variant in rules["special_types"]:
		if not Numbers.integer_between(value,0,4294967295): return false
	for key: String in ["ordinary_seconds","special_seconds","audio_fade"]:
		if not (rules.get(key) is int or rules.get(key) is float) or not is_finite(float(rules[key])) or float(rules[key])<=0 or Terrain.f32(float(rules[key]))!=float(rules[key]): return false
	for key: String in ["revive_effect","decay_effect","revive_sound","decay_sound"]:
		if not Numbers.integer_between(rules.get(key),0,4294967295): return false
	return true


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not state.get("forced") is bool: return false
	for key: String in ["phase","transition_mode","generic_type","remove_requested"]:
		if not Numbers.integer_between(state.get(key),0,8 if key=="phase" else 4294967295): return false
	for key: String in ["obstruction","audio_handle"]:
		if not Numbers.integer_between(state.get(key),-2147483648,2147483647): return false
	# The native division uses a signed, wrapping square of this value. Reject
	# undefined zero denominators at the simulation service boundary.
	if not Numbers.integer_between(state.get("footprint_width"),1,65535): return false
	for key: String in ["progress","required","timer"]:
		if not (state.get(key) is int or state.get(key) is float) or not is_finite(float(state[key])) or Terrain.f32(float(state[key]))!=float(state[key]): return false
	return float(state["required"])!=0


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for key: String in ["phase","transition_mode","generic_type","remove_requested","obstruction","audio_handle","footprint_width"]: result[key]=int(result[key])
	for key: String in ["progress","required","timer"]: result[key]=float(result[key])
	return result


static func duration(state: Dictionary,rules: Dictionary) -> float:
	return float(rules["special_seconds"] if special_type(state,rules) else rules["ordinary_seconds"])


static func special_type(state: Dictionary,rules: Dictionary) -> bool:
	for value: Variant in rules["special_types"]:
		if int(value)==int(state["generic_type"]): return true
	return false


static func advance_with_footprint(state: Dictionary,site: Dictionary,rules: Dictionary,footprint_rules: Dictionary,delta: float,ground: Callable,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not Footprint.valid(site) or not Footprint.valid_rules(footprint_rules) or int(site["footprint_width"])!=int(state["footprint_width"]) or not ground.is_valid() or not service.is_valid(): return false
	var context := FootprintContext.new()
	context.state=state
	context.site=site
	context.rules=footprint_rules
	context.ground=ground
	context.service=service
	return advance(state,rules,delta,context.route)


static func advance(state: Dictionary,rules: Dictionary,delta: float,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not service.is_valid() or not is_finite(delta) or not is_finite(Terrain.f32(delta)) or delta<0: return false
	if int(state["phase"])==0: state["phase"]=5
	elif int(state["phase"]) in [1,2]: state["phase"]=7
	service.call("refresh_footprint",[])
	if int(state["obstruction"])<=0 and not state["forced"]:
		if int(state["phase"])==8:
			state["phase"]=6 if int(state["transition_mode"])!=0 else 5
			state["progress"]=Terrain.f32((1.0-float(state["timer"])/duration(state,rules))*float(state["required"]))
			if bool(service.call("is_settlement",[])):
				service.call("start_effect",[int(rules["revive_effect"]),3])
				service.call("sound",[int(rules["revive_sound"]),0,7,0])
		return true
	if int(state["transition_mode"])!=0:
		if int(state["phase"]) in [5,6]:
			state["phase"]=8
			state["timer"]=Terrain.f32((1.0-float(state["progress"])/float(state["required"]))*duration(state,rules))
			if bool(service.call("is_settlement",[])): service.call("stop_effect",[int(rules["decay_effect"]),3])
		elif int(state["phase"])==8:
			var square: int=(int(state["footprint_width"])*int(state["footprint_width"]))&4294967295
			if square>=2147483648: square-=4294967296
			state["timer"]=Terrain.f32(float(state["timer"])+float(state["obstruction"])*Terrain.f32(delta)/float(square))
		else:
			state["timer"]=0.0
			state["phase"]=8
			if bool(service.call("is_settlement",[])): service.call("stop_effect",[int(rules["decay_effect"]),3])
	if float(state["timer"])>=duration(state,rules):
		if bool(service.call("is_settlement",[])):
			service.call("sound",[int(rules["decay_sound"]),0,7,0])
			service.call("start_effect",[int(rules["revive_effect"]),3])
		state["remove_requested"]=1
		if special_type(state,rules) and int(state["audio_handle"])>0:
			service.call("audio_lookup",[int(state["audio_handle"]),0])
			service.call("audio_release",[])
			service.call("audio_fade",[int(state["audio_handle"]),float(rules["audio_fade"])])
			state["audio_handle"]=-1
	return true
