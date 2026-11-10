extends RefCounted
## Settlement membership, specialized jobs, harvest transport and collection.

const POWERS := {"GodPower_PlaceSettlement_1":"Card_Settlement_Follower","GodPower_PlaceSettlement_2":"Card_Settlement_Farming","GodPower_PlaceSettlement_3":"Card_Settlement_Mine"}
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func configuration(state: Dictionary) -> Dictionary:
	return state.get("progression",{}).get("rules",{}).get("economy",{})


static func settlement(state: Dictionary,id: int) -> Dictionary:
	for item: Dictionary in state["progression"].get("settlements",[]):
		if int(item["id"])==id: return item
	return {}


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var reject := {"ok":false,"cost":0,"reason":""}
	var p: Dictionary = state["progression"]
	if command.get("type")=="collect_settlement":
		var item := settlement(state,int(command.get("id",-1)))
		if item.is_empty() or not world.can_act_at(item["x"],item["z"]): return reject
		var belief := 0
		var homes: Array = []
		for home: Dictionary in state["homes"]:
			if int(home["id"]) in item["members"] and world.can_act_at(home["x"],home["z"]) and int(home["stored"])>=int(home.get("min_belief",0)):
				belief+=int(home["stored"])
				homes.append(home["id"])
		return {"ok":belief+int(item["wheat"])+int(item["ore"])>0,"cost":0,"reason":"","settlement":item,"belief":belief,"homes":homes}
	var power: String = command.get("power","")
	var specification: Dictionary = configuration(state).get("settlements",{}).get(power,{})
	if specification.is_empty() or not power in p["powers"]: return reject
	if state["props"].size()+2>4096: return reject
	var origin := Vector2(float(command.get("x",-1)),float(command.get("z",-1)))
	var selected_id := -1
	var members: Array = []
	var capacity := 0
	for home: Dictionary in state["homes"]:
		if home.get("kind","")!="" or home.has("settlement_id") or home["progress"]<int(home.get("build_ticks",60)): continue
		if origin.x>=home["x"] and origin.x<home["x"]+int(home.get("span",2)) and origin.y>=home["z"] and origin.y<home["z"]+int(home.get("span",2)): selected_id=int(home["id"])
		var center := Vector2(home["x"],home["z"])+Vector2.ONE*(int(home.get("span",2))-1)*0.5
		if origin.distance_to(center)>float(specification["radius"]) or not world.can_act_at(center.x,center.y): continue
		if capacity+int(home.get("capacity",2))>int(specification["max_population"]): continue
		members.append(int(home["id"]))
		capacity+=int(home.get("capacity",2))
	if selected_id<0 or not selected_id in members: return reject
	return {"ok":int(state["belief"])>=int(specification["cost"]),"cost":int(specification["cost"]),"reason":"","members":members,"capacity":capacity,"specification":specification}


static func apply(state: Dictionary,command: Dictionary,plan: Dictionary) -> void:
	var p: Dictionary = state["progression"]
	if command["type"]=="collect_settlement":
		var item := settlement(state,int(command["id"]))
		for resource: String in ["wheat","ore"]:
			state[resource]=int(state.get(resource,0))+int(item[resource])
			item[resource]=0
		state["belief"]+=int(plan["belief"])
		state["collected"]+=int(plan["belief"])
		for home: Dictionary in state["homes"]:
			if int(home["id"]) in plan["homes"]: home["stored"]=0
		p["revision"]+=1
		return
	var id := int(state["next_id"])
	state["next_id"]+=1
	var spec: Dictionary = plan["specification"]
	var item := {"id":id,"x":int(command["x"]),"z":int(command["z"]),"role":spec["role"],"members":plan["members"].duplicate(),"capacity":plan["capacity"],"radius":spec["radius"],"wheat":0,"ore":0}
	if not p.has("settlements"): p["settlements"]=[]
	p["settlements"].append(item)
	for home: Dictionary in state["homes"]:
		if int(home["id"]) in item["members"]: home["settlement_id"]=id
	state["props"].append({"id":id,"x":item["x"],"z":item["z"],"turns":0,"model_id":spec["model_id"],"settlement_id":id})
	if spec.has("statue_id"):
		state["props"].append({"id":int(state["next_id"]),"x":item["x"],"z":item["z"],"turns":0,"model_id":spec["statue_id"],"settlement_id":id})
		state["next_id"]+=1
	p["revision"]+=1


static func plot_spec(state: Dictionary,command: Dictionary) -> Dictionary:
	var item := settlement(state,int(command.get("settlement_id",-1)))
	if item.is_empty() or not item["role"] in ["farmer","miner"]: return {}
	var x := int(command.get("x",-1))
	var z := int(command.get("z",-1))
	if Vector2(x,z).distance_to(Vector2(item["x"],item["z"]))>float(item["radius"]): return {}
	var kind := "farm" if item["role"]=="farmer" else "mine"
	var spec: Dictionary = configuration(state).get("plots",{}).get("%s:%d"%[kind,int(command.get("rank",1))],{}).duplicate(true)
	if spec.is_empty(): return {}
	spec["settlement_id"]=item["id"]
	return spec


static func worker_available(state: Dictionary,agent: Dictionary,item: Dictionary) -> bool:
	return agent["job"]==-1 and not agent.has("workplace") and agent["state"]!="worshipping" and Vector2(agent["x"],agent["z"]).distance_to(Vector2(item["x"],item["z"]))<=float(item["radius"])


static func harvest_rate(state: Dictionary, field: Dictionary) -> float:
	var rate := float(field["harvest_rate"])
	var key := "%s:%d"%[field["kind"],int(field["rank"])]
	var modifiers: Dictionary = configuration(state).get("production_modifiers",{})
	for unlock: String in modifiers:
		if Unlocks.enabled(state["progression"],unlock): rate*=float(modifiers[unlock].get(key,1))
	return rate


static func build_ticks(state: Dictionary, house: Dictionary) -> int:
	var ticks := float(house["build_ticks"])
	var modifiers: Dictionary = configuration(state).get("abode_modifiers",{})
	for unlock: String in modifiers:
		if Unlocks.enabled(state["progression"],unlock): ticks*=float(modifiers[unlock].get(str(house.get("rank",1)),1))
	return maxi(1,roundi(ticks))


static func spends_resource(state: Dictionary, resource: String) -> bool:
	var gate := "FoodSpending" if resource=="wheat" else "OreSpending"
	if not state["progression"]["rules"].get("source_unlocks",{}).has(gate): gate="Farming" if resource=="wheat" else "Mining"
	return Unlocks.enabled(state["progression"],gate)


static func update_agent(world: RefCounted,state: Dictionary,agent: Dictionary) -> bool:
	if not agent.has("workplace") or agent["job"]!=-1: return false
	var field := {}
	for home: Dictionary in state["homes"]:
		if int(home["id"])==int(agent["workplace"]): field=home; break
	var item := settlement(state,int(agent.get("settlement_id",-1)))
	if field.is_empty() or item.is_empty():
		agent.erase("workplace")
		agent.erase("profession")
		return false
	if field["progress"]<field["build_ticks"]: return false
	var origin := Vector2i(roundi(agent["x"]),roundi(agent["z"]))
	var returning := int(agent.get("carrying",0))>0
	var target := Vector2i(field["work_x"],field["work_z"])
	if returning:
		for home: Dictionary in state["homes"]:
			if int(home["id"]) in item["members"]:
				target=Vector2i(home["work_x"],home["work_z"])
				break
	if Vector2(agent["x"],agent["z"]).distance_to(Vector2(target))<0.01:
		agent["path"]=[]
		if returning:
			var resource := "wheat" if field["kind"]=="farm" else "ore"
			item[resource]+=int(agent["carrying"])
			agent["carrying"]=0
			state["progression"]["revision"]+=1
			agent["state"]="idle"
		else:
			agent["state"]="farming" if field["kind"]=="farm" else "mining"
			field["harvest_accumulator"]=float(field.get("harvest_accumulator",0))+harvest_rate(state,field)*0.1
			if float(field["harvest_accumulator"])>=float(field["max_belief"]):
				agent["carrying"]=floori(field["harvest_accumulator"])
				field["harvest_accumulator"]-=int(agent["carrying"])
		return true
	if agent["path"].is_empty(): agent["path"]=world._route(origin,target)
	if agent["path"].is_empty(): agent["state"]="waiting"; return true
	var cell := int(agent["path"][0])
	var next := Vector2(agent["x"],agent["z"]).move_toward(Vector2(cell%int(state["width"]),cell/int(state["width"])),float(world.follower_values(agent).get("RouteSpeed",world.runtime_value("follower_speed",1.3)))*0.1)
	agent["x"]=next.x
	agent["z"]=next.y
	agent["state"]="carrying" if returning else "walking"
	if next.distance_to(Vector2(cell%int(state["width"]),cell/int(state["width"])))<0.001: agent["path"].pop_front()
	return true


static func valid(p: Dictionary) -> bool:
	if not p.get("settlements",[]) is Array: return false
	var ids := {}
	var members := {}
	for item: Variant in p.get("settlements",[]):
		if not item is Dictionary or not item.get("role") in ["builder","farmer","miner"] or not item.get("members") is Array: return false
		for key: String in ["id","x","z","capacity","radius","wheat","ore"]:
			var value: Variant = item.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value!=int(value): return false
		if ids.has(int(item["id"])): return false
		ids[int(item["id"])]=true
		for id: Variant in item["members"]:
			if not (id is int or id is float) or id!=int(id) or members.has(int(id)): return false
			members[int(id)]=true
	return true


static func reconcile(state: Dictionary) -> void:
	var p: Dictionary = state["progression"]
	var homes := {}
	for home: Dictionary in state["homes"]: homes[int(home["id"])]=home
	for item: Dictionary in p.get("settlements",[]).duplicate():
		item["members"]=item["members"].filter(func(id: int) -> bool: return homes.has(id))
		item["capacity"]=0
		for id: int in item["members"]: item["capacity"]+=int(homes[id].get("capacity",2))
		if not item["members"].is_empty(): continue
		p["settlements"].erase(item)
		for prop: Dictionary in state["props"].duplicate():
			if prop.get("settlement_id",-1)==item["id"]: state["props"].erase(prop)
	for agent: Dictionary in state["followers"]:
		if not agent.has("workplace"): continue
		if homes.has(int(agent["workplace"])) and not settlement(state,int(agent["settlement_id"])).is_empty(): continue
		for key: String in ["workplace","profession","settlement_id","carrying"]: agent.erase(key)
		agent["job"]=-1
		agent["path"]=[]
		agent["state"]="idle"
	for home: Dictionary in state["homes"].duplicate():
		if home.get("kind","") in ["farm","mine"] and settlement(state,int(home.get("settlement_id",-1))).is_empty(): state["homes"].erase(home)


static func valid_world(state: Dictionary) -> bool:
	var homes := {}
	for home: Dictionary in state["homes"]: homes[int(home["id"])]=home
	for item: Dictionary in state["progression"].get("settlements",[]):
		if item["id"]<=0 or item["id"]>=state["next_id"] or item["radius"]<=0 or item["x"]>=state["width"] or item["z"]>=state["width"] or item["members"].is_empty(): return false
		for id: int in item["members"]:
			if not homes.has(id) or int(homes[id].get("settlement_id",-1))!=int(item["id"]): return false
	for home: Dictionary in state["homes"]:
		if not home.get("kind","") in ["farm","mine"]: continue
		if settlement(state,int(home.get("settlement_id",-1))).is_empty(): return false
		for key: String in ["harvest_rate","harvest_accumulator"]:
			var value: Variant = home.get(key,0)
			if not (value is int or value is float) or not is_finite(float(value)) or value<0: return false
	for agent: Dictionary in state["followers"]:
		if not agent.has("workplace"): continue
		if not (agent["workplace"] is int or agent["workplace"] is float) or not homes.has(int(agent["workplace"])): return false
		if not agent.get("profession","") in ["farmer","miner"] or settlement(state,int(agent.get("settlement_id",-1))).is_empty(): return false
		var carried: Variant = agent.get("carrying",0)
		if not (carried is int or carried is float) or not is_finite(float(carried)) or carried<0 or carried!=int(carried): return false
	return true
