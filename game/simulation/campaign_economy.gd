extends RefCounted
## Settlement membership, specialized jobs, harvest transport and collection.

const POWERS := {"GodPower_PlaceSettlement_1":"Card_Settlement_Follower","GodPower_PlaceSettlement_2":"Card_Settlement_Farming","GodPower_PlaceSettlement_3":"Card_Settlement_Mine"}
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func configuration(state: Dictionary) -> Dictionary:
	return state.get("progression",{}).get("rules",{}).get("economy",{})


static func place_free_harvest(state: Dictionary, sites: Array) -> void:
	for site: Dictionary in sites:
		var plot := site.duplicate(true)
		var x := int(plot["anchor_x"])
		var z := int(plot["anchor_z"])
		var half := int(plot["span"])/2
		plot.merge({"id":state["next_id"],"x":x-half,"z":z-half,"progress":plot["build_ticks"],
			"stored":0,"residents":0,"builder":-1,"work_x":x,"work_z":z,"stalled":false,
			"access_path":[],"awaiting_influence":true,"harvest_accumulator":0})
		state["homes"].append(plot)
		state["next_id"]+=1


static func fill_free_harvest(state: Dictionary) -> void:
	for plot: Dictionary in state["homes"]:
		if not plot.get("awaiting_influence",false): continue
		if not preload("res://simulation/influence.gd").contains(state,plot["anchor_x"],plot["anchor_z"]): continue
		plot["harvest_accumulator"]=maxf(plot["harvest_accumulator"],plot["max_belief"])
		plot["awaiting_influence"]=false


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


static func plan_existing_plot(world: RefCounted,state: Dictionary,item: Dictionary,workers: Array) -> Dictionary:
	if item["role"]=="builder": return {}
	var kind := "farm" if item["role"]=="farmer" else "mine"
	var destination := delivery_point(state,item)
	var staffed := {}
	for agent: Dictionary in state["followers"]:
		if agent.has("workplace"): staffed[int(agent["workplace"])]=true
	for field: Dictionary in state["homes"]:
		if field.get("kind","")!=kind or field["progress"]<field["build_ticks"] or staffed.has(int(field["id"])): continue
		if field.get("settlement_id",item["id"])!=item["id"]: continue
		var center := Vector2(field.get("anchor_x",field["x"]),field.get("anchor_z",field["z"]))
		if center.distance_to(Vector2(item["x"],item["z"]))>float(item["radius"]) or not world.can_act_at(center.x,center.y): continue
		var plot := Rect2i(field["x"],field["z"],field["span"],field["span"])
		var approaches: Array[Vector2i]=[]
		for z in range(plot.position.y,plot.end.y): approaches.append_array([Vector2i(plot.position.x-1,z),Vector2i(plot.end.x,z)])
		for x in range(plot.position.x,plot.end.x): approaches.append_array([Vector2i(x,plot.position.y-1),Vector2i(x,plot.end.y)])
		for work: Vector2i in approaches:
			if world.height_at(work.x,work.y)<=0 or world._occupied(work.x,work.y): continue
			if not field.get("direct_harvest",false) and work!=destination and world._route(work,destination).is_empty(): continue
			for worker: Dictionary in workers:
				var start := Vector2i(roundi(worker["x"]),roundi(worker["z"]))
				var path: Array=world._route(start,work)
				if start==work or not path.is_empty():
					return {"ok":true,"cost":0,"reason":"","field":field,"worker":worker,"work":work,"path":path,"settlement":item}
	return {}


static func delivery_point(state: Dictionary,item: Dictionary) -> Vector2i:
	for home: Dictionary in state["homes"]:
		if int(home["id"]) in item["members"]: return Vector2i(home["work_x"],home["work_z"])
	return Vector2i(item["x"],item["z"])


static func staff_existing_plot(state: Dictionary,plan: Dictionary) -> void:
	var field: Dictionary=plan["field"]
	var worker: Dictionary=plan["worker"]
	var work: Vector2i=plan["work"]
	field.merge({"work_x":work.x,"work_z":work.y,"settlement_id":plan["settlement"]["id"]},true)
	worker.merge({"workplace":field["id"],"settlement_id":field["settlement_id"],
		"profession":plan["settlement"]["role"],"path":plan["path"],"state":"walking","carrying":0},true)
	state["progression"]["revision"]+=1


static func harvest_rate(state: Dictionary, field: Dictionary) -> float:
	var rate := float(field["harvest_rate"])
	var key := "%s:%d"%[field["kind"],int(field["rank"])]
	var modifiers: Dictionary = configuration(state).get("production_modifiers",{})
	for unlock: String in modifiers:
		if Unlocks.enabled(state["progression"],unlock): rate*=float(modifiers[unlock].get(key,1))
	return preload("res://simulation/campaign_god_seed.gd").harvest_rate(state,field,rate)


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


static func update_agent(world: RefCounted,state: Dictionary,agent: Dictionary,rain: Dictionary={}) -> bool:
	if not agent.has("workplace") or agent["job"]!=-1 or agent.has("leash_goal"): return false
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
	if returning: target=delivery_point(state,item)
	if Vector2(agent["x"],agent["z"]).distance_to(Vector2(target))<0.01:
		agent["path"]=[]
		if returning:
			var resource := "wheat" if field["kind"]=="farm" else "ore"
			item[resource]+=int(agent["carrying"])
			agent["carrying"]=0
			state["progression"]["revision"]+=1
			agent["state"]="idle"
		else:
			if field.has("awaiting_influence") and not world.can_act_at(field["anchor_x"],field["anchor_z"]):
				agent["state"]="waiting"
				return true
			agent["state"]="farming" if field["kind"]=="farm" else "mining"
			var multiplier:=preload("res://simulation/campaign_rain.gd").field_multiplier(field,rain)
			field["harvest_accumulator"]=float(field.get("harvest_accumulator",0))+harvest_rate(state,field)*0.1*multiplier
			if field.get("direct_harvest",false):
				field["harvest_accumulator"]=minf(float(field["max_belief"]),float(field["harvest_accumulator"]))
				return true
			if float(field["harvest_accumulator"])>=float(field["max_belief"]):
				agent["carrying"]=floori(field["harvest_accumulator"])
				field["harvest_accumulator"]-=int(agent["carrying"])
		return true
	if agent["path"].is_empty(): agent["path"]=world._route(origin,target)
	world.finish_promised_approach(agent,target)
	if agent["path"].is_empty(): agent["state"]="waiting"; return true
	var cell := int(agent["path"][0])
	var position:=Vector2(agent["x"],agent["z"])
	var base_speed:=float(world.follower_values(agent).get("RouteSpeed",world.runtime_value("follower_speed",1.3)))
	var next:=position.move_toward(Vector2(cell%int(state["width"]),cell/int(state["width"])),float(world.source_route_speed(base_speed,position))*0.1)
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
		if not home.get("kind","") in ["farm","mine"] or not settlement(state,int(home.get("settlement_id",-1))).is_empty(): continue
		if home.get("authored_field",false) or home.has("awaiting_influence"): home.erase("settlement_id")
		else: state["homes"].erase(home)


static func valid_world(state: Dictionary) -> bool:
	var homes := {}
	for home: Dictionary in state["homes"]: homes[int(home["id"])]=home
	for item: Dictionary in state["progression"].get("settlements",[]):
		if item["id"]<=0 or item["id"]>=state["next_id"] or item["radius"]<=0 or item["x"]>=state["width"] or item["z"]>=state["width"] or item["members"].is_empty(): return false
		for id: int in item["members"]:
			if not homes.has(id) or int(homes[id].get("settlement_id",-1))!=int(item["id"]): return false
	for home: Dictionary in state["homes"]:
		if not home.get("kind","") in ["farm","mine"]: continue
		if home.get("authored_field",false):
			if not state.has("opening") or home["kind"]!="farm" or home.get("direct_harvest")!=true: return false
			var harvest: Variant=home.get("harvest_accumulator")
			if not (harvest is int or harvest is float) or not is_finite(float(harvest)) or harvest<0 or harvest>home["max_belief"]: return false
			if not home.has("settlement_id"): continue
		if home.has("awaiting_influence"):
			if state["progression"]["rules"].get("registered_scope")!="initialworldsetup7" or not home["awaiting_influence"] is bool: return false
			for key: String in ["anchor_x","anchor_z"]:
				var anchor: Variant=home.get(key)
				if not (anchor is int or anchor is float) or not is_finite(float(anchor)) or anchor!=int(anchor) or anchor<0 or anchor>=state["width"]: return false
			var amount: Variant=home.get("harvest_accumulator",0)
			if not (amount is int or amount is float) or not is_finite(float(amount)) or amount<0 or amount>home["max_belief"]: return false
			if home["awaiting_influence"] and (amount!=0 or home.has("settlement_id")): return false
		if not home.has("awaiting_influence") or home.has("settlement_id"):
			var item := settlement(state,int(home.get("settlement_id",-1)))
			if item.is_empty() or item["role"]!=("farmer" if home["kind"]=="farm" else "miner"): return false
		for key: String in ["harvest_rate","harvest_accumulator"]:
			var value: Variant = home.get(key,0)
			if not (value is int or value is float) or not is_finite(float(value)) or value<0: return false
	for agent: Dictionary in state["followers"]:
		if not agent.has("workplace"): continue
		if not (agent["workplace"] is int or agent["workplace"] is float) or not homes.has(int(agent["workplace"])): return false
		var field: Dictionary=homes[int(agent["workplace"])]
		var item := settlement(state,int(agent.get("settlement_id",-1)))
		if item.is_empty() or not field.get("kind") in ["farm","mine"] or field.get("settlement_id")!=item["id"] or agent.get("profession")!=item["role"]: return false
		var carried: Variant = agent.get("carrying",0)
		if not (carried is int or carried is float) or not is_finite(float(carried)) or carried<0 or carried!=int(carried): return false
	return true
