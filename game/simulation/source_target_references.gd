extends RefCounted
## Original house/plot target copy, validation, clear and worker bookkeeping.
## Other reference kinds and follower action/path execution remain separate.

const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["invalid_identity","home_action","settlement_action","conversion_profession","settlement_limit"]:
		if not Schedule.integer_between(rules.get(key),0,4294967295): return false
	var threshold: Variant=rules.get("plot_distance_squared")
	return (threshold is int or threshold is float) and is_finite(float(threshold)) and threshold>0 and threshold<1 and rules["settlement_limit"]>0 and rules["settlement_limit"]<=40


static func initial(rules: Dictionary) -> Dictionary:
	return {"identity":int(rules["invalid_identity"]),"entity":-1,"position":[-1.0,-1.0],"flag":true}


static func reset(reference: Dictionary,rules: Dictionary) -> void:
	reference.clear()
	reference.merge(initial(rules))


static func valid_shape(reference: Variant) -> bool:
	if not reference is Dictionary or not Schedule.integer_between(reference.get("identity"),0,4294967295) or not Schedule.integer_between(reference.get("entity"),-1,4095) or not reference.get("flag") is bool: return false
	if not reference.get("position") is Array or reference["position"].size()!=2: return false
	for value: Variant in reference["position"]:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return false
	return true


static func validate(reference: Dictionary,context: Dictionary,rules: Dictionary) -> bool:
	if not valid_rules(rules) or not valid_shape(reference): return false
	var kind := (int(reference["identity"])>>24)&31
	var entity := int(reference["entity"])
	if kind==1:
		var house: Dictionary=context.get("houses",{}).get(str(entity),{})
		if not house.is_empty() and int(house.get("identity",0))!=0 and int(house["identity"])==int(reference["identity"]): return true
	elif kind==7:
		var plot: Dictionary=context.get("plots",{}).get(str(entity),{})
		if not plot.is_empty() and int(plot.get("size",0))!=0:
			var half := float(int(plot["size"]))*0.5
			var x := Terrain.f32(Terrain.f32(float(plot["x"]))+half)
			var z := Terrain.f32(Terrain.f32(float(plot["z"]))+half)
			var dx := Terrain.f32(Terrain.f32(float(reference["position"][0]))-x)
			var dz := Terrain.f32(Terrain.f32(float(reference["position"][1]))-z)
			if Terrain.f32(dx*dx+dz*dz)<=float(rules["plot_distance_squared"]): return true
	else:
		# Unsupported kinds are unavailable; they are not generalized to a
		# replacement target. Invalid-kind validation itself changes no bytes.
		return false
	reset(reference,rules)
	return false


static func counters_initial() -> Dictionary:
	return {"houses":{},"plots":{},"settlements":{}}


static func same_records(first: Dictionary,second: Dictionary) -> bool:
	# 0x1016acd0 for distinct stored records (the cached-path and actor targets).
	# Pool identities replace native pointers; different kinds have distinct pools.
	if not valid_shape(first) or not valid_shape(second): return false
	var kind_a := (int(first["identity"])>>24)&31
	var kind_b := (int(second["identity"])>>24)&31
	if int(first["entity"])>=0 and kind_a==kind_b and int(first["entity"])==int(second["entity"]): return true
	var position: Array=first["position"]
	if (float(position[0])!=-1.0 or float(position[1])!=-1.0) and Terrain.f32(float(position[0]))==Terrain.f32(float(second["position"][0])) and Terrain.f32(float(position[1]))==Terrain.f32(float(second["position"][1])): return true
	return int(first["identity"])!=0 and int(first["identity"])==int(second["identity"])


static func valid_follower(follower: Dictionary) -> bool:
	# An empty follower represents the native null bookkeeping owner.
	return follower.is_empty() or Schedule.integer_between(follower.get("home"),-1,4095) and Schedule.integer_between(follower.get("settlement_index"),-1,39) and Schedule.integer_between(follower.get("profession"),0,255) and Schedule.integer_between(follower.get("owner"),0,7)


static func adjust(counters: Dictionary,group: String,id: int,delta: int,skill: float) -> void:
	var key := str(id)
	var row: Array=counters[group].get(key,[0,0,0.0]).duplicate()
	row[1]=(int(row[1])+delta)&0xffffffff
	row[2]=Terrain.f32(float(row[2])+float(delta)*Terrain.f32(skill))
	if int(row[0])==0 and int(row[1])==0 and float(row[2])==0.0: counters[group].erase(key)
	else: counters[group][key]=row


static func assign(target: Dictionary,incoming: Dictionary,follower: Dictionary,context: Dictionary,counters: Dictionary,rules: Dictionary,action: int,skill: Callable,local_owner: int) -> bool:
	if not valid_shape(incoming) or not valid_follower(follower) or not valid_counters(counters) or not skill.is_valid() or not valid_rules(rules): return false
	# Native assignment receives the new reference by value. Validating an
	# invalid new handle must not invalidate the old target or the input object.
	var candidate := restore(incoming)
	if not validate(candidate,context,rules): return false
	target.clear()
	target.merge(candidate)
	if follower.is_empty(): return true
	var contribution := Terrain.f32(float(skill.call()))
	var kind := (int(target["identity"])>>24)&31
	var entity := int(target["entity"])
	if kind==7:
		adjust(counters,"plots",entity,1,contribution)
		return true
	if int(follower["home"])==entity and action!=int(rules["home_action"]): follower["home"]=-1
	if int(follower["home"])!=entity: adjust(counters,"houses",entity,1,contribution)
	var house: Dictionary=context["houses"][str(entity)]
	var settlement := int(house.get("settlement_index",-1))
	if settlement>=0 and settlement<int(rules["settlement_limit"]):
		if int(follower["settlement_index"])==-1 and int(follower["home"])!=entity:
			var key := str(settlement)
			var totals: Array=counters["settlements"].get(key,[0,0]).duplicate()
			for i in range(2): totals[i]=(int(totals[i])+1)&0xffffffff
			counters["settlements"][key]=totals
		if action==int(rules["settlement_action"]): follower["settlement_index"]=settlement
	if int(follower["profession"])==int(rules["conversion_profession"]) and int(follower["owner"])==local_owner: house["profession"]=int(rules["conversion_profession"])
	return true


static func clear(target: Dictionary,follower: Dictionary,context: Dictionary,counters: Dictionary,rules: Dictionary,skill: Callable) -> bool:
	if not valid_shape(target) or not valid_follower(follower) or not valid_counters(counters) or not skill.is_valid() or not valid_rules(rules): return false
	if not validate(target,context,rules): return false
	if not follower.is_empty():
		var contribution := Terrain.f32(float(skill.call()))
		var kind := (int(target["identity"])>>24)&31
		var entity := int(target["entity"])
		if kind==7: adjust(counters,"plots",entity,-1,contribution)
		elif kind==1 and int(follower["home"])!=entity: adjust(counters,"houses",entity,-1,contribution)
	reset(target,rules)
	return true


static func valid_counters(counters: Variant) -> bool:
	if not counters is Dictionary: return false
	for group: String in ["houses","plots","settlements"]:
		if not counters.get(group) is Dictionary: return false
		var maximum := 4095 if group=="houses" else 1023 if group=="plots" else 39
		for key: Variant in counters[group]:
			if not key is String or not key.is_valid_int() or key!=str(int(key)) or not Schedule.integer_between(int(key),0,maximum): return false
			var row: Variant=counters[group][key]
			if not row is Array or row.size()!=(2 if group=="settlements" else 3): return false
			for i in range(2):
				if not Schedule.integer_between(row[i],0,4294967295): return false
			if group!="settlements" and (not (row[2] is int or row[2] is float) or not is_finite(float(row[2])) or absf(float(row[2]))>1000000000000): return false
	return true


static func restore(reference: Variant) -> Dictionary:
	if not valid_shape(reference): return {}
	return {"identity":int(reference["identity"]),"entity":int(reference["entity"]),"position":[Terrain.f32(float(reference["position"][0])),Terrain.f32(float(reference["position"][1]))],"flag":bool(reference["flag"])}


static func restore_counters(saved: Variant) -> Dictionary:
	if not valid_counters(saved): return {}
	var counters: Dictionary=saved.duplicate(true)
	for group: String in ["houses","plots","settlements"]:
		for row: Array in counters[group].values():
			for i in range(2): row[i]=int(row[i])
			if group!="settlements": row[2]=float(row[2])
	return counters
