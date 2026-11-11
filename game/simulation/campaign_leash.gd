extends RefCounted
## Campaign leashing. Site orders validate their routes and Builder slots.
## Ground orders retain their destination while the terrain is disconnected.

const Unlocks = preload("res://simulation/source_unlocks.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
const Pit = preload("res://simulation/campaign_pit.gd")


static func enabled(state: Dictionary) -> bool:
	return not rules_for(state).is_empty()


static func rules_for(state: Dictionary) -> Dictionary:
	var progression: Dictionary=state.get("progression",{})
	if progression.is_empty() or not Unlocks.enabled(progression,"Leash"): return {}
	var opening: Dictionary=state.get("opening",{})
	if not opening.is_empty():
		return opening["definition"].get("leash_rules",{}) if int(opening.get("leash_step",-1))>=2 else {}
	if not state.has("campaign") or state.has("voyage") or state.has("weyworld"): return {}
	var config: Dictionary=progression["rules"].get("economy_source",{}).get("configuration",{})
	for key: String in ["LeashFirstHoldTime","LeashMaxLength","LeashBeliefPerFollower","LeashBeliefPerHouse","LeashSize","LeashColour.x","LeashColour.y","LeashColour.z","LeashOpacity"]:
		var value: Variant=config.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<0: return {}
	return {"hold_seconds":config["LeashFirstHoldTime"],"max_length":config["LeashMaxLength"],
		"follower_cost":int(config["LeashBeliefPerFollower"]),"home_cost":int(config["LeashBeliefPerHouse"]),
		"leash_size":config["LeashSize"],"leash_color":[config["LeashColour.x"],config["LeashColour.y"],config["LeashColour.z"],config["LeashOpacity"]]}


static func selectable(agent: Dictionary) -> bool:
	return agent["state"]!="indoors" and agent["job"]==-1 and not agent.has("entering_home") and not agent.has("ark_boarding") and not agent.has("ark_passenger") and not agent.get("seeking_plot",false) and not agent.has("sacrifice_due")


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var rules := rules_for(state)
	if rules.is_empty(): return reject
	var authored := state.has("opening")
	var selected: Variant=command.get("followers")
	var home_id: Variant=command.get("home_id",-1)
	if not selected is Array or not integer(home_id,-1) or selected.size()>state["followers"].size(): return reject
	if home_id>=0 and not authored: return reject
	var remaining:={}
	for id: Variant in selected:
		if not integer(id,1) or remaining.has(int(id)): return reject
		remaining[int(id)]=true
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	if not coordinate(x,state["width"]) or not coordinate(z,state["width"]) or not world.can_act_at(x,z): return reject
	var destination:=Vector2(x,z)
	var cell:=Vector2i(destination.round())
	var pit:=Pit.target(world,state,cell) if authored else {}
	var house_agent: Dictionary=Opening.release_candidate(state,int(home_id)) if home_id>=0 else {}
	if home_id>=0 and house_agent.is_empty(): return reject
	if pit.is_empty() and not house_agent.is_empty() and house_agent["home"].get("settlement_core",false) and preload("res://simulation/campaign_economy.gd").settlement(state,house_agent["home"]["settlement_id"]).get("role") in ["farmer","miner"]:
		if not selected.is_empty(): return reject
		var plot: int=state["source_plots"]["owners"].get(str(floori(z)*int(state["width"])+floori(x)),-1)
		if plot<0: return reject
		var farming:=preload("res://simulation/campaign_farming.gd").plan_field(world,state,house_agent["home"]["settlement_id"],plot)
		var cost: int=rules["home_cost"]
		return {"ok":farming["ok"] and state["belief"]>=cost,"cost":cost,"reason":"","field_plan":farming}
	var agents: Array=[]
	for agent: Dictionary in state["followers"]:
		if not remaining.erase(int(agent["id"])): continue
		if not selectable(agent): return reject
		if not pit.is_empty() and agent.get("leash_sacrifice",false): return reject
		agents.append(agent)
	if not remaining.is_empty(): return reject
	if not house_agent.is_empty(): agents.append(house_agent["follower"])
	if agents.is_empty(): return reject
	var site: Dictionary={}
	var boarding:=false
	if authored:
		var dock: Dictionary=world.source_dock_site()
		for candidate: Dictionary in state["progression"]["shrines"]:
			if candidate["complete"] and world.source_ark_site(candidate) and world.source_shrine_bounds(candidate).has_point(cell):
				site=candidate
				boarding=true
				break
			if candidate["complete"] or candidate.get("repaired",false) or (candidate["id"]!=dock.get("id") and not world.source_land_expansion(candidate) and not world.source_ark_site(candidate)): continue
			if world.source_shrine_bounds(candidate).has_point(cell):
				site=candidate
				break
	var cost: int=selected.size()*int(rules["follower_cost"])
	if not house_agent.is_empty(): cost+=int(rules["home_cost"])
	var abode_id: int=-1
	var abode_area:=Rect2i()
	var abode_capacity:=0
	if pit.is_empty() and site.is_empty():
		var builders_only:=agents.all(func(agent: Dictionary) -> bool: return agent.get("profession","") in ["","builder"])
		var plots: Dictionary=state.get("source_plots",{})
		var plot_id: int=plots.get("owners",{}).get(str(floori(z)*int(state["width"])+floori(x)),-1)
		if builders_only and plot_id>=0 and plot_id in plots["active"]:
			var plot: Dictionary=plots["slots"][plot_id]
			if not world.promised_growth_plots().has(plot): return reject
			var abode: Dictionary=world.plan_promised_abode(plot,-1,agents)
			if abode.is_empty(): return reject
			var assignments: Array=agents.map(func(agent: Dictionary) -> Dictionary: return {"id":agent["id"]})
			return {"ok":state["belief"]>=cost,"cost":cost,"reason":"","shortage":state["belief"]<cost,
				"abode_plan":abode,"home_id":int(home_id),"home_follower":house_agent.get("follower",{}).get("id",-1),"assignments":assignments}
		if world.height_at(cell.x,cell.y)<=0: return reject
		if world._occupied(cell.x,cell.y):
			if not builders_only: return reject
			for home: Dictionary in state["homes"]:
				if not home.has("source_house") or home["progress"]>=home["build_ticks"]: continue
				var area:=Rect2i(home["x"],home["z"],home["span"],home["span"])
				if not area.has_point(cell): continue
				abode_id=home["id"]
				abode_area=area
				abode_capacity=home["build_capacity"]
				break
			if abode_id<0: return reject
	if boarding and world.source_ark_berths(site)<agents.size(): return reject
	var reserved:={}
	if abode_id>=0:
		var assigned:=0
		for agent: Dictionary in state["followers"]:
			if agent["job"]!=abode_id: continue
			assigned+=1
			reserved[Vector2i(agent["work_x"],agent["work_z"])]=true
		if assigned+agents.size()>abode_capacity: return reject
	var assignments:=[]
	var occupant: int=house_agent.get("follower",{}).get("id",-1)
	for agent: Dictionary in agents:
		var from:=Vector2(agent["x"],agent["z"])
		var origin:=Vector2i(from.round())
		var plan: Dictionary
		if not pit.is_empty():
			var target:=Vector2i(pit["x"],pit["z"])
			var path:=Pit.route(world,state,pit,origin)
			if target!=origin and path.is_empty(): return reject
			plan={"target":target,"path":path}
		elif not site.is_empty():
			plan=world.source_ark_boarding_plan(site,origin,reserved) if boarding else world.source_shrine_repair_plan(site,origin,reserved)
			if plan.is_empty(): return reject
			reserved[plan["target"]]=int(reserved.get(plan["target"],0))+1
		elif abode_id>=0:
			plan=world._promised_abode_approach(origin,abode_area,reserved,true)
			if plan.is_empty(): return reject
			reserved[plan["target"]]=true
		else:
			if agent["id"]!=occupant and redundant_ground_order(agent,"leash_goal",destination):
				cost-=int(rules["follower_cost"])
				continue
			var route: Array=world._route(origin,cell)
			plan={"target":cell,"path":route}
		plan["id"]=int(agent["id"])
		assignments.append(plan)
	if assignments.is_empty(): return reject
	return {"ok":state["belief"]>=cost,"cost":cost,"reason":"","assignments":assignments,"home_id":int(home_id),
		"home_follower":occupant,"repair_site":"" if boarding else site.get("id",""),
		"boarding":site["id"] if boarding else "","sacrifice":not pit.is_empty(),"abode_id":abode_id,
		"shortage":state["belief"]<cost}


static func apply(world: RefCounted,state: Dictionary,plan: Dictionary,drop: Vector2) -> void:
	if plan.has("abode_plan"):
		if not world.start_promised_abode(plan["abode_plan"]): return
		release_house_follower(state,plan)
		for route: Dictionary in plan["abode_plan"]["routes"]:
			var follower: Dictionary=route["follower"]
			follower.erase("leash_sacrifice")
			remember_drop(follower,drop)
		return
	release_house_follower(state,plan)
	var building_id := -1
	for assignment: Dictionary in plan["assignments"]:
		for agent: Dictionary in state["followers"]:
			if agent["id"]!=assignment["id"]: continue
			agent.erase("leash_sacrifice")
			if plan["sacrifice"]:
				for key: String in ["workplace","profession","settlement_id","carrying"]: agent.erase(key)
				agent["leash_sacrifice"]=true
			if not plan["repair_site"].is_empty():
				agent.erase("leash_goal")
				if building_id!=-1: assignment["building_id"]=building_id
				world.assign_source_shrine(agent,assignment)
				building_id=agent["job"]
			elif plan["abode_id"]>=0:
				var target: Vector2i=assignment["target"]
				agent.erase("leash_goal")
				agent.merge({"job":plan["abode_id"],"work_x":target.x,"work_z":target.y,"path":assignment["path"],"state":"walking"},true)
			else:
				var target: Vector2i=assignment["target"]
				if not plan.get("boarding","").is_empty(): agent["ark_boarding"]=plan["boarding"]
				agent["leash_goal"]=[target.x,target.y]
				agent["path"]=assignment["path"]
				agent["state"]="walking"
			remember_drop(agent,drop)
			break


static func remember_drop(agent: Dictionary,drop: Vector2) -> void:
	agent["leash_drop"]=[drop.x,drop.y,agent["job"]]


static func redundant_ground_order(agent: Dictionary,goal_key: String,drop: Vector2) -> bool:
	var goal: Array=agent.get(goal_key,[])
	if goal.is_empty(): return Vector2(agent["x"],agent["z"]).distance_to(drop)<0.01
	var previous: Array=agent.get("leash_drop",goal)
	return Vector2(previous[0],previous[1]).distance_to(drop)<0.01


static func pinned_destinations(followers: Array) -> Dictionary:
	var pins := {}
	for agent: Dictionary in followers:
		var goal: Array=agent.get("leash_goal",agent.get("weyworld_destination",[]))
		var drop: Array=agent.get("leash_drop",[])
		if not goal.is_empty():
			var point := goal if drop.is_empty() else drop
			pins[agent["id"]]=Vector2(point[0],point[1])
		elif not drop.is_empty() and agent["job"]!=-1 and agent["job"]==drop[2] and agent.has("work_x") and agent["state"]!="indoors":
			var work:=Vector2(agent["work_x"],agent["work_z"])
			if Vector2(agent["x"],agent["z"]).distance_to(work)>=0.05: pins[agent["id"]]=Vector2(drop[0],drop[1])
	return pins


static func release_house_follower(state: Dictionary,plan: Dictionary) -> void:
	if plan["home_id"]<0: return
	for home: Dictionary in state["homes"]:
		if home["id"]==plan["home_id"]: home["residents"]-=1; break
	for follower: Dictionary in state["followers"]:
		if follower["id"]!=plan["home_follower"]: continue
		follower["away_home"]=plan["home_id"]
		follower.erase("indoors_home")
		break


static func advance_walks(world: RefCounted,state: Dictionary) -> void:
	for agent: Dictionary in state["followers"]:
		if agent.has("leash_goal"): advance_walk(world,state,agent)


static func advance_walk(world: RefCounted,state: Dictionary,agent: Dictionary,goal_key: String="leash_goal") -> void:
	var goal: Array=agent[goal_key]
	var target:=Vector2i(goal[0],goal[1])
	var position:=Vector2(agent["x"],agent["z"])
	var destination:=Vector2(target)
	var sacrifice: bool=agent.get("leash_sacrifice",false)
	var drop: Array=agent.get("leash_drop",[])
	if not drop.is_empty() and not sacrifice and not agent.has("ark_boarding"):
		var point:=Vector2(drop[0],drop[1])
		if Vector2i(point.round())==target: destination=point
	if position.distance_to(destination)<0.01:
		agent.erase("leash_drop")
		if agent.has("ark_boarding"):
			world.board_source_ark(agent["ark_boarding"],agent)
			return
		agent.erase(goal_key)
		agent["path"]=[]
		agent["state"]="idle"
		return
	if not sacrifice and not agent["path"].is_empty() and not world.route_step_valid(agent,1): agent["path"]=[]
	var cell: int=target.y*int(state["width"])+target.x
	if agent["path"].is_empty():
		var origin:=Vector2i(position.round())
		agent["path"]=Pit.route(world,state,world.source_shrine_site(),origin) if sacrifice else world._route(origin,target)
		if sacrifice or agent.has("ark_boarding"):
			world.finish_promised_approach(agent,target)
		elif origin==target and world.height_at(target.x,target.y)>0 and not world._occupied(target.x,target.y):
			agent["path"].append(cell)
	if not agent["path"].is_empty():
		var offset := destination-Vector2(target) if agent["path"][0]==cell else Vector2.ZERO
		world.advance_agent_path(agent,false,0.0,offset)
	else: agent["state"]="waiting"


static func integer(value: Variant,minimum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=minimum and value<=2147483647 and value==int(value)


static func coordinate(value: Variant,width: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=0 and value<width
