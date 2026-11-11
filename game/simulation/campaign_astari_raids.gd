extends RefCounted
## Homeworld6's original raid timer, settlement search and archer actions.

const Finger = preload("res://simulation/campaign_finger.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const KIND := "astari_archer"
const TICK_SECONDS := 0.1


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get("astari_raids",{})


static func raid_state(state: Dictionary) -> Dictionary:
	var opening: Dictionary=state["opening"]
	if not opening.has("astari_raid"):
		opening["astari_raid"]={"origin":"","remaining":0,"next_poll":0,"festival_due":[],"notice":{},"shots":[],"reactions":{},"casualties":[]}
		state["enemies"]=[]
	return opening["astari_raid"]


static func shrine_repaired(state: Dictionary,site: String) -> void:
	if rules_for(state).get("origins",{}).has(site):
		raid_state(state)["origin"]=site


static func recover_origin(state: Dictionary) -> void:
	# Saves predating the raid timer have only the repaired flags. Recover the
	# furthest repaired authored beacon when its actual repair order is absent.
	for beacon: String in rules_for(state).get("origins",{}):
		for site: Dictionary in state["progression"]["shrines"]:
			if site["id"]==beacon and (site.get("repaired",false) or site["complete"]):
				shrine_repaired(state,beacon)
				break


static func prepare_load(state: Dictionary) -> void:
	var raid: Dictionary=state["opening"].get("astari_raid",{})
	if raid.is_empty(): return
	raid["festival_due"].clear()
	raid["notice"].clear()
	if raid["remaining"]>0: raid["next_poll"]=int(state["tick"])+1


static func nearest_settlement(state: Dictionary,origin: Vector2,rules: Dictionary) -> Dictionary:
	for radius: float in rules["radii"]:
		var best: Dictionary={}
		var nearest:=radius*radius
		for home: Dictionary in state["homes"]:
			if not home.get("settlement_core",false) or home.get("allegiance",0)!=0: continue
			var distance:=origin.distance_squared_to(point(home))
			if distance>nearest or distance==nearest and not best.is_empty(): continue
			best=home
			nearest=distance
		if not best.is_empty(): return best
	return {}


static func launch(world: RefCounted,state: Dictionary,raid: Dictionary,rules: Dictionary,random: RandomNumberGenerator,events: Array) -> void:
	if state.get("astari_village",{}).get("captured",false) or state["opening"].get("ark_progress",{}).get("conquered",false): return
	var origin_values: Array=rules["origins"].get(raid["origin"],[0,0])
	var origin:=Vector2(origin_values[0],origin_values[1])
	var settlement:=nearest_settlement(state,origin,rules)
	if settlement.is_empty(): return
	var destination:=point(settlement)
	var max_health:=stat(world,rules,"MaxHealth")
	for index in range(int(rules["count"])):
		# Native order is spawn Z, spawn X, sex, goal Z, goal X.
		var z:=jitter(origin.y,rules,random)
		var x:=jitter(origin.x,rules,random)
		var female:=random.randi_range(0,int(rules["random_max"]))>int(rules["random_max"])/2
		if x<0 or z<0 or x>=state["width"] or z>=state["width"]: break
		var goal_z:=jitter(destination.y,rules,random)
		var goal_x:=jitter(destination.x,rules,random)
		state["enemies"].append({"id":state["next_id"],"kind":KIND,"race":"Astari","allegiance":1,"female":female,
			"x":x,"z":z,"goal":[goal_x,goal_z],"settlement":settlement["id"],"path":[],"rotation":0.0,
			"state":"idle","health":max_health,"max_health":max_health,"scale":stat(world,rules,"Scale"),
			"route_offset":[x-roundf(x),z-roundf(z)],
			"shot_stage":0,"target":0,"phase_time":0.0,"phase_elapsed":0.0,"shot_variant":"near","scout_until":0})
		state["next_id"]+=1
	raid["notice"]={"x":destination.x,"z":destination.y,"until":int(state["tick"])+ticks(rules["duration"])}
	events.append({"type":"campaign_astari_raid","id":settlement["id"],"x":destination.x,"z":destination.y})


static func jitter(origin: float,rules: Dictionary,random: RandomNumberGenerator) -> float:
	return Terrain.f32(origin+float(random.randi_range(0,int(rules["random_max"])))*float(rules["spread"])/float(rules["random_max"])-1.0)


static func advance(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,events: Array) -> void:
	var rules:=rules_for(state)
	if rules.is_empty(): return
	var opening: Dictionary=state["opening"]
	var progression: Dictionary=state["progression"]
	var raid: Dictionary=opening.get("astari_raid",{})
	var tick: int=state["tick"]
	if Finger.POWER in progression["powers"] and raid.get("remaining",0)==0:
		raid=raid_state(state)
		raid["remaining"]=int(rules["interval"])+1
		raid["next_poll"]=tick+ticks(rules["precision"])
		launch(world,state,raid,rules,random,events)
	if raid.is_empty() or raid["remaining"]==0: return
	if tick>=int(raid["next_poll"]):
		if raid["remaining"]==1:
			launch(world,state,raid,rules,random,events)
			raid["remaining"]=int(rules["interval"])+1
		else:
			raid["remaining"]-=int(rules["precision"])
		raid["next_poll"]=tick+ticks(rules["precision"])
	if Finger.CARD in progression["completed"] and events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_astari_festival_started" and event.get("tutorial",false)):
		raid["festival_due"].append(tick+ticks(rules["festival_delay"]))
	while not raid["festival_due"].is_empty() and tick>=int(raid["festival_due"][0]):
		raid["festival_due"].pop_front()
		launch(world,state,raid,rules,random,events)
	if tick>=int(raid["notice"].get("until",0)): raid["notice"].clear()
	update_reactions(raid,state["followers"],tick)
	if state["enemies"].is_empty() and raid["shots"].is_empty(): return
	var followers: Dictionary={}
	for follower: Dictionary in state["followers"]:
		if vulnerable(follower): followers[int(follower["id"])]=follower
	resolve_shots(world,state,raid,followers,rules,tick,events)
	var assignments: Dictionary={}
	for archer: Dictionary in state["enemies"]:
		var target: int=archer["target"]
		if target>0: assignments[target]=int(assignments.get(target,0))+1
	for archer: Dictionary in state["enemies"]:
		advance_archer(world,archer,followers,assignments,raid,rules,random,tick)


static func advance_archer(world: RefCounted,archer: Dictionary,followers: Dictionary,assignments: Dictionary,
		raid: Dictionary,rules: Dictionary,random: RandomNumberGenerator,tick: int) -> void:
	if archer.has("swamp_entered"): return
	var vision:=stat(world,rules,"Vision")*float(rules["vision_multiplier"])
	var target: Dictionary=followers.get(int(archer["target"]),{})
	var stage: int=archer["shot_stage"]
	var speed:=stat(world,rules,"AnimSpeedMult")
	if stage==0:
		var best:=0.0
		for follower: Dictionary in followers.values():
			if int(assignments.get(follower["id"],0))>=int(rules["follower_limit"]): continue
			var score:=target_score(world,archer,follower,vision,rules)
			if score<=best: continue
			target=follower
			best=score
		if target.is_empty():
			scout(world,archer,rules,random,tick)
			return
		archer["target"]=target["id"]
		assignments[target["id"]]=int(assignments.get(target["id"],0))+1
		archer["path"].clear()
		archer.erase("route_revision")
		var distance:=random.randf_range(rules["advance_range"][0],rules["advance_range"][1])
		var from:=point(archer)
		var toward:=from.move_toward(point(target),distance)
		archer["path"]=world._route(Vector2i(from.round()),Vector2i(toward.round()),-1,Rect2i(),int(rules["max_steps"]),ceili(rules["advance_range"][1])+1)
		archer["shot_stage"]=-1
		stage=-1
	if stage==-1:
		if target.is_empty() or target_score(world,archer,target,vision,rules)<=0:
			archer.merge({"shot_stage":0,"target":0,"state":"idle","path":[]},true)
			return
		if not archer["path"].is_empty() and world.route_step_valid(archer,int(rules["max_steps"])):
			move_archer(world,archer,rules)
			return
		archer["path"].clear()
		archer["shot_variant"]=shot_variant(world,archer,target,rules)
		start_stage(archer,1,rules,random)
		stage=1
	if not target.is_empty(): face(archer,point(target))
	var before: float=archer["phase_elapsed"]
	archer["phase_elapsed"]=before+TICK_SECONDS*(1.0 if stage==3 else speed)
	if stage==3 and (target.is_empty() or target_score(world,archer,target,vision,rules)<=0):
		start_stage(archer,6,rules,random)
		return
	if stage==4 and not target.is_empty():
		var trigger:=float(archer["phase_time"])*float(rules["fire_progress"])
		if before<trigger and float(archer["phase_elapsed"])>=trigger:
			fire(world,archer,target,raid,rules,random,tick)
	if float(archer["phase_elapsed"])<float(archer["phase_time"]): return
	if stage==6:
		archer.merge({"shot_stage":0,"target":0,"state":"idle","phase_elapsed":0.0},true)
	else:
		start_stage(archer,3 if stage==5 else stage+1,rules,random)


static func start_stage(archer: Dictionary,stage: int,rules: Dictionary,random: RandomNumberGenerator) -> void:
	var role: String=archer["shot_variant"]+"_"+str(stage)
	archer["state"]=role
	archer["shot_stage"]=stage
	archer["phase_elapsed"]=0.0
	archer["phase_time"]=random.randf_range(rules["aim_time"][0],rules["aim_time"][1]) if stage==3 else rules["shot_durations"][role]


static func shot_variant(world: RefCounted,archer: Dictionary,target: Dictionary,rules: Dictionary) -> String:
	var source:=point(archer)
	var destination:=point(target)
	var level: bool=world.source_raw_height_at(source.x,source.y)==world.source_raw_height_at(destination.x,destination.y)
	return "near" if level and source.distance_to(destination)<float(rules["near_distance"]) else "far"


static func scout(world: RefCounted,archer: Dictionary,rules: Dictionary,random: RandomNumberGenerator,tick: int) -> void:
	if archer["scout_until"]>0:
		if tick<int(archer["scout_until"]): return
		archer["scout_until"]=0
	var revision: Array=world.raid_route_revision()
	if not archer["path"].is_empty() and not world.route_step_valid(archer,int(rules["max_steps"])):
		archer["path"].clear()
		archer.erase("route_revision")
	if archer["path"].is_empty():
		if revision==archer.get("route_revision",[]): return
		archer["route_revision"]=revision
		if not archer.has("scout_point"):
			var distance:=random.randf_range(rules["scout_range"][0],rules["scout_range"][1])
			var offset:=Vector2.from_angle(random.randf_range(0,TAU))*distance
			archer["scout_point"]=[float(archer["goal"][0])+offset.x,float(archer["goal"][1])+offset.y]
		var goal:=Vector2(archer["scout_point"][0],archer["scout_point"][1])
		var route: Dictionary=world.raid_route(Vector2i(point(archer).round()),goal,int(archer["settlement"]),rules)
		if route.is_empty():
			archer["state"]="idle"
			return
		archer["path"]=route["path"]
	move_archer(world,archer,rules)
	if archer["path"].is_empty():
		archer["state"]="idle"
		archer["scout_until"]=tick+ticks(random.randf_range(rules["scout_wait"][0],rules["scout_wait"][1]))


static func move_archer(world: RefCounted,archer: Dictionary,rules: Dictionary) -> void:
	var offset:=Vector2(archer["route_offset"][0],archer["route_offset"][1])
	world.advance_agent_path(archer,false,stat(world,rules,"RouteSpeed")*float(rules["speed_multiplier"]),offset)


static func target_score(world: RefCounted,archer: Dictionary,target: Dictionary,vision: float,rules: Dictionary) -> float:
	var source:=point(archer)
	var destination:=point(target)
	var range_limit:=vision+float(rules["follower_radius"])*float(target.get("scale",1))
	var distance:=source.distance_squared_to(destination)
	var height_weight: float=rules["stats"]["StepHeightDistanceMult"]
	if distance>=range_limit*range_limit+63*height_weight: return 0.0
	var steps: int=world.source_raw_height_at(source.x,source.y)-world.source_raw_height_at(destination.x,destination.y)
	distance=maxf(0.0,distance+float(steps)*height_weight)
	return maxf(0.0,1.0-sqrt(distance)/range_limit)*float(rules["follower_priority"])


static func fire(world: RefCounted,archer: Dictionary,target: Dictionary,raid: Dictionary,rules: Dictionary,random: RandomNumberGenerator,tick: int) -> void:
	var damage:=float(rules["damage"])*stat(world,rules,"Strength")*random.randf_range(rules["damage_min"],rules["damage_max"])
	var hit:=random.randf()<stat(world,rules,"JobSkill")
	if not hit: return
	var distance:=point(archer).distance_to(point(target))
	raid["shots"].append({"target":target["id"],"source":[archer["x"],archer["z"]],
		"damage":damage,"due":tick+ticks(distance*float(rules["flight_per_unit"]))})


static func resolve_shots(world: RefCounted,state: Dictionary,raid: Dictionary,followers: Dictionary,rules: Dictionary,tick: int,events: Array) -> void:
	for shot: Dictionary in raid["shots"].duplicate():
		if tick<int(shot["due"]): continue
		raid["shots"].erase(shot)
		var id: int=shot["target"]
		var target: Dictionary=followers.get(id,{})
		if target.is_empty(): continue
		var incoming:=Vector2(shot["source"][0],shot["source"][1])-point(target)
		var heading:=Vector2(0,-1).rotated(-deg_to_rad(float(target.get("rotation",0.0))))
		var side: String="front" if incoming.dot(heading)>=0 else "rear"
		target["health"]=maxf(0,float(target.get("health",100))-float(shot["damage"]))
		var fatal: bool=target["health"]<=0
		var clips: Array=rules["hit_reactions"][side]
		var duration:=0.0
		for clip: String in clips.slice(0,clips.size()-1): duration+=float(rules["hit_durations"][clip])
		raid["reactions"][str(id)]={"start":tick,"until":tick+ticks(rules["death_time"] if fatal else duration),"side":side,"fatal":fatal}
		events.append({"type":"campaign_astari_arrow_hit","id":id,"health":target["health"]})
		if fatal:
			var casualty: Dictionary={"id":id,"x":target["x"],"z":target["z"],"state":"dying",
				"scale":target.get("scale",1),"profession":target.get("profession",""),"rotation":target.get("rotation",0.0),
				"race":target.get("race","Brown Head")}
			if target.has("female"): casualty["female"]=target["female"]
			raid["casualties"].append(casualty)
			followers.erase(id)
			world.remove_follower(target)
			if state["followers"].is_empty(): world.respawn_source_followers()
		else:
			target["arrow_stun_until"]=raid["reactions"][str(id)]["until"]


static func update_reactions(raid: Dictionary,followers: Array,tick: int) -> void:
	for id: String in raid["reactions"].keys():
		if tick<int(raid["reactions"][id]["until"]): continue
		if not raid["reactions"][id]["fatal"]:
			for follower: Dictionary in followers:
				if int(follower["id"])==int(id):
					follower.erase("arrow_stun_until")
					break
		raid["reactions"].erase(id)
		for casualty: Dictionary in raid["casualties"]:
			if str(int(casualty["id"]))!=id: continue
			raid["casualties"].erase(casualty)
			break


static func decorate_snapshot(result: Dictionary) -> void:
	var raid: Dictionary=result["opening"].get("astari_raid",{})
	if raid.is_empty(): return
	var rules:=rules_for(result)
	result["casualties"]=raid["casualties"]
	for agents: Array in [result["followers"],result["casualties"]]:
		for agent: Dictionary in agents:
			var reaction: Dictionary=raid["reactions"].get(str(int(agent["id"])),{})
			if reaction.is_empty() or agent["state"]=="indoors": continue
			var elapsed: float=(int(result["tick"])-int(reaction["start"]))*TICK_SECONDS
			var clips: Array=rules["hit_reactions"][reaction["side"]]
			if not reaction["fatal"]: clips=clips.slice(0,clips.size()-1)
			for clip: String in clips if not reaction["fatal"] else [clips.back()]:
				var duration: float=rules["hit_durations"][clip]
				if elapsed>=duration and clip!=clips.back() and not reaction["fatal"]:
					elapsed-=duration
					continue
				agent["arrow_animation"]=clip
				agent["arrow_elapsed"]=minf(elapsed,duration)
				break


static func vulnerable(follower: Dictionary) -> bool:
	return follower.get("allegiance",0)==0 and follower.get("health",100)>0 and follower["state"]!="indoors" and not follower.has("sacrifice_due") and not follower.has("ark_passenger")


static func stat(world: RefCounted,rules: Dictionary,key: String) -> float:
	return float(world.follower_values({"race":"Astari"}).get(key,rules["stats"][key]))


static func refresh_stats(world: RefCounted,state: Dictionary) -> void:
	var enemies: Array=state.get("enemies",[])
	if enemies.is_empty(): return
	var rules:=rules_for(state)
	var health:=stat(world,rules,"MaxHealth")
	var scale:=stat(world,rules,"Scale")
	for archer: Dictionary in enemies:
		archer["max_health"]=health
		archer["health"]=minf(archer["health"],health)
		archer["scale"]=scale


static func point(item: Dictionary) -> Vector2:
	return Vector2(item.get("anchor_x",item["x"]),item.get("anchor_z",item["z"]))


static func face(archer: Dictionary,destination: Vector2) -> void:
	var direction:=destination-point(archer)
	if direction.length_squared()>0.0001: archer["rotation"]=rad_to_deg(atan2(-direction.x,-direction.y))


static func ticks(seconds: float) -> int:
	return maxi(1,ceili(seconds/TICK_SECONDS))


static func valid_rules(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in ["interval","precision","festival_delay","duration","count","follower_limit","random_max","max_steps","nav_range"]:
		if not whole(value.get(key),1,100000): return false
	if int(value["interval"])%int(value["precision"])!=0 or value["count"]>20: return false
	for key: String in ["tip_height","spread","flight_per_unit","follower_radius","vision_multiplier","speed_multiplier",
		"damage","damage_min","damage_max","death_time","follower_priority","near_distance","fire_progress"]:
		if not number(value.get(key),0,100000): return false
	if value["fire_progress"]<=0 or value["fire_progress"]>=1 or value["damage_min"]>value["damage_max"]: return false
	for key: String in ["aim_time","advance_range","scout_range","scout_wait"]:
		if not pair(value.get(key),0,100): return false
		if value[key][0]>value[key][1]: return false
	if not value.get("radii") is Array or value["radii"].is_empty() or value["radii"].size()>10: return false
	for radius: Variant in value["radii"]:
		if not whole(radius,1,1024): return false
	if not value.get("origins") is Dictionary or value["origins"].is_empty(): return false
	for origin: Variant in value["origins"].values():
		if not pair(origin,0,1023): return false
	if not value.get("stats") is Dictionary: return false
	for key: String in ["MaxHealth","RouteSpeed","Vision","Strength","JobSkill","AnimSpeedMult","Scale","StepHeightDistanceMult"]:
		if not number(value["stats"].get(key),0.00001,100000): return false
	if not value.get("roster") is Array or value["roster"].size()!=2 or not value.get("parts") is Dictionary: return false
	for id: Variant in value["roster"]+value["parts"].values():
		if not id is String or not id.begins_with("follower.group.bin:"): return false
	if not value["parts"].has_all(["male_AstariMask","bow","bow_pull","arrow","arrow_front","arrow_rear"]): return false
	if not value.get("attachments") is Dictionary or not value.get("clips") is Dictionary or not value.get("shot_durations") is Dictionary: return false
	for key: String in ["bow","bow_pull","arrow"]:
		if not value["attachments"].get(key) is Array: return false
		for role: Variant in value["attachments"][key]:
			if not role is String or not value["clips"].has(role): return false
	for role: String in ["idle","walking"]:
		if not value["clips"].get(role) is String: return false
	for variant: String in ["near","far"]:
		for stage in range(1,7):
			var role:=variant+"_"+str(stage)
			if not value["clips"].get(role) is String or not number(value["shot_durations"].get(role),0.00001,100): return false
	if not value.get("hit_reactions") is Dictionary or not value.get("hit_durations") is Dictionary: return false
	for side: String in ["front","rear"]:
		var clips: Variant=value["hit_reactions"].get(side)
		if not clips is Array or clips.size()<2 or clips.size()>3: return false
		for clip: Variant in clips:
			if not clip is String or not number(value["hit_durations"].get(clip),0.00001,100): return false
	return value.get("tip") is String and value.get("alert") is String


static func valid_state(state: Dictionary,ids: Dictionary) -> bool:
	var opening: Dictionary=state["opening"]
	if not opening.has("astari_raid"): return not state.has("enemies")
	var rules:=rules_for(state)
	var raid: Variant=opening["astari_raid"]
	if rules.is_empty() or not raid is Dictionary: return false
	var width: int=state["width"]
	var tick: int=state["tick"]
	var next_id: int=state["next_id"]
	if not raid.get("origin") is String or not (raid["origin"].is_empty() or rules["origins"].has(raid["origin"])): return false
	if not whole(raid.get("remaining"),0,int(rules["interval"])+1) or not whole(raid.get("next_poll"),0,tick+ticks(rules["precision"])): return false
	if raid["remaining"]>0 and (int(raid["remaining"])-1)%int(rules["precision"])!=0: return false
	if not raid.get("notice") is Dictionary: return false
	var notice: Dictionary=raid["notice"]
	if not notice.is_empty() and (not valid_position(notice,width) or not whole(notice.get("until"),tick,tick+ticks(rules["duration"]))): return false
	if not raid.get("festival_due") is Array or raid["festival_due"].size()>1024: return false
	var previous:=tick
	for due: Variant in raid["festival_due"]:
		if not whole(due,previous,tick+ticks(rules["festival_delay"])): return false
		previous=int(due)
	if not raid.get("shots") is Array or raid["shots"].size()>4096: return false
	for shot: Variant in raid["shots"]:
		if not shot is Dictionary or not whole(shot.get("target"),1,next_id-1) or not pair(shot.get("source"),0,width): return false
		if not number(shot.get("damage"),0,1e12) or not whole(shot.get("due"),tick,tick+ticks(rules["nav_range"])): return false
	if not raid.get("reactions") is Dictionary or not raid.get("casualties") is Array or not state.get("enemies") is Array: return false
	if raid["reactions"].size()>4096 or raid["casualties"].size()>4096 or state["enemies"].size()>65536: return false
	for id: Variant in raid["reactions"]:
		if not id is String or not id.is_valid_int() or int(id)<=0 or int(id)>=next_id: return false
		var reaction: Variant=raid["reactions"][id]
		if not reaction is Dictionary or not reaction.get("side") in ["front","rear"] or not reaction.get("fatal") is bool: return false
		if not whole(reaction.get("start"),0,tick) or not whole(reaction.get("until"),tick,tick+ticks(rules["death_time"])): return false
	for follower: Dictionary in state["followers"]:
		if not follower.has("arrow_stun_until"): continue
		var reaction: Dictionary=raid["reactions"].get(str(int(follower["id"])),{})
		if reaction.is_empty() or reaction["fatal"] or follower["arrow_stun_until"]!=reaction["until"]: return false
	for casualty: Variant in raid["casualties"]:
		if not valid_actor(casualty,ids,width,next_id): return false
		if not raid["reactions"].get(str(int(casualty["id"])),{}).get("fatal",false): return false
	for archer: Variant in state["enemies"]:
		if not valid_actor(archer,ids,width,next_id): return false
		if archer.get("kind")!=KIND or archer.get("race")!="Astari" or archer.get("allegiance")!=1 or not archer.get("female") is bool: return false
		if not pair(archer.get("goal"),-1,width+1) or not whole(archer.get("settlement"),1,next_id-1): return false
		if not whole(archer.get("shot_stage"),-1,6) or not whole(archer.get("target"),0,next_id-1): return false
		if not pair(archer.get("route_offset"),-0.5,0.5): return false
		if archer.has("scout_point") and not pair(archer["scout_point"],-101,width+101): return false
		if not archer.get("shot_variant") in ["near","far"] or not rules["clips"].has(archer["state"]): return false
		if not number(archer.get("health"),0,1e6) or not number(archer.get("max_health"),0,1e6) or archer["health"]>archer["max_health"]: return false
		if not number(archer.get("scale"),0,1e6) or not number(archer.get("rotation"),-360,360): return false
		if not number(archer.get("phase_time"),0,100) or not number(archer.get("phase_elapsed"),0,100): return false
		if not whole(archer.get("scout_until"),0,tick+ticks(rules["scout_wait"][1])): return false
		if archer.has("route_revision") and not pair(archer["route_revision"],0,1e12): return false
		if not archer.get("path") is Array or archer["path"].size()>width*width: return false
		for cell: Variant in archer["path"]:
			if not whole(cell,0,width*width-1): return false
	return true


static func valid_actor(actor: Variant,ids: Dictionary,width: int,next_id: int) -> bool:
	if not actor is Dictionary or not valid_position(actor,width) or not actor.get("state") is String: return false
	if not whole(actor.get("id"),1,next_id-1) or ids.has(int(actor["id"])): return false
	ids[int(actor["id"])]=true
	return true


static func valid_position(item: Dictionary,width: int) -> bool:
	return number(item.get("x"),0,width) and number(item.get("z"),0,width) and item["x"]<width and item["z"]<width


static func pair(value: Variant,low: float,high: float) -> bool:
	return value is Array and value.size()==2 and number(value[0],low,high) and number(value[1],low,high)


static func whole(value: Variant,low: int,high: int) -> bool:
	return number(value,low,high) and int(value)==value


static func number(value: Variant,low: float,high: float) -> bool:
	return (value is float or value is int) and is_finite(value) and value>=low and value<=high
