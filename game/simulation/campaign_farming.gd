extends RefCounted
## Source settlement compression and the first authored farming job.

const Economy = preload("res://simulation/campaign_economy.gd")
const Conversion = preload("res://simulation/source_plot_conversion.gd")
const POWER := "GodPower_PlaceSettlement_2"
const BUILDER_POWER := "GodPower_PlaceSettlement_1"
const MINING_POWER := "GodPower_PlaceSettlement_3"


static func place_authored_fields(world: RefCounted,state: Dictionary) -> void:
	var opening: Dictionary=state["opening"]
	var fields: Array=opening["definition"].get("authored_fields",[])
	if fields.is_empty() or state["homes"].any(func(home: Dictionary) -> bool: return home.get("authored_field",false)): return
	var schedule:=preload("res://simulation/source_plot_schedule.gd")
	for spec: Dictionary in fields:
		var field:=spec.duplicate(true)
		var origin:=Vector2i(Vector2(field["x"],field["z"])-Vector2.ONE*floori(float(field["span"])*0.5))
		field.merge({"id":state["next_id"],"anchor_x":field["x"],"anchor_z":field["z"],"x":origin.x,"z":origin.y,
			"work_x":field["x"],"work_z":field["z"],"progress":field["build_ticks"],"builder":-1,"stored":0,"residents":0,
			"stalled":false,"script_abode_type":0,"harvest_accumulator":0.0,"direct_harvest":true,"authored_field":true},true)
		state["next_id"]+=1
		state["homes"].append(field)
		schedule.mark(state["source_plots"]["schedule"],origin.x,origin.y)
	world._spatial_revision+=1


static func field_count(state: Dictionary,kind: String="farm") -> int:
	var count:=0
	for home: Dictionary in state["homes"]:
		if home.get("kind")==kind and home.has("settlement_id") and not home.get("authored_field",false): count+=1
	return count


static func inspect_placement(world: RefCounted,state: Dictionary,command: Dictionary,power: String=POWER) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	var width: int=state["width"]
	if not integer(x,width) or not integer(z,width) or world.height_at(x,z)<=0 or not world.can_act_at(x,z): return reject
	if not world.plot_obstruction(x,z).is_empty() or state["props"].size()+2>4096: return reject
	var spec: Dictionary=Economy.configuration(state)["settlements"][power]
	var story: Dictionary=state["opening"]["definition"]
	var power_key: String={BUILDER_POWER:"builder_settlement",MINING_POWER:"mining_settlement"}.get(power,"")
	var radius_setting: String=story.get(power_key,{}).get("radius_setting","SettCompRadius1")
	var radius: float=state["progression"]["rules"]["economy_source"]["configuration"].get(radius_setting,spec["radius"])
	var center:=Vector2(x,z)
	for site: Dictionary in state["progression"]["shrines"]:
		if (world.source_land_expansion(site) or world.source_ark_site(site)) and world.source_shrine_bounds(site).has_point(Vector2i(x,z)): return reject
	var capacity:=0
	var members:=[]
	var entrance:=[]
	var distance:=INF
	for home: Dictionary in state["homes"]:
		var area:=Rect2i(home["x"],home["z"],home.get("span",2),home.get("span",2))
		var ready: bool=home.get("kind","")=="" and not home.has("settlement_id") and home["progress"]>=home["build_ticks"]
		var anchor:=Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]))
		var gap:=anchor.distance_to(center)
		if not ready or gap>radius or not world.can_act_at(anchor.x,anchor.y):
			if area.has_point(Vector2i(x,z)): return reject
			continue
		if capacity+int(home["capacity"])>int(spec["max_population"]): return reject
		members.append(home["id"])
		capacity+=int(home["capacity"])
		var work:=Vector2i(home["work_x"],home["work_z"])
		if gap<distance and work!=Vector2i(x,z) and (power!=MINING_POWER or world.height_at(work.x,work.y)>0 and not world._occupied(work.x,work.y)):
			distance=gap
			entrance=[home["work_x"],home["work_z"]]
	if entrance.is_empty(): return reject
	var cost: int=spec["cost"]
	return {"ok":state["belief"]>=cost,"cost":cost,"reason":"","members":members,"capacity":capacity,
		"specification":spec,"entrance":entrance,"x":int(x),"z":int(z)}


static func merge(world: RefCounted,state: Dictionary,plan: Dictionary) -> int:
	var core_key: String={"builder":"builder_core","farmer":"farming_core","miner":"mining_core"}[plan["specification"]["role"]]
	var spec: Dictionary=state["opening"]["definition"][core_key]
	var core_id: int=state["next_id"]
	state["next_id"]+=1
	var settlement_id: int=state["next_id"]
	var storage:=0
	var max_belief:=0
	var occupants:=0
	var sacrificed:=0
	var members: Array=plan["members"]
	var registry: Dictionary=state["source_plots"]
	var schedule:=preload("res://simulation/source_plot_schedule.gd")
	for home: Dictionary in state["homes"].duplicate():
		if not home["id"] in members: continue
		occupants+=int(home["residents"])
		sacrificed+=int(home.get("sacrificed_followers",0))
		storage+=int(home["stored"])
		max_belief+=int(home.get("max_belief",0))
		schedule.mark(registry["schedule"],home["x"],home["z"])
		state["homes"].erase(home)
	var work: Array=plan["entrance"]
	for follower: Dictionary in state["followers"]:
		for key: String in ["indoors_home","away_home","entering_home"]:
			if follower.get(key,-1) in members:
				follower[key]=core_id
				if key=="indoors_home":
					follower["x"]=float(work[0])
					follower["z"]=float(work[1])
				if key=="entering_home": follower["path"]=[]
	var core:={"id":core_id,"settlement_core":true,"x":plan["x"],"z":plan["z"],"anchor_x":plan["x"],"anchor_z":plan["z"],"span":spec["span"],
		"capacity":plan["capacity"],"residents":occupants,"stored":storage,"max_belief":max_belief,"min_belief":1,
		"progress":1,"build_ticks":1,"birth_ticks":spec["birth_ticks"],"breeder_count":spec["breeders"],
		"work_x":work[0],"work_z":work[1],"builder":-1,"stalled":false,"access_path":[],"script_abode_type":-1}
	if sacrificed>0: core["sacrificed_followers"]=sacrificed
	state["homes"].append(core)
	var placement:={"type":"use_power","x":plan["x"],"z":plan["z"]}
	var merged:=plan.duplicate(false)
	merged["members"]=[core_id]
	Economy.apply(state,placement,merged)
	world._spatial_revision+=1
	schedule.mark(registry["schedule"],plan["x"],plan["z"])
	return settlement_id


static func plan_field(world: RefCounted,state: Dictionary,settlement_id: int,plot_id: int=-1) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var item:=Economy.settlement(state,settlement_id)
	if not item.get("role") in ["farmer","miner"] or item["members"].size()!=1: return reject
	var mine: bool=item["role"]=="miner"
	var candidate:=preload("res://simulation/campaign_opening.gd").release_candidate(state,int(item["members"][0]))
	if candidate.is_empty() or not candidate["home"].get("settlement_core",false): return reject
	# The first two tutorial jobs must construct fields. After the lesson,
	# follow the source worker selector and reuse an existing field first.
	if plot_id<0 and (mine or state["opening"].get("superfast_step",-1)>=5):
		var existing:=Economy.plan_existing_plot(world,state,item,[candidate["follower"]])
		if not existing.is_empty():
			existing["home_id"]=candidate["home"]["id"]
			return existing
	var origin:=Vector2i(roundi(candidate["follower"]["x"]),roundi(candidate["follower"]["z"]))
	var registry: Dictionary=state["source_plots"]
	var center:=Vector2(item["x"],item["z"])
	var candidates: Array=registry["active"] if plot_id<0 else [plot_id]
	var best:={}
	var best_gap:=INF
	for id: int in candidates:
		if plot_id>=0 and not id in registry["active"]: break
		var plot: Dictionary=registry["slots"][id]
		var at:=Vector2(plot["x"],plot["z"])+Vector2.ONE*float(plot["size"])*0.5
		var gap:=at.distance_squared_to(center)
		if gap>=best_gap or gap>float(item["radius"])*float(item["radius"]) or not world.can_act_at(at.x,at.y): continue
		var row: Dictionary=world.source_house_for_plot(plot["x"],plot["z"],plot["size"],2 if mine else 1)
		if row.is_empty(): continue
		var rank:=int(str(row["id"]).get_slice("_",2))
		var spec: Dictionary=Economy.configuration(state)["plots"].get("%s:%d"%["mine" if mine else "farm",rank],{})
		if spec.is_empty(): continue
		var span: int=row["size"]
		var left:=Vector2i((at-Vector2.ONE*float(span)*0.5+Vector2.ONE*0.5).floor())
		var area:=Rect2i(left,Vector2i.ONE*span)
		if mine and area.has_point(origin): continue
		if state["progression"]["shrines"].any(func(site: Dictionary) -> bool:
			return (world.source_land_expansion(site) or world.source_ark_site(site)) and world.source_shrine_bounds(site).intersects(area)): continue
		var clear:=true
		for z in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				if world._occupied(x,z) or not world.plot_obstruction(x,z).is_empty(): clear=false
		if not clear: continue
		var route: Dictionary=world._promised_abode_approach(origin,area,{},true)
		if route.is_empty(): continue
		best_gap=gap
		best={"ok":true,"cost":0,"reason":"","plot":id,"field_spec":spec,"span":span,"index":row["index"],
			"rotation":plot.get("rotation",0.0),"x":left.x,"z":left.y,"anchor_x":at.x,"anchor_z":at.y,"route":route,
			"worker":candidate["follower"]["id"],"home_id":candidate["home"]["id"],"settlement":settlement_id}
	return best if not best.is_empty() else reject


static func staff_field(state: Dictionary,plan: Dictionary) -> void:
	var candidate:=preload("res://simulation/campaign_opening.gd").release_candidate(state,plan["home_id"])
	candidate["home"]["residents"]-=1
	var worker: Dictionary=plan["worker"]
	worker.erase("indoors_home")
	worker["away_home"]=plan["home_id"]
	Economy.staff_existing_plot(state,plan)


static func start_field(world: RefCounted,state: Dictionary,plan: Dictionary) -> int:
	if not Conversion.release_plot(state["source_plots"],plan["plot"],true,false): return -1
	var id: int=state["next_id"]
	state["next_id"]+=1
	var work: Vector2i=plan["route"]["target"]
	var field: Dictionary=plan["field_spec"].duplicate(true)
	field.merge({"id":id,"x":plan["x"],"z":plan["z"],"anchor_x":plan["anchor_x"],"anchor_z":plan["anchor_z"],"span":plan["span"],
		"source_index":plan["index"],"rotation":rad_to_deg(plan["rotation"]),"direct_harvest":field["kind"]=="farm",
		"script_abode_type":0,"settlement_id":plan["settlement"],"harvest_accumulator":0.0,"progress":0,
		"stored":0,"residents":0,"builder":plan["worker"],"work_x":work.x,"work_z":work.y,"stalled":false,"access_path":[]},true)
	state["homes"].append(field)
	var candidate:=preload("res://simulation/campaign_opening.gd").release_candidate(state,plan["home_id"])
	candidate["home"]["residents"]-=1
	var worker: Dictionary=candidate["follower"]
	worker.erase("indoors_home")
	var profession: String="miner" if field["kind"]=="mine" else "farmer"
	worker.merge({"away_home":plan["home_id"],"job":id,"workplace":id,"settlement_id":plan["settlement"],"profession":profession,
		"state":"walking","path":plan["route"]["path"],"work_x":work.x,"work_z":work.y},true)
	world._spatial_revision+=1
	return id


static func integer(value: Variant,width: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=0 and value<width and value==int(value)
