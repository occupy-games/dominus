extends RefCounted
## Authored arrival tutorial and Weyworld's special construction biomes.

const Biomes = preload("res://simulation/source_biomes.gd")
const Leash = preload("res://simulation/campaign_leash.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func rules(state: Dictionary) -> Dictionary:
	return state.get("progression",{}).get("rules",{}).get("weyworld",{})


static func production_counts(state: Dictionary) -> Dictionary:
	var counts:={"wheat":0,"ore":0}
	for home: Dictionary in state["homes"]:
		if not home.has("settlement_id") or home.has("awaiting_influence"): continue
		match home.get("kind",""):
			"farm": counts["wheat"]+=1
			"mine": counts["ore"]+=1
	return counts


static func initialize(world: RefCounted,state: Dictionary) -> void:
	if state.has("weyworld") or rules(state).is_empty(): return
	state["weyworld"]={"phase":0,"hints":[5801],"first_abode":-1}
	for home: Dictionary in state["homes"]:
		if home.get("kind")=="ark" and home["residents"]<home["capacity"]: first_leash(state)
	advance(world,state)


static func first_leash(state: Dictionary) -> void:
	var progress: Dictionary=state.get("weyworld",{})
	if progress.get("phase",-1)!=0: return
	progress["phase"]=1
	progress["hints"].erase(5801)


static func advance(world: RefCounted,state: Dictionary) -> void:
	var progress: Dictionary=state.get("weyworld",{})
	if progress.is_empty(): return
	var source:=rules(state)
	var hints: Array=progress["hints"]
	if progress["phase"]<=1:
		var first: Dictionary={}
		for home: Dictionary in state["homes"]:
			if home.get("kind","")!="": continue
			if first.is_empty() or progress["first_abode"]==home["id"]: first=home
			if progress["first_abode"]==home["id"]: break
		if first.is_empty():
			hints.erase(5802)
			progress["first_abode"]=-1
		else:
			progress["first_abode"]=first["id"]
			first_leash(state)
			if first["progress"]<first["build_ticks"]:
				if not 5802 in hints: hints.append(5802)
			else:
				hints.erase(5802)
				progress["phase"]=2
				if influenced(world,source["verdant"]): enter_late_tips(world,state)
	if progress["phase"]==2:
		if not 5803 in hints and influenced(world,source["verdant"]): hints.append(5803)
	elif progress["phase"]==3:
		var granite: bool=progress["wait_granite"] and influenced(world,source["granite"])
		var hallowed:=visible_hallowed(world,source)
		if granite:
			progress["wait_granite"]=false
			hints.append(5806)
		if progress["wait_hallowed"] and not hallowed.is_empty():
			progress["wait_hallowed"]=false
			progress["hallowed"]=hallowed
			if granite: progress["queue_hallowed"]=true
			else: hints.append(5805)
		if not progress["wait_granite"] and not progress["wait_hallowed"]: progress["phase"]=4


static func enter_late_tips(world: RefCounted,state: Dictionary) -> void:
	var progress: Dictionary=state["weyworld"]
	var source:=rules(state)
	progress["wait_hallowed"]=visible_hallowed(world,source).is_empty()
	progress["wait_granite"]=not influenced(world,source["granite"])
	progress["phase"]=3 if progress["wait_hallowed"] or progress["wait_granite"] else 4


static func acknowledge(world: RefCounted,state: Dictionary,id: int) -> void:
	var progress: Dictionary=state["weyworld"]
	progress["hints"].erase(id)
	if id==5803:
		progress["hints"].append(5804)
		enter_late_tips(world,state)
	elif id==5806 and progress.erase("queue_hallowed"):
		progress["hints"].append(5805)


static func visible_hallowed(world: RefCounted,source: Dictionary) -> Array:
	for point: Array in source["hallowed"]:
		if influenced(world,point): return point
	return []


static func influenced(world: RefCounted,point: Array) -> bool:
	return world.can_act_at(point[0],point[1])


static func presentation(state: Dictionary) -> Dictionary:
	var progress: Dictionary=state["weyworld"]
	var source:=rules(state)
	var result:={"definition":{"messages":source["messages"]},"messages":[],"camera_degrees":source["camera_degrees"]}
	if Unlocks.enabled(state["progression"],"Leash") or progress["phase"]==0:
		result["leash_controls"]=source["leash"]
		result["leash_homes"]=[]
		result["leash_followers"]={}
		for home: Dictionary in state["homes"]:
			if home.get("kind")=="ark" and home["residents"]>0: result["leash_homes"].append(home["id"])
		for follower: Dictionary in state["followers"]:
			if Leash.selectable(follower): result["leash_followers"][follower["id"]]=true
	for id: int in progress["hints"]:
		var point: Array=[]
		match id:
			5801,5802:
				for home: Dictionary in state["homes"]:
					if id==5801 and home.get("kind")=="ark" or id==5802 and home["id"]==progress["first_abode"]:
						point=[home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"])]
						break
			5803: point=source["verdant"]
			5804: point=source["rugged"]
			5805: point=progress["hallowed"]
			5806: point=source["granite"]
		var message:={"id":id,"callback":true if id>=5803 else null}
		if not point.is_empty():
			message["anchor"]={"kind":"plot","x":point[0],"z":point[1]}
			if point.size()>2: message["anchor"]["height"]=(float(point[2])-float(state["source_map"]["sea_level"]))*0.3
		result["messages"].append(message)
	return result


static func placement_reason(state: Dictionary,kind: String,x: float,z: float) -> String:
	var source:=rules(state)
	if source.is_empty() or not Unlocks.enabled(state["progression"],"HousesBiomeLocked"): return ""
	var biome:=biome_at(source,x,z)
	if kind=="farm" and biome!=1 or kind=="mine" and biome!=2 or kind=="home" and biome==3:
		return source["biome_messages"][kind]
	return ""


static func biome_at(source: Dictionary,x: float,z: float) -> int:
	var environment: Dictionary=source["environment"]
	return Biomes.biome_at(environment["biomes"],environment["configuration"],x,z)


static func house_spec(state: Dictionary,rank: int,x: int,z: int) -> Dictionary:
	var source:=rules(state)
	if source.is_empty(): return {}
	var abodes: Dictionary=source.get("abodes",{})
	var half:=float(abodes.get("0:%d"%rank,{}).get("span",0))*0.5
	var kind:=biome_at(source,x+half,z+half)
	var spec: Dictionary=abodes.get("%d:%d"%[kind,rank],{})
	if spec.is_empty() or not Unlocks.enabled(state["progression"],spec["unlock"]): return {}
	var result:=spec.duplicate(true)
	result["build_ticks"]=preload("res://simulation/campaign_economy.gd").build_ticks(state,spec)
	return result


static func highest_abode_rank(state: Dictionary,fallback: int) -> int:
	var result := fallback
	for spec: Dictionary in rules(state).get("abodes",{}).values():
		if int(spec["rank"])>result and Unlocks.enabled(state["progression"],spec["unlock"]): result=int(spec["rank"])
	return result


static func valid(state: Dictionary) -> bool:
	var data: Variant=state["weyworld"]
	var source:=rules(state)
	if not data is Dictionary or not source.get("messages") is Dictionary or not source.get("leash") is Dictionary or not Biomes.valid(source.get("environment")): return false
	if not Numbers.integer_between(data.get("phase"),0,4) or not Numbers.integer_between(data.get("first_abode"),-1,2147483647) or not data.get("hints") is Array or data["hints"].size()>6: return false
	for id: Variant in data["hints"]:
		if not Numbers.integer_between(id,5801,5806) or not source["messages"].has(str(int(id))): return false
	if int(data["phase"])==3 and (not data.get("wait_granite") is bool or not data.get("wait_hallowed") is bool): return false
	if 5805 in data["hints"] or data.get("queue_hallowed",false):
		if not data.get("hallowed") is Array or not data["hallowed"] in source.get("hallowed",[]): return false
	return true
