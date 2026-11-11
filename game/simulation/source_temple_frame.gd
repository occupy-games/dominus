extends RefCounted
## Native pre-work frame: worker presence, passive work, forced decay, actual
## footprint transitions, spatial refresh, cooldown and vertical targeting.
## Settlement-affiliation refresh precedes this frame. Downward motion is an
## explicit simulation service; presentation cannot change the stored height.

const Phase = preload("res://simulation/source_temple_terrain.gd")
const Footprint = preload("res://simulation/source_temple_footprint.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Repair = preload("res://simulation/source_temple_repair.gd")


class RepairContext extends RefCounted:
	var state: Dictionary
	var service: Callable

	func route(name: String,args: Array) -> Variant:
		if name=="sound":
			var positioned := args.duplicate(true)
			positioned[1]=[float(state["x"]),float(state["z"]),float(state["height"])]
			return service.call(name,positioned)
		return service.call(name,args)


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["forced_decay_rate","presence_rate","passive_work_rate","ground_offset","boat_height","rise_speed","motion_default"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	return rules["forced_decay_rate"]>0 and rules["presence_rate"]>0 and rules["passive_work_rate"]>0 and rules["rise_speed"]>0


static func valid(state: Variant) -> bool:
	if not Phase.valid(state) or not Footprint.valid(state): return false
	for key: String in ["work_presence","cooldown","height_ceiling"]:
		var value: Variant=state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or Terrain.f32(float(value))!=float(value): return false
	return Numbers.integer_between(state.get("handle"),0,65534) and Numbers.integer_between(state.get("motion_handle"),0,4294967295)


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result := Phase.restore(saved)
	for key: String in ["handle","motion_handle"]: result[key]=int(result[key])
	for key: String in ["x","z","height","work_presence","cooldown","height_ceiling"]: result[key]=float(result[key])
	return result


static func advance(state: Dictionary,rules: Dictionary,phase_rules: Dictionary,footprint_rules: Dictionary,workers: int,delta: float,raw_ground: Callable,world_ground: Callable,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not Phase.valid_rules(phase_rules) or not Footprint.valid_rules(footprint_rules): return false
	if not Numbers.integer_between(workers,0,4294967295) or not is_finite(delta) or delta<0 or not is_finite(Terrain.f32(delta)) or not raw_ground.is_valid() or not world_ground.is_valid() or not service.is_valid(): return false
	var dt := Terrain.f32(delta)
	if float(state["work_presence"])<1 and workers>0:
		state["work_presence"]=Terrain.f32(minf(1,float(state["work_presence"])+Terrain.f32(float(workers))*dt*float(rules["presence_rate"])))
	if state["forced"]: state["timer"]=Terrain.f32(float(state["timer"])+dt*float(rules["forced_decay_rate"]))
	if int(state["transition_mode"])!=0 and int(state["phase"]) in [5,6]:
		state["progress"]=Terrain.f32(float(state["progress"])+dt*float(rules["passive_work_rate"]))
	if not Phase.advance_with_footprint(state,state,phase_rules,footprint_rules,dt,raw_ground,service): return false
	service.call("spatial_refresh",[1])
	if float(state["cooldown"])>0: state["cooldown"]=Terrain.f32(float(state["cooldown"])-dt)
	var sampled: Variant=world_ground.call(float(state["x"]),float(state["z"]),0)
	if not (sampled is int or sampled is float) or not is_finite(float(sampled)): return false
	var target := minf(Terrain.f32(Terrain.f32(float(sampled))+float(rules["ground_offset"])),float(state["height_ceiling"]))
	if bool(service.call("is_boat",[])): target=float(rules["boat_height"])
	if float(state["height"])<target and int(state["transition_mode"])==0 and int(state["motion_handle"])==0:
		state["height"]=Terrain.f32(float(state["height"])+minf(target-float(state["height"]),dt*float(rules["rise_speed"])))
	elif float(state["height"])>target and not bool(service.call("motion_locked",[])):
		var parameter := float(rules["motion_default"])
		service.call("move_vertical",[target,parameter,parameter,parameter,0])
	return true


static func valid_repair_inputs(state: Dictionary,rules: Dictionary,phase_rules: Dictionary,footprint_rules: Dictionary,repair_rules: Dictionary,totals: Dictionary,delta: float,player: int,raw_ground: Callable,world_ground: Callable,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not Phase.valid_rules(phase_rules) or not Footprint.valid_rules(footprint_rules): return false
	if not Repair.valid(state) or not Repair.valid_rules(repair_rules) or not Numbers.integer_between(player,0,4294967295): return false
	# Both earlier ports name the same native +0x3c4 slot. They must never
	# become two independently editable facts in the composed state.
	if int(state["start_block"])!=int(state.get("transition_mode",-1)): return false
	for key: String in ["workers","contributors"]:
		if not Numbers.integer_between(totals.get(key),0,4294967295): return false
	var skill: Variant=totals.get("skill_sum")
	if not (skill is int or skill is float) or not is_finite(float(skill)): return false
	return is_finite(delta) and delta>=0 and is_finite(Terrain.f32(delta)) and raw_ground.is_valid() and world_ground.is_valid() and service.is_valid()


static func advance_repair(state: Dictionary,rules: Dictionary,phase_rules: Dictionary,footprint_rules: Dictionary,repair_rules: Dictionary,totals: Dictionary,delta: float,mode: int,player: int,raw_ground: Callable,world_ground: Callable,service: Callable) -> Dictionary:
	var rejected := {"ok":false,"completed":false}
	if not valid_repair_inputs(state,rules,phase_rules,footprint_rules,repair_rules,totals,delta,player,raw_ground,world_ground,service): return rejected
	if not advance(state,rules,phase_rules,footprint_rules,int(totals["workers"]),delta,raw_ground,world_ground,service): return rejected
	var context := RepairContext.new()
	context.state=state
	context.service=service
	return {"ok":true,"completed":Repair.advance_work(state,repair_rules,totals,delta,mode,player,context.route)}
