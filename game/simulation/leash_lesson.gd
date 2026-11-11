extends RefCounted
## Fixed-tick mission 3, using the source spawns, terrain, objectives and copy.

const Progression = preload("res://simulation/progression.gd")
const Immutable = preload("res://simulation/immutable_data.gd")
const Leash = preload("res://simulation/campaign_leash.gd")

const INTRO := 0
const FIRST_FOLLOWER := 1
const BUILDER_SLOT := 4
const HOUSE_OCCUPANT := 5
const TEAMWORK := 8
const GROUP := 9
const REPAIR := 12
const RETURN := 13


static func setup(world: RefCounted, state: Dictionary, source: Dictionary) -> void:
	var definition:=source.duplicate()
	var raw: PackedByteArray=definition["terrain"]
	definition.erase("terrain")
	state["width"]=int(definition["width"])
	state["belief"]=int(definition["belief"])
	var terrain:=PackedByteArray()
	terrain.resize(raw.size())
	for cell in raw.size(): terrain[cell]=maxi(0,int(raw[cell])-19)
	state["terrain"]=terrain
	state["source_map"]={"sea_level":19,"height_sha256":definition["terrain_sha256"]}
	state["progression"]=Progression.initialize({"shrines":[],"objects":[],"chests":[],"cards":{},"followers":definition["follower_values"],
		"config":{"templeFixerFalloff":definition["temple_falloff"]}},terrain,state["width"])
	for record: Dictionary in definition["followers"]:
		var at: Array=record["position"]
		var agent: Dictionary=world._agent(at[0],at[1],false)
		agent["female"]=record["female"]
		agent["rotation"]=record["rotation"]
		state["followers"].append(agent)
	var initial_home:=add_building(world,state,definition["initial_home"],definition["occupied_home_span"],definition["home_model"],definition["build_ticks"],2,definition["home_capacity"])
	var target: Array=definition["target"]
	var entrance: Dictionary=world._promised_abode_approach(Vector2i(target[0],target[1]),footprint(definition["initial_home"],definition["occupied_home_span"]),{})
	if not entrance.is_empty():
		initial_home["work_x"]=entrance["target"].x
		initial_home["work_z"]=entrance["target"].y
	initial_home["progress"]=initial_home["build_ticks"]
	initial_home["residents"]=definition["home_capacity"]
	for index in range(int(initial_home["residents"])):
		var resident: Dictionary=world._agent(initial_home["work_x"],initial_home["work_z"],false)
		resident["state"]="indoors"
		resident["indoors_home"]=initial_home["id"]
		state["followers"].append(resident)
	var temple: Dictionary=definition["temple"]
	var anchor: Array=temple["position"]
	state["progression"]["shrines"].append({"id":temple["id"],"x":anchor[0],"z":anchor[1],"model_id":temple["model_id"],
		"rotation":temple["rotation"],"source_center":true,"source_height":temple["source_height"],
		"build_ticks":temple["build_ticks"],"started":false,"complete":false})
	var camera: Array=definition["camera"][0]
	state["camera_start"]={"x":camera[0],"z":camera[1]}
	state["leash_lesson"]={"definition":Immutable.freeze(definition),"stage":INTRO,"home_id":initial_home["id"],
		"first_id":state["followers"][0]["id"],"target_id":-1,"temple_id":-1,"first_release":-1,"prompt":{}}
	set_stage(state,INTRO,[])


static func footprint(position: Array,span: int) -> Rect2i:
	var center:=Vector2i(int(position[0]),int(position[1]))
	return Rect2i(center-Vector2i.ONE*(span/2),Vector2i.ONE*span)


static func add_building(world: RefCounted,state: Dictionary,position: Array,span: int,model: String,ticks: int,builders: int,capacity: int) -> Dictionary:
	var area:=footprint(position,span)
	var home:={"id":state["next_id"],"x":area.position.x,"z":area.position.y,"span":span,"anchor_x":position[0],"anchor_z":position[1],
		"model_id":model,"build_ticks":ticks,"progress":0,"stored":0,"residents":0,"capacity":capacity,"build_capacity":builders,
		"new_builder_contribution":5.0,"builder":-1,"work_x":area.position.x-1,"work_z":area.position.y,"stalled":false}
	state["next_id"]+=1
	state["homes"].append(home)
	world._spatial_revision+=1
	return home


static func set_stage(state: Dictionary,stage: int,events: Array) -> void:
	var lesson: Dictionary=state["leash_lesson"]
	var source: Dictionary=lesson["definition"]
	lesson["stage"]=stage
	lesson["selection"]={FIRST_FOLLOWER:"follower",HOUSE_OCCUPANT:"home",GROUP:"group"}.get(stage,"")
	lesson.erase("drag_prompt")
	lesson.erase("group_prompt")
	if stage in [FIRST_FOLLOWER,HOUSE_OCCUPANT,GROUP]:
		var drag_key: String={FIRST_FOLLOWER:"082_6",HOUSE_OCCUPANT:"086_6",GROUP:"095_6"}[stage]
		lesson["drag_prompt"]={"id":6100+stage,"text":source["messages"]["LOC_TUT_"+drag_key],
			"ack":false,"position":source["temple_hint"] if stage==GROUP else source["target"]}
	if stage==GROUP:
		lesson["group_prompt"]={"id":6200+stage,"text":source["messages"]["LOC_TUT_093_6"],"ack":false,"position":source["group_center"]}
		lesson["group_size"]=source["followers"].size()-1
	if stage in [INTRO,FIRST_FOLLOWER]:
		lesson["plot"]={"x":source["target"][0],"z":source["target"][1],"size":source["home_span"]}
	else: lesson.erase("plot")
	var key: String={INTRO:"078_6",FIRST_FOLLOWER:"080_6",BUILDER_SLOT:"099_6a",HOUSE_OCCUPANT:"085_6",
		TEAMWORK:"086_6a",GROUP:"090_6",REPAIR:"095_6",RETURN:"149_6"}[stage]
	lesson["prompt"]={"id":6000+stage,"text":source["messages"]["LOC_TUT_"+key],
		"ack":stage in [INTRO,TEAMWORK,RETURN]}
	if stage in [INTRO,BUILDER_SLOT,TEAMWORK]:
		lesson["prompt"]["position"]=source["target"]
	elif stage==HOUSE_OCCUPANT: lesson["prompt"]["position"]=source["initial_home"]
	elif stage==REPAIR: lesson["prompt"]["position"]=source["temple_hint"]
	elif stage in [FIRST_FOLLOWER,GROUP]:
		lesson["prompt"]["follower"]=state["followers"][0 if stage==FIRST_FOLLOWER else 1]["id"]
	if stage in [HOUSE_OCCUPANT,GROUP]:
		events.append({"type":"campaign_camera","action":"SetCamera","args":source["camera"][1 if stage==HOUSE_OCCUPANT else 2]})


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var lesson: Dictionary=state["leash_lesson"]
	var source: Dictionary=lesson["definition"]
	var stage: int=lesson["stage"]
	if command.get("type")=="campaign_ack":
		var prompt: Dictionary=lesson["prompt"]
		return {"ok":prompt.get("ack",false) and command.get("id")==prompt.get("id"),"cost":0,"reason":""}
	if command.get("type")!="leash" or not stage in [FIRST_FOLLOWER,HOUSE_OCCUPANT,GROUP]: return reject
	var selected: Variant=command.get("followers")
	if not selected is Array: return reject
	var expected: Array=[lesson["first_id"]] if stage==FIRST_FOLLOWER else []
	if stage==GROUP:
		for index in range(1,source["followers"].size()): expected.append(state["followers"][index]["id"])
	if selected.size()!=expected.size() or not expected.all(func(id: int) -> bool: return id in selected): return reject
	if int(command.get("home_id",-1))!=(int(lesson["home_id"]) if stage==HOUSE_OCCUPANT else -1): return reject
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	if not (x is float or x is int) or not (z is float or z is int) or not is_finite(x) or not is_finite(z): return reject
	if x<0 or z<0 or x>=state["width"] or z>=state["width"]: return reject
	var release:=Vector2(x,z)
	var target: Array=source["temple_hint"] if stage==GROUP else source["target"]
	if release.distance_squared_to(Vector2(target[0],target[1]))>=16.0: return reject
	if stage==GROUP and world.height_at(roundi(x),roundi(z))<4: return reject # Source minimum layer 23.
	var agents: Array=state["followers"].filter(func(agent: Dictionary) -> bool:
		return agent["id"] in selected or stage==HOUSE_OCCUPANT and agent.get("indoors_home")==lesson["home_id"])
	if stage==HOUSE_OCCUPANT and not agents.is_empty(): agents.resize(1)
	if agents.is_empty(): return reject
	var model: Dictionary=source["temple"]
	var position: Array=model["position"] if stage==GROUP else source["target"]
	var area:=footprint(position,model["span"] if stage==GROUP else source["home_span"])
	var reserved:={}
	if stage==HOUSE_OCCUPANT:
		for agent: Dictionary in state["followers"]:
			if agent["job"]==lesson["target_id"]: reserved[Vector2i(agent["work_x"],agent["work_z"])]=true
	var assignments:=[]
	for agent: Dictionary in agents:
		var from:=Vector2(agent["x"],agent["z"])
		if from.distance_to(release)>float(source["max_length"]): return reject
		var approach: Dictionary=world._promised_abode_approach(Vector2i(from.round()),area,reserved,true)
		if approach.is_empty(): return reject
		reserved[approach["target"]]=true
		assignments.append({"id":agent["id"],"target":approach["target"],"path":approach["path"]})
	var cost: int=source["home_cost"] if stage==HOUSE_OCCUPANT else int(source["follower_cost"])*agents.size()
	return {"ok":state["belief"]>=cost,"cost":cost,"reason":"","assignments":assignments}


static func apply(world: RefCounted,state: Dictionary,command: Dictionary,plan: Dictionary,events: Array) -> void:
	var lesson: Dictionary=state["leash_lesson"]
	var source: Dictionary=lesson["definition"]
	var stage: int=lesson["stage"]
	if command["type"]=="campaign_ack":
		if stage==RETURN:
			lesson["prompt"]={}
			state["won"]=true
			events.append({"type":"campaign_leash_lesson_return"})
		else: set_stage(state,{INTRO:FIRST_FOLLOWER,BUILDER_SLOT:HOUSE_OCCUPANT,TEAMWORK:GROUP}[stage],events)
		return
	var destination: int=lesson["target_id"]
	if stage==FIRST_FOLLOWER:
		var home:=add_building(world,state,source["target"],source["home_span"],source["home_model"],source["build_ticks"],2,source["home_capacity"])
		destination=home["id"]
		lesson["target_id"]=destination
		lesson["first_release"]=state["tick"]
		set_stage(state,BUILDER_SLOT,events)
	elif stage==HOUSE_OCCUPANT:
		for home: Dictionary in state["homes"]:
			if home["id"]==lesson["home_id"]: home["residents"]-=1; break
		set_stage(state,TEAMWORK,events)
	else:
		var site: Dictionary=state["progression"]["shrines"][0]
		var model: Dictionary=source["temple"]
		var shrine:=add_building(world,state,model["position"],model["span"],model["model_id"],model["build_ticks"],model["build_capacity"],0)
		shrine.merge({"kind":"shrine","rotation":model["rotation"],"shrine_id":model["id"]},true)
		destination=shrine["id"]
		lesson["temple_id"]=destination
		site["started"]=true
		set_stage(state,REPAIR,events)
	for assignment: Dictionary in plan["assignments"]:
		for agent: Dictionary in state["followers"]:
			if agent["id"]!=assignment["id"]: continue
			var target: Vector2i=assignment["target"]
			agent.erase("indoors_home")
			agent.merge({"job":destination,"state":"walking","path":assignment["path"].duplicate(),
				"work_x":target.x,"work_z":target.y,"leash_route_speed":2.0 if stage!=GROUP else 0.0},true)
			Leash.remember_drop(agent,Vector2(command["x"],command["z"]))
			break


static func advance(world: RefCounted,state: Dictionary,events: Array) -> void:
	if state["won"]: return
	var lesson: Dictionary=state["leash_lesson"]
	var stage: int=lesson["stage"]
	for agent: Dictionary in state["followers"]:
		if agent["job"]!=-1:
			world.finish_promised_approach(agent,Vector2i(agent["work_x"],agent["work_z"]))
			world._update_agent(agent,false)
	if not (stage in [BUILDER_SLOT,HOUSE_OCCUPANT] and state["tick"]>=int(lesson["first_release"])+int(lesson["definition"]["build_ticks"])-400):
		world._advance_construction()
	for home: Dictionary in state["homes"]:
		if stage==BUILDER_SLOT and home["id"]==lesson["target_id"] and home["progress"]>0:
			if not lesson.has("slot_prompt_tick"): lesson["slot_prompt_tick"]=int(state["tick"])+35
			if state["tick"]>=int(lesson["slot_prompt_tick"]):
				lesson["prompt"]={"id":6000+BUILDER_SLOT,"text":lesson["definition"]["messages"]["LOC_TUT_100_6"],"ack":true,"position":lesson["definition"]["target"]}
		if stage==REPAIR and home["id"]==lesson["temple_id"] and home["progress"]>=home["build_ticks"]:
			state["progression"]["shrines"][0]["complete"]=true
			set_stage(state,RETURN,events)
