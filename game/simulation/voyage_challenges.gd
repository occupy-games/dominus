extends RefCounted
## Original Lua API translated to fixed-tick, plain-data challenge operations.

const Interpreter = preload("res://simulation/voyage_script.gd")
var world: RefCounted
var state: Dictionary
var voyage: Dictionary
var definition: Dictionary
var events: Array
var vm := Interpreter.new()


func configure(owner: RefCounted, data: Dictionary, output: Array) -> void:
	world=owner
	state=data
	voyage=state["voyage"]
	definition=voyage["definition"]
	events=output
	vm.initialize(definition.get("program",{}),voyage["globals"],apply_api)


func point(x: Variant, z: Variant) -> Vector2:
	return Vector2(float(x)-float(definition["origin"][0]),float(z)-float(definition["origin"][1]))


func source_point(local: Vector2) -> Dictionary:
	return {"multiple":[local.x+definition["origin"][0],local.y+definition["origin"][1]]}


func hook(name: String, args: Array = []) -> void:
	vm.hook(name,args)
	if not vm.error.is_empty():
		voyage["script_error"]=vm.error
		events.append({"type":"voyage_script_error","message":vm.error})


func prepare() -> void:
	for object: Dictionary in definition.get("objects",[]):
		if object["type"] in ["champion","wolf1"]: spawn_enemy(object["type"],Vector2(object["x"],object["z"]))
		elif str(object["type"]).begins_with("tree"):
			var x := int(object["x"])
			var z := int(object["z"])
			if world.height_at(x,z)>0:
				var exists := false
				for tree: Dictionary in state["trees"]:
					if int(tree["x"])==x and int(tree["z"])==z: exists=true; break
				if not exists: state["trees"].append({"x":x,"z":z,"variant":maxi(0,int(str(object["type"]).trim_prefix("tree"))-1)})
		elif str(object["type"]).begins_with("treasure"):
			var chest := object.duplicate(true)
			chest["id"]=state["next_id"]
			state["next_id"]+=1
			chest["opened"]=false
			chest["height"]=world.height_at(roundi(chest["x"]),roundi(chest["z"]))-int(chest["depth"])
			voyage["chests"].append(chest)
	vm.run()
	hook("onPostLoad",[0])
	hook("onFewFramesIn")


func spawn_enemy(kind: String, position: Vector2) -> int:
	if position.x<0 or position.y<0 or position.x>=int(state["width"]) or position.y>=int(state["width"]): return -1
	var enemy: Dictionary = world._agent(roundi(position.x),roundi(position.y),false)
	enemy["kind"]=kind
	enemy["race"]="Champion" if kind=="champion" else "NakedRace"
	enemy["home_x"]=position.x
	enemy["home_z"]=position.y
	enemy["stamina"]=1.0
	enemy["cooldown"]=0
	enemy["health"]=float(definition.get("races",{}).get("Champion",{}).get("MaxHealth",100))
	enemy["scale"]=float(definition.get("races",{}).get("Champion",{}).get("Scale",1.2))
	state["enemies"].append(enemy)
	return int(enemy["id"])


func agents_near(position: Vector2, radius: float, include_enemies: bool = true) -> Array:
	var found: Array = []
	for list: Array in [state["followers"],state["enemies"] if include_enemies else []]:
		for agent: Dictionary in list:
			if Vector2(agent["x"],agent["z"]).distance_to(position)<=radius: found.append(agent)
	return found


func agent_by_id(id: Variant) -> Dictionary:
	if not (id is float or id is int): return {}
	for list: Array in [state["followers"],state["enemies"]]:
		for agent: Dictionary in list:
			if int(agent["id"])==int(id): return agent
	return {}


func change_field(field: String, center: Vector2, radius: float, value: int) -> void:
	var width := int(state["width"])
	for z in range(maxi(0,floori(center.y-radius)),mini(width,ceili(center.y+radius)+1)):
		for x in range(maxi(0,floori(center.x-radius)),mini(width,ceili(center.x+radius)+1)):
			if center.distance_squared_to(Vector2(x,z))<=radius*radius: voyage[field][z*width+x]=value
	voyage["land_revision"]+=1
	state["terrain_revision"]+=1


func cast(power: String, center: Vector2, strength: float = 1.0) -> void:
	var config: Dictionary = voyage["config"]
	match power:
		"GodPower_Beautify","GodPower_RainOfPurity":
			var radius := float(config.get("BEAUTIFY_RADIUS",2.5))
			change_field("blight",center,radius,0)
			change_field("swamp",center,radius,0)
			change_field("beauty",center,radius,255)
		"GodPower_Swamp": change_field("swamp",center,float(config.get("SwampPudSize",2)),255)
		"GodPower_FingerOfGod":
			for enemy: Dictionary in state["enemies"]:
				if Vector2(enemy["x"],enemy["z"]).distance_to(center)<=1.0+float(config.get("ChampionFingerRadiusAddition",0.6)):
					enemy["stamina"]=0.0
					enemy["state"]="resting"
		"GodPower_PlaceSpeed":
			var temple := {"type":"Monument_Speed","uid":int(state["next_id"]),"x":center.x,"z":center.y,"complete":true,"progress":0,"build_seconds":0,"rotation":0.0,"model":"shrine","symbol":"speed","radius":10.0}
			state["next_id"]+=1
			voyage["temples"].append(temple)
			hook("onTemplePlaced",[temple["uid"]])
		"GodPower_MeteorStrike","GodPower_Comet":
			var radius := float(config.get("MeteorMaxBlastDistance",5))
			var width := int(state["width"])
			for z in range(maxi(1,floori(center.y-radius)),mini(width-1,ceili(center.y+radius)+1)):
				for x in range(maxi(1,floori(center.x-radius)),mini(width-1,ceili(center.x+radius)+1)):
					var distance := center.distance_to(Vector2(x,z))
					if distance>radius: continue
					var cell := z*width+x
					var old := int(state["terrain"][cell])
					state["terrain"][cell]=maxi(0,old-maxi(1,roundi((1-distance/radius)*float(config.get("MeteorChunkSinkDistance",3)))))
					if old>0 and state["terrain"][cell]==0: world._dry_land-=1
					voyage["blight"][cell]=maxi(int(voyage["blight"][cell]),roundi(float(config.get("MeteorBlightAmount",10))*2.55))
			state["terrain_revision"]+=1
			world._recover_agents()
			for agent: Dictionary in agents_near(center,radius): agent["health"]-=float(config.get("MeteorDamageMultiplier",10))*strength
			events.append({"type":"voyage_meteor","x":center.x,"z":center.y,"message":""})
		_:
			voyage["script_error"]="Unimplemented source power: "+power


func apply_api(name: String, args: Array) -> Variant:
	match name:
		"Config":
			if args.size()>1: voyage["config"][str(args[0])]=args[1]
			return null
		"GetConfig": return voyage["config"].get(str(args[0]),0)
		"GetMissionDifficulty": return int(definition.get("difficulty",0))
		"GetCurrentMission": return definition["id"]
		"GetRareStickerIndex": return int(args[0]) if not args.is_empty() else 0
		"GetMissionTimeRemaining": return maxf(0,float(definition["seconds"])-int(voyage["elapsed"])*0.1)
		"Random": return world._random.randf_range(float(args[0]),float(args[1])) if args.size()>1 else world._random.randf()
		"Persist":
			if args.size()>1: voyage["persistent"][str(args[0])]=args[1]
			return voyage["persistent"].get(str(args[0]),0)
		"Belief":
			if not args.is_empty(): state["belief"]=maxi(0,int(args[0]))
			return state["belief"]
		"After","NonPausingAfter":
			if args.size()>1:
				voyage["scheduled"].append({"tick":int(voyage["elapsed"])+maxi(1,roundi(float(args[0])*10)),"callback":args[1],"args":args.slice(2)})
			return null
		"SpawnThing": return spawn_enemy(str(args[0]),point(args[1],args[2]))
		"SpawnFollower":
			var position := point(args[1],args[2])
			var agent: Dictionary = world._agent(roundi(position.x),roundi(position.y),false)
			state["followers"].append(agent)
			return agent["id"]
		"FollowerInRadius","GetFirstFollowerInRadius":
			var found := agents_near(point(args[0],args[1]),float(args[2]))
			return not found.is_empty() if name=="FollowerInRadius" else (found[0]["id"] if not found.is_empty() else -1)
		"FollowerStamina": return float(agent_by_id(args[0]).get("stamina",0))
		"TempleUID": return args[0] if not args.is_empty() else -1
		"GetFirstTempleInRadius":
			var position := point(args[0],args[1])
			for temple: Dictionary in voyage["temples"]:
				if Vector2(temple["x"],temple["z"]).distance_to(position)<=float(args[2]): return temple["uid"]
			return -1
		"TempleDeconstruct":
			for temple: Dictionary in voyage["temples"]:
				if int(temple["uid"])==int(args[0]): temple["deconstructed"]=true
			return null
		"OverrideInfluenceArea":
			for area: Dictionary in voyage["areas"]:
				if area["name"]==str(args[0]): area["enabled"]=not area["enabled"]
			voyage["land_revision"]+=1
			state["terrain_revision"]+=1
			return null
		"OverrideGodPowerLock":
			var power := str(args[0])
			if power in voyage["powers"]: voyage["powers"].erase(power)
			else: voyage["powers"].append(power)
			return null
		"PlaceSwamp":
			change_field("swamp",point(args[0],args[1]),float(args[3]),255)
			return null
		"PutSwampsOnBlight":
			var start := point(args[0],args[1])
			var width := int(state["width"])
			for z in range(maxi(0,int(start.y)),mini(width,int(start.y)+int(args[3]))):
				for x in range(maxi(0,int(start.x)),mini(width,int(start.x)+int(args[2]))):
					if int(voyage["blight"][z*width+x])>roundi(float(voyage["config"].get("SWAMP_BLIGHT_MIN_THRESH",0.2))*255): voyage["swamp"][z*width+x]=255
			voyage["land_revision"]+=1
			state["terrain_revision"]+=1
			return null
		"CastPower":
			cast(str(args[2]),point(args[0],args[1]),float(args[5]) if args.size()>5 else 1.0)
			return null
		"IsValidPath":
			var start := point(args[0],args[1])
			var goal := point(args[2],args[3])
			return not world._route(Vector2i(start),Vector2i(goal)).is_empty()
		"IsRadiusFlat":
			var center := point(args[0],args[1])
			var height: int = world.height_at(roundi(center.x),roundi(center.y))
			for z in range(-ceili(float(args[2])),ceili(float(args[2]))+1):
				for x in range(-ceili(float(args[2])),ceili(float(args[2]))+1):
					if Vector2(x,z).length()<=float(args[2]) and world.height_at(roundi(center.x)+x,roundi(center.y)+z)!=height: return false
			return true
		"KillAllFollowerInRadius":
			for agent: Dictionary in agents_near(point(args[0],args[1]),float(args[2])): agent["health"]=0.0
			return null
		"ProcessFollowersInRadius":
			for agent: Dictionary in agents_near(point(args[0],args[1]),float(args[2])): vm.invoke(args[3],[agent["id"]])
			return null
		"TriggerAlert","TriggerTip3D","TriggerTip2D","TriggerTipGameObject","TriggerTipGUI":
			for argument: Variant in args:
				if argument is String and str(argument).begins_with("LOC_"):
					var message: String = definition.get("texts",{}).get(argument,"")
					if not message.is_empty(): events.append({"type":"voyage_alert","message":message})
					break
			voyage["tip_id"]+=1
			return voyage["tip_id"]
		"CenterScreen": return source_point(Vector2(definition["dock"][0],definition["dock"][1]))
		# These source APIs only direct presentation, telemetry or tutorial hints.
		# They do not decide movement, combat, topology, resources or progression.
		"Console","SetCamera","DebugSetCameraPos","SetCameraBaseRotation","UnlockCameraToRegion","LockCameraToRegion","TimeOfDay","TriggerVFX","DisplayRadius","ClearTip","ClearAlert","ClearAlertByID","ShowUI","ClearUI","SendAnalyticsWithStepName","LockActivity","CreateReaction","ArrowCreate","ArrowAddPoint","ArrowDestroy": return null
		_:
			if name in definition.get("program",{}).get("calls",[]): voyage["script_error"]="Unsupported source API: "+name
			else:
				# Several original scripts schedule a callback they never define.
				# As in a failed Lua callback, no challenge operation is invented.
				if not voyage.has("source_warnings"): voyage["source_warnings"]=[]
				if not name in voyage["source_warnings"]: voyage["source_warnings"].append(name)
	return null
