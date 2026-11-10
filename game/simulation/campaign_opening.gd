extends RefCounted
## Authored Homeworld6 rescue/trail. All timing and callbacks use simulation ticks.
## Later tutorial/story stages are retained as source data, not fabricated here.

const Interpreter = preload("res://simulation/voyage_script.gd")
const DayCycle = preload("res://simulation/day_cycle.gd")
const SourceRocks = preload("res://simulation/authored_rocks.gd")
const ROCK_ID_BASE := 4294967296
var world: RefCounted
var state: Dictionary
var events: Array
var opening: Dictionary
var vm := Interpreter.new()


static func initialize(definition: Dictionary) -> Dictionary:
	SourceRocks.prepare(definition)
	var globals: Dictionary = definition["constants"].duplicate(true)
	globals["blockedFollowerObj"]=-1
	globals.merge(definition.get("helpers",{}).duplicate(true))
	globals["DESKTOP_MODE"]=true
	globals["initialFollowers"]={}
	var entries: Array = []
	for row: Dictionary in definition["route"]: entries.append(row["entry"].duplicate(true))
	return {"definition":definition,"phase":"rescue","checkpoint":-1,"globals":globals,
		"entries":entries,
		"submerged_levels":{},"observer":{"mode":"all"},"reactions":{},"next_reaction":1,"tips":{},"next_tip":1,
		"clock":DayCycle.initialize(definition["day_cycle"]),"effects":{},"next_effect":1,
		"promised_step":-1,"actions":{},"next_action":1,"reaction_objects":{},"activity_exception":null,"tree_regeneration":false,
		"camera_locked":true,"zoom_locked":true,
		"scheduled":[],"messages":[{"id":2,"callback":null},{"id":3,"callback":null}],
		"protected":[],"persistent":{},"last_topology":-1,"blocked":false,
		"movement_paused":false,"reaction_speed":float(globals["origGotoSpeedMult"]),"rescue_tick":-1,"revision":0,"error":""}


func configure(owner: RefCounted,data: Dictionary,output: Array) -> void:
	world=owner
	state=data
	events=output
	opening=state["opening"]
	# Script tables use one-based follower indices and a zero-based route. Rebind
	# these aliases after restoring JSON, which cannot preserve table identity.
	var blocks := {}
	for i in range(opening["entries"].size()):
		var entry: Dictionary = opening["entries"][i]
		# The source dispatches these authored mixed-case callback names in lower case.
		for name: String in ["onArrived","onBlocked","onUnblocked"]:
			if entry.has(name): entry[name.to_lower()]=entry[name]
		blocks[str(i)]=entry
	opening["globals"]["BLOCKAGES"]=blocks
	opening["globals"]["currentBlockage"]=int(opening["checkpoint"])
	opening["globals"]["string"]={"format":{"builtin":"string.format"}}
	opening["globals"]["table"]={"insert":{"builtin":"table.insert"}}
	if opening["globals"]["initialFollowers"].is_empty():
		for i in range(opening["protected"].size()): opening["globals"]["initialFollowers"][str(i+1)]={"id":int(opening["protected"][i]),"blockage":-1}
	vm.initialize(opening["definition"]["program"],opening["globals"],api)


func show_message(id: int, callback: Variant = null) -> void:
	for message: Dictionary in opening["messages"]:
		if int(message["id"])==id:
			message["callback"]=callback
			return
	var message := {"id":id,"callback":callback}
	var entry: Dictionary = opening["definition"]["messages"].get(str(id),{})
	if entry.get("object_get",{}).has("symbol"):
		var object: Variant = vm.hook(str(entry["object_get"]["symbol"]))
		if object!=null:
			message["object"]=object
			if int(object)>=ROCK_ID_BASE:
				var cell := int(object)-ROCK_ID_BASE
				var rock := SourceRocks.at(state,cell)
				message["anchor"]={"kind":"rock","x":int(rock.get("x",cell%int(state["width"]))),"z":int(rock.get("z",cell/int(state["width"])))}
			else: message["anchor"]={"kind":"follower","id":int(object)}
	if id==29:
		var options: Array = opening["definition"]["messages"]["29"]["options"]
		message["option"]=mini(options.size()-1,floori(world._random.randf()*options.size()))
	opening["messages"].append(message)
	opening["revision"]+=1


func clear_message(id: int) -> void:
	for message: Dictionary in opening["messages"].duplicate():
		if int(message["id"])==id: opening["messages"].erase(message); opening["revision"]+=1


func acknowledge(id: int) -> void:
	for message: Dictionary in opening["messages"].duplicate():
		if int(message["id"])!=id: continue
		clear_message(id)
		if message["callback"]!=null: vm.invoke(message["callback"])
		elif id==4 and opening["phase"]=="worship": next_checkpoint()
		if not vm.error.is_empty(): opening["error"]=vm.error
		return


func run_callback(name: String) -> void:
	var index := int(opening["checkpoint"])
	if index<0 or index>=opening["definition"]["route"].size(): return
	var entry: Dictionary = opening["entries"][index]
	if entry.has(name): vm.invoke(entry[name],[entry])
	elif name=="onArrived": next_checkpoint()
	elif name=="onBlocked": vm.hook("defaultFollowerBlockedBehaviour")
	if not vm.error.is_empty(): opening["error"]=vm.error


func next_checkpoint() -> void:
	if int(opening["checkpoint"])==opening["definition"]["route"].size()-1:
		vm.hook("clearInitialFollowersTarget")
		opening["phase"]="trailing"
		opening["camera_locked"]=true
		opening["globals"]["hackStopFollowerCheck"]=true
		opening["globals"]["onStartPlayTriggered"]=true
		vm.invoke(opening["definition"]["waiting_hooks"]["onListening"])
		events.append({"type":"campaign_stage","stage":"trailing"})
		return
	var starting: bool = opening["phase"]!="trail"
	clear_message(29)
	opening["globals"]["bIgnoreFollowerBlocked"]=false
	opening["globals"]["bIgnoreFollowerBlocked2"]=false
	opening["globals"]["blockedFollowerObj"]=null
	api("StopReaction",[opening["globals"].get("assessLandReaction")])
	opening["globals"]["assessLandReaction"]=null
	opening["checkpoint"]+=1
	opening["globals"]["currentBlockage"]=int(opening["checkpoint"])
	opening["persistent"]["TrailBlockage"]=int(opening["checkpoint"])
	opening["last_topology"]=-1
	opening["blocked"]=false
	opening["movement_paused"]=false
	for agent: Dictionary in followers(): agent["path"]=[]
	opening["revision"]+=1
	opening["phase"]="trail"
	if starting: vm.invoke(opening["definition"]["trail_hooks"]["onListening"])
	vm.hook("setInitialFollowersTarget")
	events.append({"type":"campaign_stage","stage":"trail","checkpoint":opening["checkpoint"]})


func followers() -> Array:
	return state["followers"].filter(func(agent: Dictionary) -> bool: return int(agent["id"]) in opening["protected"])


func next_promised_step() -> void:
	opening["phase"]="promised_land"
	opening["promised_step"]+=1
	var step := int(opening["promised_step"])
	opening["persistent"]["PromisedLandProgress"]=step+1
	opening["handoff"]={"tutorial":"PromisedLand","step":step,"available":step<2}
	events.append({"type":"campaign_handoff","tutorial":"PromisedLand","step":step,"available":step<2})
	if step<2: vm.invoke(opening["definition"]["promised_steps"][step]["hooks"]["onListening"])


static func rock_alive(data: Dictionary,cell: int) -> bool:
	return SourceRocks.alive(data,cell)


static func can_tap_rock(data: Dictionary,cell: int) -> bool:
	var story: Dictionary = data["opening"]
	var root := SourceRocks.canonical_cell(data,cell)
	return story["phase"]=="promised_land" and story["promised_step"]==1 and story["activity_exception"]==ROCK_ID_BASE+root and rock_alive(data,cell) and preload("res://simulation/influence.gd").contains(data,root%int(data["width"]),root/int(data["width"]))


func tap_rock(cell: int) -> void:
	cell=SourceRocks.canonical_cell(state,cell)
	var p: Dictionary = state["progression"]
	p["rock_taps"][str(cell)]=int(p["rock_taps"].get(str(cell),0))+1
	if int(p["rock_taps"][str(cell)])<int(opening["definition"]["object_config"]["taps_to_destroy_rock"]): return
	var rock := SourceRocks.at(state,cell)
	if not rock.is_empty():
		for dz in range(int(rock["size_z"])):
			for dx in range(int(rock["size_x"])):
				p["rock_taps"][str((int(rock["origin_z"])+dz)*int(state["width"])+int(rock["origin_x"])+dx)]=int(p["rock_taps"][str(cell)])
	p["rock_revision"]+=1
	var id := ROCK_ID_BASE+cell
	for key: String in opening["reaction_objects"].keys():
		if opening["reaction_objects"][key]==id: api("StopReaction",[int(key)])
	events.append({"type":"rock_removed","id":id,"cell":cell})
	var hooks: Dictionary = opening["definition"]["promised_steps"][int(opening["promised_step"])]["hooks"]
	if hooks.has("onRockDestroyed"): vm.invoke(hooks["onRockDestroyed"],[id])
	if not vm.error.is_empty(): opening["error"]=vm.error


func advance() -> void:
	for waiter: Dictionary in DayCycle.advance(opening["clock"],opening["definition"]["day_cycle"],0.1): vm.invoke(waiter["callback"],waiter["args"])
	var due: Array = opening["scheduled"].filter(func(item: Dictionary) -> bool: return int(item["tick"])<=int(state["tick"]))
	for item: Dictionary in due:
		opening["scheduled"].erase(item)
		if item.get("action","")=="worship":
			opening["phase"]="worship"
			show_message(4)
			opening["scheduled"].append({"tick":int(state["tick"])+150,"action":"begin_trail"})
		elif item.get("action","")=="begin_trail":
			if opening["phase"]=="worship": acknowledge(4)
		else: vm.invoke(item["callback"],item["args"])
	if not vm.error.is_empty(): opening["error"]=vm.error
	if not opening["error"].is_empty(): return
	var agents := followers()
	if agents.size()!=2: return
	if opening["phase"] in ["rescue","embrace","worship"]:
		var dry := true
		for agent: Dictionary in agents:
			if world.height_at(roundi(agent["x"]),roundi(agent["z"]))<=0: dry=false
		if not dry:
			opening["phase"]="rescue"
			opening["scheduled"]=[]
			opening["rescue_tick"]=-1
			show_message(2)
			show_message(3)
			for agent: Dictionary in agents: agent["state"]="drowning" if world.height_at(roundi(agent["x"]),roundi(agent["z"]))<=0 else "idle"
			return
		if opening["phase"]=="rescue":
			opening["phase"]="embrace"
			opening["rescue_tick"]=int(state["tick"])
			opening["messages"]=[]
			opening["scheduled"].append({"tick":int(state["tick"])+60,"action":"worship"})
			events.append({"type":"source_sound","event":"PLAYSOUND_OPENINGTUTORIAL_FOLLOWERSSAVED"})
		for agent: Dictionary in agents: agent["state"]="worshipping" if opening["phase"]=="worship" else ("hugging_take" if agent.get("female",false) else "hugging_give")
		return
	if not opening["phase"] in ["trail","trailing"] or opening["movement_paused"]: return
	if "StandStill" in opening["reactions"].values():
		for agent: Dictionary in agents: agent["state"]="idle"
		return
	var entry: Dictionary = opening["entries"][int(opening["checkpoint"])]
	var target := Vector2(entry["Target"]["x"],entry["Target"]["y"])
	var topology: int = state["terrain_revision"]
	var any_blocked := false
	var blocked_ids: Array = []
	for agent: Dictionary in agents:
		var position := Vector2(agent["x"],agent["z"])
		if position.distance_squared_to(target)<4:
			agent["state"]="idle"
			agent["path"]=[]
			continue
		if agent["path"].is_empty() and agent["state"]=="waiting" and opening["blocked"] and int(opening["last_topology"])==topology:
			agent["state"]="waiting"
			any_blocked=true
			blocked_ids.append(int(agent["id"]))
			continue
		if agent["path"].is_empty() or int(opening["last_topology"])!=topology:
			agent["path"]=route_to_target(agent,target)
		if agent["path"].is_empty():
			agent["state"]="waiting"
			any_blocked=true
			blocked_ids.append(int(agent["id"]))
			continue
		var cell := int(agent["path"][0])
		var destination := Vector2(cell%int(state["width"]),cell/int(state["width"]))
		var speed: float = float(world.follower_values(agent).get("RouteSpeed",opening["definition"]["constants"]["base_follower_speed"]))*float(opening["reaction_speed"])
		var next := position.move_toward(destination,speed*0.1)
		agent["x"]=next.x
		agent["z"]=next.y
		agent["state"]="walking"
		if next.distance_squared_to(destination)<0.000001: agent["path"].pop_front()
	var checkpoint := int(opening["checkpoint"])
	if opening["phase"]=="trail" and any_blocked and not opening["globals"]["bIgnoreFollowerBlocked"]:
		var leading: Variant = vm.hook("getLeadingFollowerId")
		if int(leading) in blocked_ids: vm.invoke(opening["definition"]["trail_hooks"]["onFollowerBlocked"],[leading])
	if not vm.error.is_empty(): opening["error"]=vm.error
	if checkpoint!=int(opening["checkpoint"]): return
	opening["blocked"]=any_blocked
	opening["last_topology"]=topology
	# The original one-second observer callback owns arrival, not render frames
	# or this movement loop. Its per-follower checkpoint history also gates catch-up.


func route_to_target(agent: Dictionary,target: Vector2) -> Array:
	var start := Vector2i(roundi(agent["x"]),roundi(agent["z"]))
	var candidates: Array[Vector2i] = []
	for dz in range(-2,3):
		for dx in range(-2,3):
			var cell := Vector2i(roundi(target.x)+dx,roundi(target.y)+dz)
			if Vector2(cell).distance_squared_to(target)<4 and world.height_at(cell.x,cell.y)>0: candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return Vector2(a).distance_squared_to(target)<Vector2(b).distance_squared_to(target))
	for cell: Vector2i in candidates:
		var path: Array = world._route(start,cell)
		if not path.is_empty(): return path
	# A blocked follower first approaches the obstacle; it must not stop at the
	# beginning of the route just because the destination is currently unreachable.
	var frontier: Array[Vector2i] = [start]
	var previous := {start:start}
	var best := start
	var cursor := 0
	while cursor<frontier.size():
		var current := frontier[cursor]
		cursor+=1
		if Vector2(current).distance_squared_to(target)<Vector2(best).distance_squared_to(target): best=current
		for direction: Vector2i in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
			var next := current+direction
			if previous.has(next) or world.height_at(next.x,next.y)<=0 or world._occupied(next.x,next.y): continue
			if absi(world.height_at(current.x,current.y)-world.height_at(next.x,next.y))>1: continue
			previous[next]=current
			frontier.append(next)
	var approach: Array = []
	while best!=start:
		approach.push_front(best.y*int(state["width"])+best.x)
		best=previous[best]
	return approach


func api(name: String,args: Array) -> Variant:
	match name:
		"advanceBlockage": next_checkpoint()
		"currentTutorialStep":
			if args[0]=="Trail" and opening["phase"] in ["trailing","arrival"]:
				var hooks: Dictionary = opening["definition"]["waiting_hooks" if opening["phase"]=="trailing" else "arrival_hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			if args[0]=="PromisedLand" and opening["phase"]=="promised_land" and int(opening["promised_step"])<2:
				var hooks: Dictionary = opening["definition"]["promised_steps"][int(opening["promised_step"])]["hooks"].duplicate(true)
				for key: String in hooks.keys(): hooks[key.to_lower()]=hooks[key]
				return hooks
			opening["error"]="Unsupported campaign tutorial stage query."
		"nextTrailStep":
			if opening["phase"]=="trailing":
				opening["phase"]="arrival"
				events.append({"type":"campaign_stage","stage":"arrival"})
				vm.invoke(opening["definition"]["arrival_hooks"]["onListening"])
			elif opening["phase"]=="arrival": opening["phase"]="trail_complete"
			else: opening["error"]="Unsupported campaign trail-stage transition."
		"nextPromisedLandStep": next_promised_step()
		"ShowUI","ShowUIWithCb":
			if args.size()>1 and args[0] in ["Trail","PromisedLand"]: show_message(int(args[1])+(1000 if args[0]=="PromisedLand" else 0),args[2] if args.size()>2 else null)
		"ClearUI":
			if args.size()>1 and args[0] in ["Trail","PromisedLand"]: clear_message(int(args[1])+(1000 if args[0]=="PromisedLand" else 0))
		"After":
			opening["scheduled"].append({"tick":int(state["tick"])+maxi(1,roundi(float(args[0])*10)),"callback":args[1],"args":args.slice(2)})
		"PlaySound": events.append({"type":"source_sound","event":str(args[0])})
		"Midday","Sunset","Midnight": return opening["definition"]["day_cycle"]["functions"][name]["value"]
		"TimeOfDay":
			if not args.is_empty(): opening["clock"]["time"]=fposmod(float(args[0]),float(opening["definition"]["day_cycle"]["period"]))
			return float(opening["clock"]["time"])/float(opening["definition"]["day_cycle"]["period"])
		"Config":
			if args.size()==2 and args[0]=="TimeOfDaySpeed": opening["clock"]["speed"]=float(args[1])
			else: opening["error"]="Unsupported campaign config operation."
		"AtTimeOfDay": opening["clock"]["waiters"].append({"time":fposmod(float(args[0]),float(opening["definition"]["day_cycle"]["period"])),"callback":args[1],"args":args.slice(2)})
		"Unlock":
			if not state["progression"].has("script_unlocks"): state["progression"]["script_unlocks"]={}
			state["progression"]["script_unlocks"][str(args[0])]=true
		"TriggerVFX":
			var id := int(opening["next_effect"])
			opening["next_effect"]+=1
			opening["effects"][str(id)]={"name":str(args[0]),"args":args.slice(1).duplicate(true)}
			events.append({"type":"campaign_vfx_start","id":id,"name":str(args[0]),"args":args.slice(1).duplicate(true)})
			return id
		"StopVFXInstance":
			opening["effects"].erase(str(int(args[0])))
			events.append({"type":"campaign_vfx_stop","id":int(args[0])})
		"ClearAlertByID":
			if not args.is_empty() and args[0]!=null: opening["error"]="Unsupported campaign alert handle."
		"CreateReaction":
			var id := int(opening["next_reaction"])
			opening["next_reaction"]+=1
			opening["reactions"][str(id)]=str(args[0])
			if args[0]=="TutorialGoTo":
				opening["movement_paused"]=false
				opening["blocked"]=false
				opening["last_topology"]=-1
				for agent: Dictionary in followers(): agent["path"]=[]
			else:
				for agent: Dictionary in followers(): agent["state"]="scared" if args[0]=="TutorialAtPromisedLandScared" else ("idle" if args[0]=="StandStill" else "assessing")
			return id
		"AttachReaction":
			var id := int(api("CreateReaction",[args[0]]))
			opening["reaction_objects"][str(id)]=args[1]
			return id
		"StopReaction":
			if not args.is_empty() and args[0]!=null:
				var key := str(int(args[0]))
				if opening["reactions"].get(key)=="TutorialGoTo": opening["movement_paused"]=true
				opening["reactions"].erase(key)
				opening["reaction_objects"].erase(key)
		"GetFirstRockInRadius":
			var center := Vector2(args[0],args[1])
			var radius := float(args[2])
			var best := radius*radius+0.000001
			var result: Variant = null
			for rock: Dictionary in SourceRocks.entries(state):
				var cell := SourceRocks.cell(state,rock)
				var distance := center.distance_squared_to(Vector2(rock["x"],rock["z"]))
				if distance<best and rock_alive(state,cell): best=distance; result=ROCK_ID_BASE+cell
			for z in range(maxi(0,floori(center.y-radius)),mini(int(state["width"]),ceili(center.y+radius)+1)):
				for x in range(maxi(0,floori(center.x-radius)),mini(int(state["width"]),ceili(center.x+radius)+1)):
					var cell := z*int(state["width"])+x
					if not SourceRocks.at(state,cell).is_empty(): continue
					var distance := center.distance_squared_to(Vector2(x,z))
					if distance<best and rock_alive(state,cell): best=distance; result=ROCK_ID_BASE+cell
			return result
		"SetActivityLockException": opening["activity_exception"]=args[0]
		"ClearActivityLockException": opening["activity_exception"]=null
		"SetTreeRegen": opening["tree_regeneration"]=bool(args[0])
		"DisplayAction":
			var id := int(opening["next_action"])
			opening["next_action"]+=1
			opening["actions"][str(id)]=args.duplicate(true)
			events.append({"type":"campaign_action_start","id":id,"args":args.duplicate(true)})
			return id
		"ClearAction":
			opening["actions"].erase(str(int(args[0])))
			events.append({"type":"campaign_action_stop","id":int(args[0])})
		"Persist":
			if args.size()>1: opening["persistent"][str(args[0])]=args[1]
			return opening["persistent"].get(str(args[0]),0)
		"FollowerPos":
			for agent: Dictionary in followers():
				if int(agent["id"])==int(args[0]): return {"multiple":[agent["x"],agent["z"]]}
			return {"multiple":[null,null]}
		"ProcessFollowersInRadius":
			var center := Vector2(args[0],args[1])
			for agent: Dictionary in followers():
				if Vector2(agent["x"],agent["z"]).distance_squared_to(center)<=float(args[2])*float(args[2]): vm.invoke(args[3],[int(agent["id"])])
		"table.insert":
			var table: Dictionary = args[0]
			table[str(Interpreter.table_length(table)+1)]=args[1]
		"Vec2DistanceSq": return Vector2(float(args[0])-float(args[2]),float(args[1])-float(args[3])).length_squared()
		"Table":
			if args.size() in [3,4] and args[0]=="reactions0" and args[1] in ["AgressiveSpeedMult","PassiveSpeedMult"]:
				if args.size()==3: return opening["reaction_speed"]
				opening["reaction_speed"]=float(args[3])
			else: opening["error"]="Unsupported campaign table operation."
		"IsValidPath":
			var start := Vector2i(roundi(float(args[0])),roundi(float(args[1])))
			var target := Vector2i(roundi(float(args[2])),roundi(float(args[3])))
			return world.height_at(target.x,target.y)>0 and (start==target or not world._route(start,target).is_empty())
		"IsPointOnScreen": return point_visible(float(args[0]),float(args[1]),float(args[2]))
		"GetStepAtPoint":
			return world.source_step_at(float(args[0]),float(args[1]))
		"TeleportFollower":
			for agent: Dictionary in followers():
				if int(agent["id"])==int(args[0]):
					agent["x"]=float(args[1]); agent["z"]=float(args[2]); agent["path"]=[]
					events.append({"type":"campaign_catch_up","cause":"trailing_path_repair" if opening["phase"]=="trailing" else "offscreen","id":int(agent["id"]),"x":agent["x"],"z":agent["z"]})
		"TriggerTipGameObject":
			var id := int(opening["next_tip"])
			opening["next_tip"]+=1
			opening["tips"][str(id)]={"follower":int(args[0]),"key":str(args[1])}
			return id
		"ClearTip":
			if not args.is_empty() and args[0]!=null: opening["tips"].erase(str(int(args[0])))
		"SetCamera","LockCamera","UnlockCamera","UnlockZooming":
			if name in ["LockCamera","UnlockCamera"]: opening["camera_locked"]=name=="LockCamera"
			elif name=="UnlockZooming": opening["zoom_locked"]=false
			events.append({"type":"campaign_camera","action":name,"args":args.duplicate(true)})
		"Console","string.format": pass # Source diagnostics, not game decisions.
		_:
			opening["error"]="Unsupported campaign callback: "+name
	return null


func observe(command: Dictionary) -> void:
	opening["observer"]={"mode":"orthographic","projection":command["projection"].duplicate()}
	if command.get("ended",false) and opening["phase"]=="trail":
		vm.hook("cameraEndUpdate")
		if not vm.error.is_empty(): opening["error"]=vm.error


func sculpt_completed() -> void:
	if opening["phase"]=="trail": vm.invoke(opening["definition"]["trail_hooks"]["onSculptComplete"])
	else:
		clear_message(1)
		clear_message(3)
	if not vm.error.is_empty(): opening["error"]=vm.error


func sculpt_failed() -> void:
	if opening["phase"]=="trailing": vm.invoke(opening["definition"]["waiting_hooks"]["onSculptFailed"])
	if not vm.error.is_empty(): opening["error"]=vm.error


func point_visible(x: float,z: float,cutoff: float) -> bool:
	# Headless self-play explicitly uses an all-seeing observer until a replay or
	# presentation submits its orthographic projection. No renderer is queried.
	if opening["observer"]["mode"]=="all": return true
	var projection: Array = opening["observer"]["projection"]
	var height: float = world.height_at(roundi(x),roundi(z))*0.3
	var u: float = projection[0]*x+projection[1]*z+projection[2]*height+projection[3]
	var v: float = projection[4]*x+projection[5]*z+projection[6]*height+projection[7]
	return u>=cutoff and u<=1-cutoff and v>=cutoff and v<=1-cutoff


static func valid_observation(command: Dictionary) -> bool:
	if not command.get("projection") is Array or command["projection"].size()!=8 or not command.get("ended",false) is bool: return false
	for value: Variant in command["projection"]:
		if not (value is float or value is int) or not is_finite(value) or absf(value)>1000000: return false
	return true


static func valid(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not data.get("definition") is Dictionary or not data.get("globals") is Dictionary or not data.get("persistent") is Dictionary: return false
	if not data.get("protected") is Array or not data.get("messages") is Array or not data.get("scheduled") is Array: return false
	var definition: Dictionary = data["definition"]
	if not SourceRocks.valid(definition): return false
	if definition.has("plot_environment") and not preload("res://simulation/source_biomes.gd").valid(definition["plot_environment"]): return false
	if definition.has("house_selection") and not preload("res://simulation/source_houses.gd").valid(definition["house_selection"]): return false
	if definition.has("build_candidate_values"):
		if not preload("res://simulation/source_build_candidates.gd").valid_values(definition["build_candidate_values"]): return false
		for row: Dictionary in definition.get("house_selection",[]):
			if not definition["build_candidate_values"].has(row["id"]): return false
	if definition.has("rock_motion_config") and not preload("res://simulation/source_rock_motion.gd").valid_config(definition["rock_motion_config"]): return false
	if definition.has("tree_response_config") and not preload("res://simulation/source_tree_response.gd").valid_config(definition["tree_response_config"]): return false
	if definition.has("plot_resize_rules") and not preload("res://simulation/source_plot_resize.gd").valid_rules(definition["plot_resize_rules"]): return false
	if definition.has("plot_conversion_rules") and not preload("res://simulation/source_plot_conversion.gd").valid_rules(definition["plot_conversion_rules"]): return false
	if definition.has("build_start_rules") and not preload("res://simulation/source_build_start.gd").valid_rules(definition["build_start_rules"]): return false
	if definition.has("plot_cost") and not preload("res://simulation/source_plot_cost.gd").valid_definition(definition): return false
	if definition.has("house_constructor"):
		if not preload("res://simulation/source_house_constructor.gd").valid_content(definition["house_constructor"]): return false
	if definition.has("house_pool_rules"):
		if not definition["house_pool_rules"] is Dictionary or not preload("res://simulation/source_plot_schedule.gd").integer_between(definition["house_pool_rules"].get("capacity"),1,65535): return false
	if definition.has("target_reference_rules") and not preload("res://simulation/source_target_references.gd").valid_rules(definition["target_reference_rules"]): return false
	if definition.has("action_sequences") and not preload("res://simulation/source_action_sequence.gd").valid_content(definition["action_sequences"]): return false
	if definition.has("action_entry") and not preload("res://simulation/source_action_entry.gd").valid_content(definition["action_entry"]): return false
	if definition.has("action_controller") and not preload("res://simulation/source_action_controller.gd").valid_content(definition["action_controller"]): return false
	if definition.has("plot_field") and not preload("res://simulation/source_plot_field.gd").valid(definition["plot_field"]): return false
	if definition.has("influence_rules") and not preload("res://simulation/source_influence.gd").valid_rules(definition["influence_rules"]): return false
	if not definition.get("route") is Array or definition["route"].size()!=14 or not definition.get("program") is Dictionary or not definition.get("messages") is Dictionary: return false
	if not definition.get("constants") is Dictionary or not definition.get("program",{}).get("functions") is Dictionary: return false
	if not definition.get("day_cycle") is Dictionary or not DayCycle.valid(data.get("clock"),definition["day_cycle"]): return false
	if not definition.get("arrival_hooks") is Dictionary or not data.get("effects") is Dictionary or not integer(data.get("next_effect"),1,1000000000000): return false
	if not definition.get("promised_steps") is Array or definition["promised_steps"].size()!=11 or not definition.get("object_config") is Dictionary: return false
	if not integer(data.get("promised_step"),-1,10) or not integer(data.get("next_action"),1,1000000000000): return false
	if not data.get("actions") is Dictionary or not data.get("reaction_objects") is Dictionary or not data.get("tree_regeneration") is bool: return false
	if data.get("activity_exception")!=null and not integer(data["activity_exception"],ROCK_ID_BASE,ROCK_ID_BASE+1024*1024-1): return false
	if not definition.get("helpers") is Dictionary or not definition.get("trail_hooks") is Dictionary or not definition.get("waiting_hooks") is Dictionary or not data.get("globals",{}).get("initialFollowers") is Dictionary: return false
	for key: String in ["reactions","tips","observer"]:
		if not data.get(key) is Dictionary: return false
	if not data["observer"].get("mode") in ["all","orthographic"]: return false
	if data["observer"]["mode"]=="orthographic" and not valid_observation(data["observer"]): return false
	for key: String in ["next_reaction","next_tip"]:
		if not integer(data.get(key),1,1000000000000): return false
	for key: String in ["camera_locked","zoom_locked"]:
		if not data.get(key) is bool: return false
	var band: Variant = definition.get("coastal_free_band")
	if not band is Dictionary or not integer(band.get("min"),0,255) or not integer(band.get("max"),0,255) or band["min"]>band["max"]: return false
	if not data.get("entries") is Array or data["entries"].size()!=definition["route"].size() or not data.get("submerged_levels") is Dictionary: return false
	var floor: Variant = definition.get("raw_floor")
	if not (floor is Array or floor is PackedByteArray) or floor.size()!=1024*1024: return false
	for height: Variant in floor:
		if not integer(height,0,255): return false
	for key: Variant in data["submerged_levels"]:
		if not key is String or not key.is_valid_int() or int(key)<0 or int(key)>=1024*1024 or not integer(data["submerged_levels"][key],0,19): return false
	if data["protected"].size()!=2 or data["protected"][0]==data["protected"][1]: return false
	for id: Variant in data["protected"]:
		if not integer(id,1,1000000): return false
	for key: String in ["blocked","movement_paused"]:
		if not data.get(key) is bool: return false
	for key: String in ["last_topology","rescue_tick","revision"]:
		if not integer(data.get(key),-1,1000000000000): return false
	var speed: Variant = data.get("reaction_speed")
	if not (speed is int or speed is float) or not is_finite(float(speed)) or speed<0 or speed>1000: return false
	if not data.get("error") is String or data["error"].length()>1000 or data["messages"].size()>64 or data["scheduled"].size()>2048: return false
	for message: Variant in data["messages"]:
		if not message is Dictionary or not integer(message.get("id"),1,1033) or not definition["messages"].has(str(int(message["id"]))): return false
		if not message.has("callback") or not (message["callback"]==null or message["callback"] is Dictionary or message["callback"] is String): return false
		if int(message["id"])==29 and not integer(message.get("option"),0,4): return false
	for item: Variant in data["scheduled"]:
		if not item is Dictionary or not integer(item.get("tick"),0,1000000000000): return false
		if item.has("action"):
			if not item["action"] in ["worship","begin_trail"]: return false
		elif not item.get("args") is Array or not (item.get("callback") is String or item.get("callback") is Dictionary): return false
	for entry: Variant in data["entries"]:
		if not entry is Dictionary or not entry.get("Target") is Dictionary: return false
		for axis: String in ["x","y"]:
			var coordinate: Variant = entry["Target"].get(axis)
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or coordinate<0 or coordinate>=1024: return false
	if not data.get("phase") in ["rescue","embrace","worship","trail","trailing","arrival","trail_complete","promised_land"]: return false
	var checkpoint: Variant = data.get("checkpoint")
	if not integer(checkpoint,-1,14): return false
	if data["phase"] in ["trailing","arrival"] and checkpoint!=13: return false
	return not (data["phase"]=="trail" and (checkpoint<0 or checkpoint>=14))


static func integer(value: Variant,minimum: int,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value==int(value) and value>=minimum and value<=maximum


static func sculpt_cost(state: Dictionary,edits: Array,fallback: int) -> int:
	var opening: Dictionary = state["opening"]
	var floor: Variant = opening["definition"]["raw_floor"]
	var band: Dictionary = opening["definition"]["coastal_free_band"]
	for edit: Dictionary in edits:
		var cell: int = edit["cell"]
		var previous := int(state["terrain"][cell])+19 if int(state["terrain"][cell])>0 else int(opening["submerged_levels"].get(str(cell),floor[cell]))
		# Global onSculptFailed identifies the free 17..24 coastal band.
		if mini(previous,int(edit["height"])+19)<int(band["min"]) or maxi(previous,int(edit["height"])+19)>int(band["max"]): return fallback
	return 0
