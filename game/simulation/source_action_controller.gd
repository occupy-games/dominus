extends RefCounted
## Original 0x1006ae00 action advancement. A true raw result requests a new
## decision; it does not imply that a building or campaign milestone completed.

const Sequence = preload("res://simulation/source_action_sequence.gd")
const Entry = preload("res://simulation/source_action_entry.gd")
const References = preload("res://simulation/source_target_references.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_content(content: Variant) -> bool:
	if not content is Dictionary or not content.get("rules") is Dictionary or not content.get("default_state") is Dictionary or not content.get("actions") is Array or content["actions"].size()>251: return false
	var rules: Dictionary=content["rules"]
	for key: String in ["decision_phase","native_slot","temple_state"]:
		if not Schedule.integer_between(rules.get(key),0,255): return false
	for key: String in ["house_actions","temple_actions"]:
		if not rules.get(key) is Array: return false
		for value: Variant in rules[key]:
			if not Schedule.integer_between(value,0,250): return false
	var ids := {}
	for action: Variant in content["actions"]:
		if not action is Dictionary or not Schedule.integer_between(action.get("id"),0,250) or ids.has(int(action["id"])) or not action.get("looping") is bool or not action.get("available") is bool or not action.get("states") is Array: return false
		ids[int(action["id"])]=true
		var indices := {}
		for row: Variant in action["states"]:
			if not row is Dictionary or not Schedule.integer_between(row.get("index"),0,19) or indices.has(int(row["index"])) or not row.get("available") is bool: return false
			indices[int(row["index"])]=true
			if action["available"] and not row["available"]: return false
			if row["available"] and not valid_flags(row): return false
	return valid_flags(content["default_state"]) and Entry.valid_entry(content["default_state"])


static func valid_flags(row: Dictionary) -> bool:
	return row.get("terminable") is bool and row.get("face_end") is bool and Schedule.integer_between(row.get("end_skip"),-1,2147483647)


static func compile_action(definition: Dictionary,id: int) -> Dictionary:
	var controller: Variant=definition.get("action_controller")
	if not valid_content(controller) or not Sequence.valid_content(definition.get("action_sequences")) or not Entry.valid_content(definition.get("action_entry")): return {}
	var selected := {}
	for action: Dictionary in controller["actions"]:
		if int(action["id"])==id: selected=action; break
	if selected.is_empty() or not selected["available"]: return {}
	var states := Sequence.entries(definition["action_sequences"],id)
	if states.is_empty(): return {}
	for state: Dictionary in states: state.merge(controller["default_state"],true)
	for row: Dictionary in selected["states"]:
		var index := int(row["index"])
		states[index].merge(row,true)
		var entry := Entry.find(definition["action_entry"],id,index)
		if entry.is_empty(): return {}
		states[index].merge(entry,true)
	return {"states":states,"looping":bool(selected["looping"])}


static func valid_actor(actor: Dictionary) -> bool:
	if not Entry.valid_actor(actor) or not Schedule.integer_between(actor.get("action"),0,250) or not Schedule.integer_between(actor.get("phase"),0,3) or not Schedule.integer_between(actor.get("voice"),0,1) or not Schedule.integer_between(actor.get("profile"),0,4294967295) or not actor.get("failed") is bool: return false
	for key: String in ["native_slot","gate_slot"]:
		if not Schedule.integer_between(actor.get(key),0,255): return false
	if not actor.get("target") is Dictionary or not actor.get("cached_target") is Dictionary: return false
	for key: String in ["target","cached_target"]:
		if not actor[key].is_empty() and not References.valid_shape(actor[key]): return false
	if not actor.get("position") is Array or actor["position"].size()!=3: return false
	for value: Variant in actor["position"]:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	var time: Variant=actor.get("path_time")
	return (time is int or time is float) and is_finite(float(time))


static func enter(actor: Dictionary,index: int,compiled: Dictionary,definition: Dictionary,services: Dictionary) -> Dictionary:
	if index<0 or index>=compiled["states"].size(): return {}
	return Entry.enter(actor,index,int(actor["profile"]),compiled["states"][index],definition["action_entry"]["rules"],services)


static func advance(actor: Dictionary,first: bool,definition: Dictionary,context: Dictionary,services: Dictionary) -> Dictionary:
	var compiled := compile_action(definition,int(actor.get("action",-1)))
	if compiled.is_empty() or not valid_actor(actor) or not References.valid_rules(definition.get("target_reference_rules")): return {}
	if not actor["target"].is_empty() and not ((int(actor["target"]["identity"])>>24)&31) in [1,7,31]: return {}
	for key: String in ["check","random_word","resolve","duration","orientation","animate","end_sound","request_decision","reset_navigation","target_position","face"]:
		if not services.get(key) is Callable or not services[key].is_valid(): return {}
	var rules: Dictionary=definition["action_controller"]["rules"]
	var states: Array=compiled["states"]
	var old := int(actor["step"])
	var row: Dictionary=states[old]
	var finish: bool=bool(actor["failed"]) and bool(row["terminable"])
	if not finish:
		if actor["failed"]:
			if int(row["end_skip"])>0: actor["step"]=int(row["end_skip"])
			elif not first: actor["step"]=old+1
		elif not first: actor["step"]=int(row["next"]) if int(row["next"])>=0 else old+1
		var chosen := Sequence.choose(states,int(actor["step"]),definition["action_sequences"]["rules"],services["random_word"],services["check"])
		if chosen.is_empty(): return {}
		actor["step"]=int(chosen["index"])
		if int(actor["step"])<states.size():
			var entered := enter(actor,int(actor["step"]),compiled,definition,services)
			if entered.is_empty(): return {}
			if entered["result"]:
				if int(actor["phase"])==3 and states[int(actor["step"])]["face_end"] and not actor["target"].is_empty():
					var position: Array=services["target_position"].call(actor["target"].duplicate(true))
					var direction: Array=[]
					for i in range(3): direction.append(Terrain.f32(Terrain.f32(float(position[i]))-Terrain.f32(float(actor["position"][i]))))
					services["face"].call(direction)
				return {"result":false}
	# Native looping retries start at zero and ignore the entry helper's result.
	if not actor["failed"] and compiled["looping"]:
		var chosen := Sequence.choose(states,0,definition["action_sequences"]["rules"],services["random_word"],services["check"])
		if chosen.is_empty(): return {}
		var index := int(chosen["index"])
		if index>=0:
			actor["step"]=index
			var entered := enter(actor,index,compiled,definition,services)
			if entered.is_empty(): return {} # No out-of-row native-memory fallback.
			return {"result":false}
	actor["step"]=old
	if int(actor["phase"])!=int(rules["decision_phase"]) and actor["has_channel"]:
		var suppress := false
		if not actor["target"].is_empty() and References.validate(actor["target"],context,definition["target_reference_rules"]):
			var id := int(actor["target"]["entity"])
			if rules["house_actions"].any(func(value: Variant) -> bool: return int(value)==int(actor["action"])): suppress=int(context["houses"][str(id)]["state"])==0
			elif rules["temple_actions"].any(func(value: Variant) -> bool: return int(value)==int(actor["action"])): suppress=int(context["houses"][str(id)]["completion_state"])==int(rules["temple_state"])
		if not suppress: services["end_sound"].call(int(actor["voice"]))
	actor["phase"]=int(rules["decision_phase"])
	actor["native_slot"]=int(rules["native_slot"])
	services["request_decision"].call(actor)
	if not actor["cached_target"].is_empty() and not actor["target"].is_empty() and References.same_records(actor["cached_target"],actor["target"]):
		services["reset_navigation"].call()
		actor["path_time"]=0.0
		actor["gate_slot"]=int(rules["native_slot"])
		actor["cached_target"]={}
		actor["target"]=References.initial(definition["target_reference_rules"])
		actor["failed"]=true
	return {"result":true}


static func restore(saved: Variant) -> Dictionary:
	if not saved is Dictionary or not valid_actor(saved): return {}
	var actor := Entry.restore(saved)
	for key: String in ["action","phase","voice","profile","native_slot","gate_slot"]: actor[key]=int(actor[key])
	actor["path_time"]=Terrain.f32(float(actor["path_time"]))
	for i in range(3): actor["position"][i]=Terrain.f32(float(actor["position"][i]))
	for key: String in ["target","cached_target"]:
		if not actor[key].is_empty(): actor[key]=References.restore(actor[key])
	return actor
