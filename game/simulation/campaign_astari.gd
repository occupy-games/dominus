extends RefCounted
## Homeworld6 village residency, festivals and allegiance transfer.

const Happiness = preload("res://simulation/happiness.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const TICK_SECONDS := 0.1


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get("astari_village",{})


static func homes(state: Dictionary) -> Array:
	return state.get("astari_village",{}).get("homes",[])


static func initialize(world: RefCounted,state: Dictionary) -> void:
	var rules:=rules_for(state)
	if rules.is_empty() or state.has("astari_village"): return
	var core: Dictionary=rules["village"]
	var inherited: bool=state["progression"].get("script_unlocks",{}).get("winAstari",false)
	var village: Dictionary={"homes":[],"performers":[],"immigrants":[],"next_festival":0,
		"ai_ready":ticks(core["ai_delay"]),"forced":false,"captured":false,"festival":{},"notice":{}}
	state["astari_village"]=village
	var compound:=make_home(state,core["x"],core["z"],core["width"],core["depth"],"village",int(core["residents"]))
	compound.merge({"settlement_core":true,"script_abode_type":-1,"name":core["title"]})
	village["homes"].append(compound)
	for spec: Dictionary in rules["houses"]:
		var home:=make_home(state,spec["x"],spec["z"],spec["span"],spec["span"],"",spec["residents"])
		home.merge(spec["building"],true)
		home["progress"]=home["build_ticks"]
		village["homes"].append(home)
	for spec: Dictionary in rules["fields"]:
		var home:=make_home(state,spec["x"],spec["z"],spec["span"],spec["span"],"farm",0)
		home.merge(spec["building"],true)
		home.merge({"authored_field":true,"direct_harvest":true,"harvest_accumulator":0.0,"progress":home["build_ticks"]},true)
		village["homes"].append(home)
	world._spatial_revision+=1
	if inherited:
		for home: Dictionary in village["homes"]: home["residents"]=0
		capture(world,state,village,[])
		return
	var prior: Dictionary=state["opening"].get("ark_progress",{})
	if prior.has("festival_until"):
		var forced: Dictionary=state["opening"]["definition"]["ark"]["festival"]
		village["forced"]=true
		village["festival"]={"start":maxi(0,int(prior["festival_until"])-ticks(forced["AstariFestivalLength"])),
			"until":prior["festival_until"]}
		mood(state).merge({"player":1.0,"astari":-1.0+float(rules["boost"])},true)
		prior.erase("festival_until")


static func make_home(state: Dictionary,x: int,z: int,span: int,depth: int,kind: String,residents: int) -> Dictionary:
	var id: int=state["next_id"]
	state["next_id"]+=1
	return {"id":id,"x":x-span/2,"z":z-depth/2,"span":span,"depth":depth,"anchor_x":x,"anchor_z":z,"work_x":x,"work_z":z,
		"kind":kind,"allegiance":1,"residents":residents,"capacity":maxi(1,residents),"progress":1,"build_ticks":1,
		"birth_ticks":1,"builder":-1,"stalled":false,"stored":0,"min_belief":0,"max_belief":0,"breed_locked":true,"village_structure":true}


static func force_festival(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,events: Array) -> bool:
	var village: Dictionary=state.get("astari_village",{})
	if village.is_empty() or village["captured"] or village["forced"]: return false
	var settings: Dictionary=state["opening"]["definition"]["ark"]["festival"]
	var values:=mood(state)
	values["player"]=float(settings["AdjustHappiness"])
	values["astari"]=float(settings["AdjustAstariHappiness"])
	village["forced"]=true
	if village["festival"].is_empty():
		start_festival(world,state,village,rules_for(state),random,events)
	else:
		village["festival"]["until"]=int(village["festival"]["start"])+ticks(settings["AstariFestivalLength"])
	return true


static func advance(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,events: Array) -> void:
	var village: Dictionary=state.get("astari_village",{})
	if village.is_empty(): return
	var tick: int=state["tick"]
	if village["captured"]: return
	var count:=population(state)
	var rules:=rules_for(state)
	if count==0:
		capture(world,state,village,events)
		return
	if not Unlocks.enabled(state["progression"],rules["unlock"]) and not village["forced"]: return
	var values:=mood(state)
	var settings: Dictionary=state["opening"]["definition"]["ark"]["festival"] if village["forced"] else {}
	var length: float=settings.get("AstariFestivalLength",rules["length"])
	var baseline: float=Happiness.initial(state["progression"]["rules"])["astari"]
	var population_adjustment:=float(rules["population_effect"])*(count-float(rules["population"]))/float(rules["population"])
	baseline-=clampf(population_adjustment,-float(rules["population_adjust_max"]),float(rules["population_adjust_max"]))
	var decay: float=-float(rules["decay"])*TICK_SECONDS/(length+float(rules["interval"]))
	values["astari"]=Terrain.f32(clampf(move_toward(float(values["astari"]),baseline,decay),-1,1))
	if village["festival"].is_empty():
		advance_return(world,village,rules)
		if tick>=int(village["next_festival"]) and tick>=int(village["ai_ready"]):
			start_festival(world,state,village,rules,random,events)
	elif tick>=int(village["festival"]["until"]):
		finish_festival(world,state,village,rules,random,events)
	else:
		advance_performers(world,state,village,rules,random)


static func start_festival(world: RefCounted,state: Dictionary,village: Dictionary,rules: Dictionary,
		random: RandomNumberGenerator,events: Array) -> void:
	var settings: Dictionary=state["opening"]["definition"]["ark"]["festival"] if village["forced"] else {}
	var tick: int=state["tick"]
	village["notice"].clear()
	village["festival"]={"start":tick,"until":tick+ticks(settings.get("AstariFestivalLength",rules["length"]))}
	var values:=mood(state)
	values["astari"]=Terrain.f32(clampf(float(values["astari"])+float(rules["boost"]),-1,1))
	var tutorial: bool=state["opening"]["persistent"].get("ShouldPlayFestivalTutorial",0)==1
	events.append({"type":"campaign_astari_festival_started","tutorial":tutorial})
	assign_performers(world,state,village,rules,random)


static func finish_festival(world: RefCounted,state: Dictionary,village: Dictionary,rules: Dictionary,
		random: RandomNumberGenerator,events: Array) -> void:
	var settings: Dictionary=state["opening"]["definition"]["ark"]["festival"] if village["forced"] else {}
	var values:=mood(state)
	var difference:=Terrain.f32(float(values["player"])-float(values["astari"]))
	var scale: float=rules["conversion_scale"]
	var budget: int
	var change: int
	if difference>0:
		budget=int(minf(difference*scale*float(settings.get("MaxFollowersToConvertPostFestival",rules["post_limit"])),
			float(settings.get("MaxFollowersToConvertOnFestivalCatchup",rules["catchup_limit"]))))
		change=join_player(world,state,village,rules,random,budget)
	elif difference<0:
		budget=int(-difference*scale*int(state["followers"].size()*float(rules["post_fraction"])))
		change=-join_astari(world,state,village,rules,budget)
	village["festival"].clear()
	village["next_festival"]=int(state["tick"])+ticks(rules["interval"])
	if change!=0:
		var key: String=("won" if change>0 else "lost")+("_singular" if absi(change)==1 else "_plural")
		village["notice"]={"text":rules["notices"][key]%absi(change)}
		state["progression"]["revision"]+=1
		events.append({"type":"campaign_autosave"})
	events.append({"type":"campaign_astari_festival_ended","converted":change})
	if population(state)==0: capture(world,state,village,events)
	else: send_performers_home(world,village,rules)


static func population(state: Dictionary) -> int:
	var count:=0
	for home: Dictionary in homes(state): count+=int(home["residents"])
	for enemy: Dictionary in state.get("enemies",[]):
		if enemy.get("kind")=="astari_archer" and enemy.get("health",0)>0: count+=1
	return count


static func join_player(world: RefCounted,state: Dictionary,village: Dictionary,rules: Dictionary,
		random: RandomNumberGenerator,budget: int) -> int:
	if budget<=0: return 0
	var center:=Vector2(rules["conversion_center"][0],rules["conversion_center"][1])
	var target:=nearest_house(state["homes"],center)
	if target.is_empty(): return 0
	var destination:=point(target)
	var count:=0
	var occupied: Array=village["homes"].filter(func(home: Dictionary) -> bool: return home["residents"]>0)
	occupied.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return destination.distance_squared_to(point(a))<destination.distance_squared_to(point(b)))
	for home: Dictionary in occupied:
		var exit:=exit_point(world,home,destination)
		if exit.x<0: continue
		var amount:=mini(budget-count,int(home["residents"]))
		for index in range(amount):
			var resident:=resident_at(world,village,home,exit,rules,random)
			home["residents"]-=1
			for key: String in ["home","dance_until","festival_goal","return_goal"]: resident.erase(key)
			resident.merge({"allegiance":0,"state":"idle","path":[],"job":-1,"wait":0},true)
			state["followers"].append(resident)
		count+=amount
		if count>=budget: break
	return count


static func join_astari(world: RefCounted,state: Dictionary,village: Dictionary,rules: Dictionary,budget: int) -> int:
	if budget<=0: return 0
	var destination: Dictionary=village["homes"][0]
	var center:=Vector2(rules["conversion_center"][0],rules["conversion_center"][1])
	var residents: Dictionary={}
	for follower: Dictionary in state["followers"]:
		var home_id: int=follower.get("indoors_home",-1)
		if home_id<0 or follower["state"]!="indoors" or follower.has("ark_passenger") or follower["id"] in state["opening"]["protected"]: continue
		if not residents.has(home_id): residents[home_id]=[]
		residents[home_id].append(follower)
	var occupied: Array=state["homes"].filter(func(home: Dictionary) -> bool:
		return residents.has(int(home["id"])) and not home.get("kind","") in ["ark","shrine"])
	occupied.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return center.distance_squared_to(point(a))<center.distance_squared_to(point(b)))
	var count:=0
	for home: Dictionary in occupied:
		for follower: Dictionary in residents[int(home["id"])]:
			village["immigrants"].append({"id":follower["id"],"home":destination["id"],"female":follower.get("female",false)})
			home["residents"]=maxi(0,int(home["residents"])-1)
			destination["residents"]+=1
			destination["capacity"]=maxi(destination["capacity"],destination["residents"])
			world.remove_follower(follower)
			count+=1
			if count>=budget: return count
	return count


static func capture(world: RefCounted,state: Dictionary,village: Dictionary,events: Array) -> void:
	village["captured"]=true
	village["festival"].clear()
	village["performers"].clear()
	var p: Dictionary=state["progression"]
	if not p.has("script_unlocks"): p["script_unlocks"]={}
	p["script_unlocks"]["winAstari"]=true
	p["script_unlocks"]["ConqueredAstariClaim"]=true
	for home: Dictionary in village["homes"]:
		home["allegiance"]=0
		if home["kind"]=="": home.erase("breed_locked")
		state["homes"].append(home)
		if state.has("source_plots"):
			var schedule: Dictionary=state["source_plots"]["schedule"]
			for x: int in [int(home["x"]),int(home["x"])+int(home["span"])-1]:
				for z: int in [int(home["z"]),int(home["z"])+int(home["depth"])-1]:
					preload("res://simulation/source_plot_schedule.gd").mark(schedule,x,z)
	village["homes"].clear()
	world._spatial_revision+=1
	world._plan_stamp=-1
	p["revision"]+=1
	events.append({"type":"campaign_astari_village_captured"})
	if not events.any(func(event: Dictionary) -> bool: return event["type"]=="campaign_autosave"):
		events.append({"type":"campaign_autosave"})


static func nearest_house(candidates: Array,center: Vector2) -> Dictionary:
	var result: Dictionary={}
	var nearest:=INF
	for home: Dictionary in candidates:
		if home.get("allegiance",0)!=0 or home.get("progress",0)<home.get("build_ticks",1) or home.get("kind","") in ["ark","shrine"]: continue
		var distance:=center.distance_squared_to(point(home))
		if distance>=nearest: continue
		result=home
		nearest=distance
	return result


static func assign_performers(world: RefCounted,state: Dictionary,village: Dictionary,rules: Dictionary,random: RandomNumberGenerator) -> void:
	var center:=Vector2(rules["festival_center"][0],rules["festival_center"][1])
	var reaction: Dictionary=rules["reaction"]
	var limit: int=reaction["limit"]
	var claimed: Dictionary={}
	for actor: Dictionary in village["performers"]:
		claimed[actor["home"]]=int(claimed.get(actor["home"],0))+1
		actor.erase("return_goal")
	for home: Dictionary in village["homes"]:
		if village["performers"].size()>=limit: break
		if point(home).distance_to(center)>float(reaction["radius"]) or home["residents"]<=0: continue
		var exit:=exit_point(world,home,center)
		if exit.x<0: continue
		var vacant:=int(home["residents"])-int(claimed.get(home["id"],0))
		for index in range(mini(vacant,limit-village["performers"].size())):
			var actor:=new_resident(world,exit,rules,random)
			restore_immigrant(village,home,actor)
			actor["home"]=home["id"]
			village["performers"].append(actor)
	var slots: int=reaction["initial_slots"]
	var spacing: float=reaction["spacing"]
	for index in range(village["performers"].size()):
		var actor: Dictionary=village["performers"][index]
		var ring:=index/slots+1
		var angle:=TAU*float(index%slots)/float(slots)
		var destination:=center+Vector2.from_angle(angle)*float(ring)*spacing/(2.0*sin(PI/float(slots)))
		actor["festival_goal"]=[destination.x,destination.y]
		actor["path"]=world._route(Vector2i(point(actor).round()),Vector2i(destination.round()),-1,Rect2i(),int(rules["max_steps"]),ceili(reaction["radius"]+reaction["resolve_radius"]))
		actor["state"]="walking" if not actor["path"].is_empty() else "idle"
		actor["dance_until"]=int(state["tick"])+ticks(random.randf_range(reaction["idle"][0],reaction["idle"][1]))


static func advance_performers(world: RefCounted,state: Dictionary,village: Dictionary,rules: Dictionary,random: RandomNumberGenerator) -> void:
	var tick: int=state["tick"]
	var reaction: Dictionary=rules["reaction"]
	var speed:=route_speed(world,rules)
	for actor: Dictionary in village["performers"]:
		if not actor["path"].is_empty():
			world.advance_agent_path(actor,false,speed)
			continue
		var target:=Vector2(actor["festival_goal"][0],actor["festival_goal"][1])
		var position:=point(actor)
		if position.distance_to(target)>1.0: continue
		if position.distance_squared_to(target)>0.001:
			position=position.move_toward(target,float(world.source_route_speed(speed,position))*TICK_SECONDS)
			actor["x"]=position.x
			actor["z"]=position.y
		if tick<int(actor["dance_until"]): continue
		var dance: bool=not str(actor["state"]).begins_with("dance") and random.randf()>=float(reaction["skip"])
		var length: Array=reaction["dance"] if dance else reaction["idle"]
		actor["state"]="dance"+str(random.randi_range(1,3)) if dance else "idle"
		actor["dance_until"]=tick+ticks(random.randf_range(length[0],length[1]))


static func send_performers_home(world: RefCounted,village: Dictionary,rules: Dictionary) -> void:
	var homes_by_id: Dictionary={}
	for home: Dictionary in village["homes"]: homes_by_id[int(home["id"])]=home
	for actor: Dictionary in village["performers"]:
		var start:=Vector2i(point(actor).round())
		var exit:=exit_point(world,homes_by_id[actor["home"]],point(actor))
		actor["path"]=world._route(start,exit,-1,Rect2i(),int(rules["max_steps"]),ceili(rules["reaction"]["radius"]+rules["reaction"]["resolve_radius"]))
		actor["state"]="walking" if not actor["path"].is_empty() else "idle"
		if start==exit or not actor["path"].is_empty(): actor["return_goal"]=[exit.x,exit.y]


static func advance_return(world: RefCounted,village: Dictionary,rules: Dictionary) -> void:
	if village["performers"].is_empty(): return
	var speed:=route_speed(world,rules)
	for actor: Dictionary in village["performers"].duplicate():
		if not actor.has("return_goal"): continue
		world.advance_agent_path(actor,false,speed)
		if actor["path"].is_empty():
			# The actor keeps its identity when it becomes an indoor resident again.
			village["immigrants"].append({"id":actor["id"],"home":actor["home"],"female":actor["female"]})
			village["performers"].erase(actor)


static func route_speed(world: RefCounted,rules: Dictionary) -> float:
	return float(world.follower_values({"race":"Astari"}).get("RouteSpeed",rules["actor_stats"]["RouteSpeed"]))


static func resident_at(world: RefCounted,village: Dictionary,home: Dictionary,exit: Vector2i,rules: Dictionary,random: RandomNumberGenerator) -> Dictionary:
	for actor: Dictionary in village["performers"]:
		if actor["home"]!=home["id"]: continue
		village["performers"].erase(actor)
		return actor
	var resident:=new_resident(world,exit,rules,random)
	restore_immigrant(village,home,resident)
	return resident


static func restore_immigrant(village: Dictionary,home: Dictionary,resident: Dictionary) -> void:
	for immigrant: Dictionary in village["immigrants"]:
		if immigrant["home"]!=home["id"]: continue
		village["immigrants"].erase(immigrant)
		resident.merge({"id":immigrant["id"],"female":immigrant["female"]},true)
		break


static func new_resident(world: RefCounted,exit: Vector2i,rules: Dictionary,random: RandomNumberGenerator) -> Dictionary:
	var offset: float=rules["reaction"]["spacing"]*0.5
	var actor: Dictionary=world._agent(float(exit.x)+random.randf_range(-offset,offset),float(exit.y)+random.randf_range(-offset,offset),false)
	var stats: Dictionary=world.follower_values({"race":"Astari"})
	var health: float=stats.get("MaxHealth",rules["actor_stats"]["MaxHealth"])
	actor.merge({"race":"Astari","allegiance":1,"female":random.randi_range(0,1)==1,"state":"idle",
		"health":health,"max_health":health,"scale":stats.get("Scale",rules["actor_stats"]["Scale"])},true)
	return actor


static func exit_point(world: RefCounted,home: Dictionary,target: Vector2) -> Vector2i:
	var area:=Rect2i(home["x"],home["z"],home["span"],home["depth"])
	var perimeter: Array[Vector2i]=[]
	for x in range(area.position.x,area.end.x):
		perimeter.append(Vector2i(x,area.position.y-1))
		perimeter.append(Vector2i(x,area.end.y))
	for z in range(area.position.y,area.end.y):
		perimeter.append(Vector2i(area.position.x-1,z))
		perimeter.append(Vector2i(area.end.x,z))
	var result:=Vector2i(-1,-1)
	var nearest:=INF
	for candidate: Vector2i in perimeter:
		if world.height_at(candidate.x,candidate.y)<=0 or world._occupied(candidate.x,candidate.y): continue
		var distance:=target.distance_squared_to(Vector2(candidate))
		if distance>=nearest: continue
		nearest=distance
		result=candidate
	return result


static func point(home: Dictionary) -> Vector2:
	return Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]))


static func mood(state: Dictionary) -> Dictionary:
	var p: Dictionary=state["progression"]
	if not p.has("happiness"): p["happiness"]=Happiness.initial(p["rules"])
	return p["happiness"]


static func ticks(seconds: float) -> int:
	return maxi(1,roundi(seconds/TICK_SECONDS))


static func valid_rules(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in ["population","length","interval","post_limit","catchup_limit"]:
		if not integer(value.get(key),1,100000): return false
	for key: String in ["boost","post_fraction","population_effect","population_adjust_max","conversion_scale"]:
		if not number(value.get(key),0,1): return false
	if not number(value.get("decay"),-100,0) or value.get("unlock")!="AstariFestivalsUnlock": return false
	if not integer(value.get("max_steps"),1,16): return false
	var core: Variant=value.get("village")
	if not core is Dictionary or not position(core,1024) or not integer(core.get("width"),1,16) or not integer(core.get("depth"),1,16): return false
	if not integer(core.get("residents"),1,int(value["population"])) or not integer(core.get("ai_delay"),1,10000) or not core.get("title") is String: return false
	if not core.get("levels") is Array or core["levels"].size()!=int(core["width"])*int(core["depth"]): return false
	for level: Variant in core["levels"]:
		if not integer(level,0,63): return false
	if not value.get("houses") is Array or value["houses"].size()!=4 or not value.get("fields") is Array or value["fields"].size()!=2: return false
	var population_sum: int=core["residents"]
	for home: Variant in value["houses"]+value["fields"]:
		if not home is Dictionary or not position(home,1024) or not integer(home.get("span"),1,16): return false
		if not home.get("building") is Dictionary or not home["building"].get("model_id") is String or not integer(home["building"].get("build_ticks"),1,100000): return false
		if not integer(home.get("residents",0),0,1000): return false
		population_sum+=int(home.get("residents",0))
	if population_sum!=int(value["population"]): return false
	for key: String in ["conversion_center","festival_center"]:
		if not pair(value.get(key),0,1023): return false
	var reaction: Variant=value.get("reaction")
	if not reaction is Dictionary or not integer(reaction.get("limit"),1,1000) or not integer(reaction.get("initial_slots"),2,128): return false
	if not number(reaction.get("radius"),1,100) or not number(reaction.get("resolve_radius"),0,100) or not number(reaction.get("spacing"),0.01,4) or not number(reaction.get("skip"),0,1): return false
	for key: String in ["dance","idle"]:
		if not pair(reaction.get(key),0,100) or reaction[key][0]>reaction[key][1]: return false
	if not value.get("actor_stats") is Dictionary: return false
	for key: String in ["MaxHealth","RouteSpeed","Scale","AnimSpeedMult"]:
		if not number(value["actor_stats"].get(key),0.001,1000): return false
	if not value.get("bodies") is Array or value["bodies"].size()!=2 or not value.get("mask") is String or not value.get("clips") is Dictionary: return false
	for model: Variant in value["bodies"]+[value["mask"]]:
		if not model is String or not model.begins_with("follower.group.bin:"): return false
	for key: String in ["idle","walking","dance1","dance2","dance3"]:
		if not value["clips"].get(key) is String: return false
	if not value.get("notices") is Dictionary: return false
	for key: String in ["start","won_singular","won_plural","lost_singular","lost_plural"]:
		if not value["notices"].get(key) is String: return false
	return true


static func valid_state(state: Dictionary,ids: Dictionary) -> bool:
	if not state.has("astari_village"): return true
	var rules:=rules_for(state)
	var village: Variant=state["astari_village"]
	var tick: int=state["tick"]
	var width: int=state["width"]
	var max_id:=int(state["next_id"])-1
	if rules.is_empty() or not village is Dictionary or not village.get("captured") is bool or not village.get("forced") is bool: return false
	if not integer(village.get("next_festival"),0,tick+ticks(rules["interval"])) or not integer(village.get("ai_ready"),0,tick+ticks(rules["village"]["ai_delay"])): return false
	if not village.get("festival") is Dictionary or not village.get("notice") is Dictionary: return false
	if not village["notice"].is_empty() and not village["notice"].get("text") is String: return false
	var festival: Dictionary=village["festival"]
	if not festival.is_empty() and (not integer(festival.get("start"),0,tick) or not integer(festival.get("until"),0,tick+ticks(rules["length"]))): return false
	for key: String in ["homes","immigrants","performers"]:
		if not village.get(key) is Array: return false
	if village["captured"]:
		return village["homes"].is_empty() and village["immigrants"].is_empty() and village["performers"].is_empty() and festival.is_empty()
	if village["homes"].size()!=7 or not village["homes"][0] is Dictionary or village["homes"][0].get("kind")!="village": return false
	if village["immigrants"].size()>65536 or village["performers"].size()>int(rules["reaction"]["limit"]): return false
	var homes_by_id: Dictionary={}
	for home: Variant in village["homes"]:
		if not home is Dictionary or not register_id(home,ids,max_id) or not position(home,width) or home.get("allegiance")!=1: return false
		if not integer(home.get("span"),1,16) or not integer(home.get("depth"),1,16) or not integer(home.get("capacity"),1,65536): return false
		if not integer(home.get("residents"),0,int(home["capacity"])): return false
		homes_by_id[int(home["id"])]=int(home["residents"])
	for resident: Variant in village["immigrants"]+village["performers"]:
		if not resident is Dictionary or not register_id(resident,ids,max_id) or not resident.get("female") is bool: return false
		if not integer(resident.get("home"),1,max_id) or int(homes_by_id.get(int(resident["home"]),0))<=0: return false
		homes_by_id[int(resident["home"])]-=1
	for actor: Dictionary in village["performers"]:
		if not position(actor,width) or not rules["clips"].has(actor.get("state")) or actor.get("allegiance")!=1 or actor.get("race")!="Astari": return false
		if not pair(actor.get("festival_goal"),0,width) or not integer(actor.get("dance_until"),0,tick+1000): return false
		if actor.has("return_goal") and not pair(actor["return_goal"],0,width): return false
		if not actor.get("path") is Array or actor["path"].size()>width*width: return false
		for cell: Variant in actor["path"]:
			if not integer(cell,0,width*width-1): return false
	return true


static func register_id(item: Dictionary,ids: Dictionary,max_id: int) -> bool:
	if not integer(item.get("id"),1,max_id) or ids.has(int(item["id"])): return false
	ids[int(item["id"])]=true
	return true


static func position(item: Dictionary,width: int) -> bool:
	return number(item.get("x"),0,width) and number(item.get("z"),0,width) and item["x"]<width and item["z"]<width


static func pair(value: Variant,low: float,high: float) -> bool:
	return value is Array and value.size()==2 and number(value[0],low,high) and number(value[1],low,high)


static func integer(value: Variant,low: int,high: int) -> bool:
	return number(value,low,high) and int(value)==value


static func number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high
