extends RefCounted
## Original exposure, opening and lifetime rules. Explicit plain-data services
## own field queries, progression/reward dispatch and spatial/pool registration.
## Visual/audio services emit presentation intents; they cannot grant rewards.

const Core = preload("res://simulation/source_chest_constructor.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Placement = preload("res://simulation/source_chest_placement.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["open_seconds","disappear_seconds","mission_score","height_scale","exposure_margin","old_height_weight","ground_weight"]:
		if not Placement.finite(rules.get(key)) or float(rules[key])<0: return false
	for key: String in ["fallback_reward","bonus_reward","bonus_unlock"]:
		if not rules.get(key) is String or rules[key].is_empty(): return false
	return rules["height_scale"]>0 and Schedule.integer_between(rules.get("count_baseline"),0,1000000) and Schedule.integer_between(rules.get("open_animation"),0,1000000)


static func valid_chest(chest: Variant) -> bool:
	if not chest is Dictionary or not Schedule.integer_between(chest.get("handle"),0,65534) or not Schedule.integer_between(chest.get("source_id"),0,4294967295) or not Core.valid(chest.get("core")): return false
	var reward: Variant=chest.get("reward")
	return reward is String or Schedule.integer_between(reward,0,4294967295)


static func restore(saved: Variant) -> Dictionary:
	var failed := {"ok":false,"chests":[]}
	if not saved is Array or saved.size()>65535: return failed
	var handles := {}
	var result: Array=[]
	for value: Variant in saved:
		if not valid_chest(value) or handles.has(int(value["handle"])): return failed
		var chest: Dictionary=value.duplicate(true)
		chest["handle"]=int(chest["handle"])
		chest["source_id"]=int(chest["source_id"])
		if not chest["reward"] is String: chest["reward"]=int(chest["reward"])
		chest["core"]=Core.restore(chest["core"])
		handles[chest["handle"]]=true
		result.append(chest)
	return {"ok":true,"chests":result}


static func exposed(chest: Dictionary,rules: Dictionary,service: Callable) -> bool:
	if not valid_rules(rules) or not valid_chest(chest) or int(chest["core"]["source_slots"]["60"])!=0: return false
	var position: Array=chest["core"]["position"]
	var override: Variant=service.call("sculpt",int(chest["handle"]),[int(position[0]),int(position[1])])
	if not override is Dictionary or not override.get("active") is bool: return false
	var height := 0.0
	if override["active"]:
		if not Placement.finite(override.get("height")): return false
		height=Terrain.f32(float(override["height"]))*float(rules["height_scale"])
	else:
		var sampled: Variant=service.call("ground",int(chest["handle"]),[position[0],position[1]])
		if not Placement.finite(sampled): return false
		height=Terrain.f32(float(sampled))
	return height-float(rules["exposure_margin"])<float(position[2])


static func kind_bits(kind: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0,kind)
	return bytes.decode_float(0)


static func begin_open(chest: Dictionary,rules: Dictionary,service: Callable) -> bool:
	if not valid_rules(rules) or not valid_chest(chest): return false
	var slots: Dictionary=chest["core"]["source_slots"]
	var started := int(slots["60"])==0
	var handle := int(chest["handle"])
	if started:
		service.call("animation",handle,[int(rules["open_animation"])])
		service.call("open_notification",handle,chest["core"]["position"].duplicate(true))
		slots["60"]=1
		service.call("increment_opened",handle,[])
		if int(service.call("mission_mode",handle,[]))==3:
			var position: Array=chest["core"]["position"].duplicate(true)
			position.append(kind_bits(int(chest["core"]["kind"])))
			service.call("mission_score",handle,[int(Terrain.f32(float(rules["mission_score"]))),position])
	# The raw source entry resets elapsed even when opening already started.
	# The ordinary player command below rejects that repeated action first.
	slots["58"]=0.0
	return started


static func try_open(chest: Dictionary,rules: Dictionary,service: Callable) -> bool:
	if not valid_rules(rules) or not valid_chest(chest): return false
	var position: Array=chest["core"]["position"]
	if not service.call("influence",int(chest["handle"]),[int(position[0]),int(position[1]),false]): return false
	if int(chest["core"]["source_slots"]["60"])!=0 or not exposed(chest,rules,service): return false
	return begin_open(chest,rules,service)


static func grant(chest: Dictionary,rules: Dictionary,mode: int,service: Callable) -> void:
	var handle := int(chest["handle"])
	var source_id := int(chest["source_id"])
	service.call("opened_log",handle,[source_id,2])
	var reward: Variant=chest["reward"]
	if (reward is String and reward.is_empty()) or (not reward is String and int(reward)==0) or not service.call("reward_available",handle,[reward]): reward=rules["fallback_reward"]
	if mode==2:
		if not service.call("mode2_ready",handle,[]) or not service.call("mode2_available",handle,[]): return
		# Source builds format four diagnostic keys, then query the same
		# no-argument service. This is not four fabricated sticker grants.
		for index in range(4): service.call("mode2_prepare",handle,[])
		return
	var slots: Dictionary=chest["core"]["source_slots"]
	if mode==1 and (int(slots["a0"])&int(slots["a4"]))==4294967295: return
	var flags := 32 if service.call("reward_status",handle,[]) else 0
	service.call("grant",handle,[reward,source_id,flags])
	var previous: bool=service.call("unlocked",handle,[rules["bonus_unlock"]])
	service.call("unlock",handle,[rules["bonus_unlock"]])
	var eligible: bool=service.call("reward_type_a",handle,[reward])
	if not eligible: eligible=service.call("reward_type_b",handle,[reward])
	if eligible and previous:
		flags=32 if service.call("reward_status",handle,[]) else 0
		service.call("grant",handle,[rules["bonus_reward"],source_id,flags])
	service.call("finish_target",handle,[int(slots["a0"])])


static func advance(chests: Array,rules: Dictionary,delta: float,mode: int,authored_words: int,service: Callable) -> Dictionary:
	var empty := {"ok":false,"removed":[],"totals":{}}
	if not valid_rules(rules) or not Placement.finite(delta) or delta<0 or authored_words<0 or authored_words>1000000: return empty
	var handles := {}
	for chest: Variant in chests:
		if not valid_chest(chest) or handles.has(int(chest["handle"])): return empty
		handles[int(chest["handle"])]=true
	var closed := 0
	var visible := 0
	var stories := 0
	var removed: Array=[]
	for chest: Dictionary in chests.duplicate(false):
		var core: Dictionary=chest["core"]
		var slots: Dictionary=core["source_slots"]
		var position: Array=core["position"]
		var handle := int(chest["handle"])
		var sampled: Variant=service.call("ground",handle,[position[0],position[1]])
		if not Placement.finite(sampled): return empty
		var height := Terrain.f32(float(sampled))
		if float(core["base_height"])+float(rules["exposure_margin"])>=height and float(position[2])!=height:
			position[2]=Terrain.f32(float(position[2])*float(rules["old_height_weight"])+height*float(rules["ground_weight"]))
		var phase := int(slots["60"])
		if phase==0:
			closed+=1
			if service.call("influence",handle,[int(position[0]),int(position[1]),false]):
				visible+=1
				if int(core["kind"])==4: stories+=1
		elif phase==1:
			slots["58"]=Terrain.f32(float(slots["58"])+Terrain.f32(delta))
			if float(slots["58"])>Terrain.f32(float(rules["open_seconds"])):
				slots["60"]=2
				grant(chest,rules,mode,service)
		elif phase==2:
			slots["58"]=Terrain.f32(float(slots["58"])+Terrain.f32(delta))
			if float(slots["58"])-Terrain.f32(float(rules["open_seconds"]))>Terrain.f32(float(rules["disappear_seconds"])):
				service.call("destroy",handle,[])
				service.call("unregister",handle,[core["spatial"].duplicate(true)])
				core["registered"]=false
				chest["source_id"]=-1
				chests.erase(chest)
				removed.append(handle)
				service.call("release",handle,[])
	var base := authored_words+int(rules["count_baseline"])-closed
	return {"ok":true,"removed":removed,"totals":{"base":base,"visible":base+visible,"story":stories}}
