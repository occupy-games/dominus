extends RefCounted
## Homeworld leashing. The release command pays and assigns every selected
## follower together after simulation has checked all routes and Builder slots.

const Unlocks = preload("res://simulation/source_unlocks.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
const Pit = preload("res://simulation/campaign_pit.gd")


static func enabled(state: Dictionary) -> bool:
	var opening: Dictionary=state.get("opening",{})
	return int(opening.get("leash_step",-1))>=2 and opening["definition"].has("leash_rules") and Unlocks.enabled(state["progression"],"Leash")


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	if not enabled(state): return reject
	var selected: Variant=command.get("followers")
	var home_id: Variant=command.get("home_id",-1)
	if not selected is Array or not integer(home_id,-1) or selected.size()>state["followers"].size(): return reject
	var remaining:={}
	for id: Variant in selected:
		if not integer(id,1) or remaining.has(int(id)): return reject
		remaining[int(id)]=true
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	if not coordinate(x,state["width"]) or not coordinate(z,state["width"]) or not world.can_act_at(x,z): return reject
	var destination:=Vector2(x,z)
	var cell:=Vector2i(destination.round())
	var pit:=Pit.target(world,state,cell)
	var rules: Dictionary=state["opening"]["definition"]["leash_rules"]
	var house_agent: Dictionary=Opening.release_candidate(state,int(home_id)) if home_id>=0 else {}
	if home_id>=0 and house_agent.is_empty(): return reject
	if pit.is_empty() and not house_agent.is_empty() and house_agent["home"].get("settlement_core",false) and preload("res://simulation/campaign_economy.gd").settlement(state,house_agent["home"]["settlement_id"]).get("role") in ["farmer","miner"]:
		if not selected.is_empty(): return reject
		var from:=Vector2(house_agent["follower"]["x"],house_agent["follower"]["z"])
		if from.distance_to(Vector2(x,z))>float(rules["max_length"]): return reject
		var plot: int=state["source_plots"]["owners"].get(str(floori(z)*int(state["width"])+floori(x)),-1)
		if plot<0: return reject
		var farming:=preload("res://simulation/campaign_farming.gd").plan_field(world,state,house_agent["home"]["settlement_id"],plot)
		var cost: int=rules["home_cost"]
		return {"ok":farming["ok"] and state["belief"]>=cost,"cost":cost,"reason":"","field_plan":farming}
	var agents: Array=[]
	for agent: Dictionary in state["followers"]:
		if not remaining.erase(int(agent["id"])): continue
		if agent["state"]=="indoors" or agent["job"]!=-1 or agent.has("entering_home") or agent.has("ark_boarding") or agent.get("seeking_plot",false) or agent.has("sacrifice_due"): return reject
		if not pit.is_empty() and agent.get("leash_sacrifice",false): return reject
		agents.append(agent)
	if not remaining.is_empty(): return reject
	if not house_agent.is_empty(): agents.append(house_agent["follower"])
	if agents.is_empty(): return reject
	var site: Dictionary={}
	var boarding:=false
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
	if pit.is_empty() and site.is_empty() and (world.height_at(cell.x,cell.y)<=0 or world._occupied(cell.x,cell.y)): return reject
	if boarding and world.source_ark_berths(site)<agents.size(): return reject
	var reserved:={}
	var assignments:=[]
	for agent: Dictionary in agents:
		var from:=Vector2(agent["x"],agent["z"])
		if from.distance_to(destination)>float(rules["max_length"]): return reject
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
			reserved[plan["target"]]=true
		else:
			var route: Array=world._route(origin,cell)
			if origin!=cell and route.is_empty(): return reject
			plan={"target":cell,"path":route}
		plan["id"]=int(agent["id"])
		assignments.append(plan)
	var cost: int=selected.size()*int(rules["follower_cost"])
	if not house_agent.is_empty(): cost+=int(rules["home_cost"])
	return {"ok":state["belief"]>=cost,"cost":cost,"reason":"","assignments":assignments,"home_id":int(home_id),
		"home_follower":house_agent.get("follower",{}).get("id",-1),"repair_site":"" if boarding else site.get("id",""),
		"boarding":site["id"] if boarding else "","sacrifice":not pit.is_empty(),
		"shortage":state["belief"]<cost}


static func apply(world: RefCounted,state: Dictionary,plan: Dictionary) -> void:
	if plan["home_id"]>=0:
		for home: Dictionary in state["homes"]:
			if home["id"]==plan["home_id"]: home["residents"]-=1; break
	var building_id := -1
	for assignment: Dictionary in plan["assignments"]:
		for agent: Dictionary in state["followers"]:
			if agent["id"]!=assignment["id"]: continue
			agent.erase("leash_sacrifice")
			if plan["sacrifice"]:
				for key: String in ["workplace","profession","settlement_id","carrying"]: agent.erase(key)
				agent["leash_sacrifice"]=true
			if agent["id"]==plan["home_follower"]:
				agent["away_home"]=plan["home_id"]
				agent.erase("indoors_home")
			if not plan["repair_site"].is_empty():
				agent.erase("leash_goal")
				if building_id!=-1: assignment["building_id"]=building_id
				world.assign_source_shrine(agent,assignment)
				building_id=agent["job"]
			else:
				var target: Vector2i=assignment["target"]
				if not plan.get("boarding","").is_empty(): agent["ark_boarding"]=plan["boarding"]
				agent["leash_goal"]=[target.x,target.y]
				agent["path"]=assignment["path"]
				agent["state"]="walking"
			break


static func advance_walks(world: RefCounted,state: Dictionary) -> void:
	for agent: Dictionary in state["followers"]:
		if not agent.has("leash_goal"): continue
		var goal: Array=agent["leash_goal"]
		var target:=Vector2i(goal[0],goal[1])
		var position:=Vector2(agent["x"],agent["z"])
		if position.distance_to(Vector2(target))<0.01:
			if agent.has("ark_boarding"):
				world.board_source_ark(agent["ark_boarding"],agent)
				continue
			agent.erase("leash_goal")
			agent["state"]="idle"
			continue
		if agent["path"].is_empty():
			var origin:=Vector2i(position.round())
			agent["path"]=Pit.route(world,state,world.source_shrine_site(),origin) if agent.get("leash_sacrifice",false) else world._route(origin,target)
		world.finish_promised_approach(agent,target)
		if not agent["path"].is_empty(): world._update_agent(agent,false)
		else: agent["state"]="waiting"


static func integer(value: Variant,minimum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=minimum and value<=2147483647 and value==int(value)


static func coordinate(value: Variant,width: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=0 and value<width
