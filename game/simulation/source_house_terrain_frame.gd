extends RefCounted
## Original 0x100bb96b..0x100bbbdb. Foundation, damage/recovery, work and
## completion are simulation data. Remaining model/economy/effect services are
## explicit; presentation cannot finish a house or remove a structural variant.

const Foundation = preload("res://simulation/source_building_foundation.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Membership = preload("res://simulation/source_temple_membership.gd")
const BuildTime = preload("res://simulation/source_house_build_time.gd")


static func signed32(value: int) -> int:
	return value-4294967296 if value>=2147483648 else value


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("complete_hook") is String or rules["complete_hook"].is_empty() or rules["complete_hook"].length()>256: return false
	for key: String in ["ordinary_seconds","attached_seconds","forced_rate","other_phase_rate"]:
		if not Membership.source_float(rules.get(key)) or float(rules[key])<=0: return false
	for key: String in ["complete_sound","complete_handle_kind","damage_notice"]:
		if not Numbers.integer_between(rules.get(key),0,4294967295): return false
	return true


static func valid(state: Variant) -> bool:
	if not Foundation.valid(state) or not state.get("reference_attached") is bool or not state.get("forced") is bool: return false
	# Original division uses a signed wrapping square. Actual house source
	# widths are positive; zero has an undefined finite-state result here.
	if not Numbers.integer_between(state["nav_size"],1,1024): return false
	if state.has("size") and not Numbers.integer_between(state["size"],int(state["nav_size"]),int(state["nav_size"])): return false
	if not Numbers.integer_between(state.get("handle"),0,65534) or not Numbers.integer_between(state.get("created_clock"),0,9223372036854775807): return false
	for key: String in ["state","variant","status_mode","identity","workers","restore_requested","appearance_dirty","completed_dirty"]:
		if not Numbers.integer_between(state.get(key),0,4294967295): return false
	for key: String in ["progress","damage_timer","post_complete_timer"]:
		if not Membership.source_float(state.get(key)): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result := Foundation.restore(saved)
	for key: String in ["handle","created_clock","state","variant","status_mode","identity","workers","restore_requested","appearance_dirty","completed_dirty"]: result[key]=int(result[key])
	for key: String in ["progress","damage_timer","post_complete_timer"]: result[key]=float(result[key])
	return result


static func target(service: Callable) -> float:
	var value: Variant=service.call("construction_target",[])
	if not (value is int or value is float): return NAN
	var stored := Terrain.f32(float(value))
	return stored if is_finite(stored) and stored>0 else NAN


static func advance_state(state: Dictionary,rules: Dictionary,delta: float,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not is_finite(delta) or delta<0 or not is_finite(Terrain.f32(delta)) or not service.is_valid(): return false
	var dt := Terrain.f32(delta)
	var phase := int(state["state"])
	if phase==3:
		state["damage_timer"]=Terrain.f32(float(state["damage_timer"])+dt*(1.0 if state["reference_attached"] else float(rules["other_phase_rate"])))
	elif phase==2:
		if int(state["uneven_count"])==0 and not state["forced"]:
			service.call("stop_damage_effect",[])
			state["state"]=0
			var required := target(service)
			if not is_finite(required): return false
			state["restore_requested"]=1
			state["progress"]=Terrain.f32((1.0-float(state["damage_timer"])/float(rules["ordinary_seconds"]))*required)
		else:
			var rate := dt
			if not state["reference_attached"]: rate*=float(signed32(int(state["uneven_count"]))) / float(int(state["nav_size"])*int(state["nav_size"]))
			state["damage_timer"]=Terrain.f32(float(state["damage_timer"])+rate)
			var limit := float(rules["attached_seconds"] if state["reference_attached"] else rules["ordinary_seconds"])
			if float(state["damage_timer"])>limit:
				if signed32(int(state["variant"]))>0:
					state["variant"]=(int(state["variant"])-1)&4294967295
					service.call("refresh_variant",[])
					state["damage_timer"]=0.0
				else:
					if ((int(state["status_mode"])-1)&4294967295)<=1: service.call("destruction_economy",[])
					service.call("stop_damage_effect",[])
				state["appearance_dirty"]=1
	elif phase==0:
		if signed32(int(state["uneven_count"]))>0:
			var progress := float(state["progress"])
			var required := target(service)
			if not is_finite(required): return false
			var fraction := Terrain.f32(progress/required)
			state["state"]=2
			state["damage_timer"]=Terrain.f32((1.0-fraction)*float(rules["ordinary_seconds"]))
			service.call("start_damage_effect",[])
			service.call("house_event",[int(state["identity"])>>29,int(rules["damage_notice"]),1,int(state["handle"])])
		else:
			var count := Terrain.f32(float(state["workers"]))
			if count>0:
				var exponent: Variant=service.call("work_exponent",[])
				if not Membership.source_float(exponent): return false
				state["progress"]=Terrain.f32(float(state["progress"])+pow(count,float(exponent))*dt)
			var progress := float(state["progress"])
			var required := target(service)
			if not is_finite(required): return false
			if progress>required:
				service.call("sound",[int(rules["complete_sound"]),state["position"].duplicate(),0,7,0])
				service.call("hook",[rules["complete_hook"],int(state["handle"])|int(rules["complete_handle_kind"])])
				state["state"]=1; state["post_complete_timer"]=0.0
				var clock: Variant=service.call("clock",[0])
				if not Numbers.integer_between(clock,0,9223372036854775807): return false
				state["created_clock"]=int(clock)
				state["completed_dirty"]=1
	return true


static func advance(state: Dictionary,rules: Dictionary,foundation_rules: Dictionary,delta: float,service: Callable,overlay: Callable,ground: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not Foundation.valid_rules(foundation_rules) or not is_finite(delta) or delta<0 or not is_finite(Terrain.f32(delta)) or not service.is_valid() or not overlay.is_valid() or not ground.is_valid(): return false
	var dt := Terrain.f32(delta)
	if state["forced"]: state["damage_timer"]=Terrain.f32(float(state["damage_timer"])+dt*(1.0 if state["reference_attached"] else float(rules["forced_rate"])))
	if not state["reference_attached"] and not Foundation.scan(state,foundation_rules,service,overlay,ground): return false
	return advance_state(state,rules,dt,service)


static func advance_with_build_time(state: Dictionary,rules: Dictionary,foundation_rules: Dictionary,delta: float,modifiers: Dictionary,global_override: float,stats: Callable,service: Callable,overlay: Callable,ground: Callable) -> bool:
	if not valid(state) or not BuildTime.valid_inputs(state,modifiers,global_override) or not stats.is_valid() or not service.is_valid():
		return false
	var route := func(name: String,args: Array) -> Variant:
		match name:
			"construction_target":
				return BuildTime.resolve(state,modifiers,global_override,stats)
			"work_exponent":
				return BuildTime.stat(stats,"new builder contribution")
		return service.call(name,args)
	return advance(state,rules,foundation_rules,delta,route,overlay,ground)
