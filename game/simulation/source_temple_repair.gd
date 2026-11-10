extends RefCounted
## Original temple affordability, raw repair start and work/completion protocol.
## These phases are native: 5 ready, 6 working, 7 complete, 8 blocked. Burial and
## destruction belong to the remaining temple lifecycle, not this work block.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func signed32(value: Variant) -> bool:
	return Numbers.integer_between(value,-2147483648,2147483647)


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not preload("res://simulation/construction_work.gd").valid_exponent(rules.get("exponent")): return false
	for key: String in ["reference_effect_value"]:
		if not (rules.get(key) is float or rules.get(key) is int) or not is_finite(float(rules[key])) or float(rules[key])<=0: return false
	for key: String in ["start_hook","complete_hook","complete_unlock","spending_unlock"]:
		if not rules.get(key) is String or rules[key].is_empty() or rules[key].length()>256: return false
	for key: String in ["dock_sound","pit_sound","ordinary_sound","ready_phase","working_phase","complete_phase","blocked_phase","temple_handle_kind","ark_finish_action","completion_notice"]:
		if not Numbers.integer_between(rules.get(key),0,4294967295): return false
	return true


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not Numbers.integer_between(state.get("handle"),0,65534) or not signed32(state.get("source_id")) or not Numbers.integer_between(state.get("phase"),0,8): return false
	for key: String in ["food_cost","ore_cost"]:
		if not signed32(state.get(key)): return false
	for key: String in ["start_block","reward_pending","notice_data"]:
		if not Numbers.integer_between(state.get(key),0,4294967295): return false
	for key: String in ["progress","required"]:
		if not (state.get(key) is int or state.get(key) is float) or not is_finite(float(state[key])) or Terrain.f32(float(state[key]))!=float(state[key]): return false
	if not state.get("reward") is String and not Numbers.integer_between(state.get("reward"),0,4294967295): return false
	if not state.get("reward_ready") is bool or not state.get("references") is Array or state["references"].size()>1024: return false
	for id: Variant in state["references"]:
		if not Numbers.integer_between(id,0,4294967295): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for key: String in ["handle","source_id","phase","food_cost","ore_cost","start_block","reward_pending","notice_data"]: result[key]=int(result[key])
	for key: String in ["progress","required"]: result[key]=float(result[key])
	for i in range(result["references"].size()): result["references"][i]=int(result["references"][i])
	if result["reward"] is float: result["reward"]=int(result["reward"])
	return result


static func currency_allowed(state: Dictionary,currency: int,rules: Dictionary,service: Callable) -> bool:
	if int(state["phase"])!=int(rules["ready_phase"]) or currency not in [1,2]: return true
	var name := "ore" if currency==1 else "food"
	return int(service.call("currency",[name]))>=int(state[name+"_cost"])


static func can_pay(state: Dictionary,rules: Dictionary,service: Callable) -> bool:
	if int(state["phase"])!=int(rules["ready_phase"]): return true
	if int(service.call("currency",["food"]))<int(state["food_cost"]): return false
	return int(service.call("currency",["ore"]))>=int(state["ore_cost"])


static func begin(state: Dictionary,rules: Dictionary,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not service.is_valid(): return false
	if int(state["phase"]) in [int(rules["blocked_phase"]),int(rules["complete_phase"]),int(rules["working_phase"])] or int(state["start_block"])!=0: return false
	service.call("hook",[rules["start_hook"],int(state["handle"])|int(rules["temple_handle_kind"])])
	if bool(service.call("spending_enabled",[])):
		service.call("spend_food",[Terrain.f32(float(state["food_cost"]))])
		service.call("spend_ore",[Terrain.f32(float(state["ore_cost"]))])
	state["phase"]=int(rules["working_phase"])
	return true


static func work_value(progress: float,delta: float,workers: int,contributors: int,skill_sum: float,exponent: float) -> float:
	var count := Terrain.f32(float(workers))
	var contributing := Terrain.f32(float(contributors))
	if count<=0 or contributing<=0: return Terrain.f32(progress)
	return Terrain.f32(Terrain.f32(progress)+(Terrain.f32(skill_sum)/contributing)*pow(count,Terrain.f32(exponent))*Terrain.f32(delta))


static func advance_work(state: Dictionary,rules: Dictionary,totals: Dictionary,delta: float,mode: int,player: int,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not service.is_valid() or not is_finite(delta) or delta<0 or not Numbers.integer_between(player,0,4294967295): return false
	for key: String in ["workers","contributors"]:
		if not Numbers.integer_between(totals.get(key),0,4294967295): return false
	if not (totals.get("skill_sum") is int or totals.get("skill_sum") is float) or not is_finite(float(totals["skill_sum"])): return false
	if int(state["phase"])!=int(rules["working_phase"]): service.call("is_settlement",[]); return false
	state["progress"]=work_value(float(state["progress"]),delta,int(totals["workers"]),int(totals["contributors"]),float(totals["skill_sum"]),float(rules["exponent"]))
	if float(state["progress"])<float(state["required"]): return false
	state["phase"]=int(rules["complete_phase"])
	if bool(service.call("is_dock",[])): service.call("sound",[int(rules["dock_sound"]),0,0,7,0])
	elif bool(service.call("is_pit",[])): service.call("sound",[int(rules["pit_sound"]),0,0,7,0])
	elif not bool(service.call("is_settlement",[])): service.call("sound",[int(rules["ordinary_sound"]),0,0,7,0])
	service.call("hook",[rules["complete_hook"],int(state["handle"])|int(rules["temple_handle_kind"])])
	if bool(service.call("is_ark",[])):
		var followers: Array=service.call("ark_followers",[])
		for follower: Dictionary in followers:
			if not follower.get("targets_site",false): continue
			service.call("transition",[int(follower["id"]),int(rules["ark_finish_action"])])
			service.call("start_action",[int(follower["id"])])
	var index := 0
	while index<state["references"].size():
		service.call("reference_effect",[player,float(rules["reference_effect_value"]),0])
		index+=1
	state["references"].clear()
	if mode==0:
		var context: Variant=service.call("notification_context",[])
		service.call("completion_notice",[context,int(rules["completion_notice"]),int(state["source_id"]),int(state["notice_data"])])
	service.call("completion_visual",[])
	var has_reward: bool=not str(state["reward"]).is_empty() if state["reward"] is String else int(state["reward"])!=0
	if has_reward:
		state["reward_pending"]=1
		state["reward_ready"]=true
	elif mode==0:
		service.call("unlock",[str(rules["complete_unlock"])%int(state["source_id"])])
	return true


static func dispatch_pending(state: Dictionary,rules: Dictionary,service: Callable) -> bool:
	# Original 0x10140b9c: this occurs before work in the next temple update.
	# Only Temple_Of_Discovery uses this branch. Its flags are cleared before
	# unlock/grant callbacks; phase and reward presence are deliberately no gate.
	if not valid(state) or not valid_rules(rules) or not service.is_valid(): return false
	if not bool(service.call("is_discovery",[])) or int(state["reward_pending"])==0: return false
	service.call("notification_context",[])
	var source_id := int(state["source_id"])
	state["reward_pending"]=0
	state["reward_ready"]=false
	service.call("unlock",[str(rules["complete_unlock"])%source_id])
	# The original reloads both fields after the unlock service returns.
	service.call("grant_temple",[state["reward"],int(state["source_id"])&4294967295,0])
	return true
