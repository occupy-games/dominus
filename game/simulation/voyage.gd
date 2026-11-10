extends RefCounted
## Original expedition scripts, hazards, shrines, powers and fixed-tick outcomes.

const Challenges = preload("res://simulation/voyage_challenges.gd")


static func initialize(definition: Dictionary, width: int = 0, blight: PackedByteArray = PackedByteArray()) -> Dictionary:
	var field := PackedByteArray()
	field.resize(width*width)
	var result := {"definition":definition.duplicate(true),"phase":"ready","elapsed":0,
		"aboard":0,"launched":0,"rescued":0,"dead":0,"score":0,"stars":0,
		"config":definition.get("config",{}).duplicate(true),"globals":{},"persistent":{},
		"scheduled":[],"tip_id":0,"script_error":"","land_revision":0,
		"blight":blight.duplicate() if blight.size()==field.size() else field.duplicate(),
		"swamp":field.duplicate(),"beauty":field.duplicate(),"temples":[],"areas":definition.get("areas",[]).duplicate(true),
		"powers":[],"chests":[],"target_uid":-1}
	for temple: Dictionary in definition.get("temples",[]):
		var item := temple.duplicate(true)
		item["complete"]=item["type"]=="Expedition_Goal" or (item["type"]=="Monument_Speed" and float(item.get("build_seconds",0))<=0)
		item["progress"]=0.0
		result["temples"].append(item)
	for power: String in definition.get("unlocks",{}):
		if power.begins_with("GodPower_") and definition["unlocks"][power]=="always": result["powers"].append(power)
	return result


static func setup(world: RefCounted, state: Dictionary) -> void:
	state["enemies"]=[]
	var host := Challenges.new()
	host.configure(world,state,[])
	host.prepare()


static func influence_contains(state: Dictionary, x: float, z: float) -> bool:
	var voyage: Dictionary = state["voyage"]
	if not voyage.get("areas",[]).is_empty():
		var inside := false
		for area: Dictionary in voyage["areas"]:
			if area["enabled"] and Vector2(x,z).distance_to(Vector2(area["x"],area["z"]))<=float(area["radius"]): inside=true; break
		if not inside: return false
	return x>=0 and z>=0 and x<int(state["width"]) and z<int(state["width"])


static func can_act_at(state: Dictionary, x: float, z: float) -> bool:
	if not influence_contains(state,x,z): return false
	var voyage: Dictionary = state["voyage"]
	var radius := float(voyage.get("config",{}).get("EnemyFollowerCheckWidth",0))
	for enemy: Dictionary in state.get("enemies",[]):
		if float(enemy.get("stamina",1))>0 and absf(x-float(enemy["x"]))<=radius and absf(z-float(enemy["z"]))<=radius: return false
	return true


static func inspect(state: Dictionary, command: Dictionary) -> Dictionary:
	var voyage: Dictionary = state["voyage"]
	var definition: Dictionary = voyage["definition"]
	var kind := str(command.get("type",""))
	if kind=="start_voyage":
		var count := int(command.get("followers",definition["minimum"]))
		return {"ok":voyage["phase"]=="ready" and count>=int(definition["minimum"]) and count<=int(definition["maximum"]),"cost":0,"reason":"Set sail"}
	if voyage["phase"]!="running": return {"ok":false,"cost":0,"reason":"Set sail first." if voyage["phase"]=="ready" else "This voyage has ended."}
	if kind=="voyage_power":
		var power := str(command.get("power",""))
		var cost := ceili(float(definition.get("power_data",{}).get(power,{}).get("cost",0)))
		return {"ok":power in voyage["powers"] and state["belief"]>=cost and influence_contains(state,float(command.get("x",-1)),float(command.get("z",-1))),"cost":cost,"reason":"Cast "+power.trim_prefix("GodPower_")}
	if kind=="voyage_temple":
		for temple: Dictionary in voyage["temples"]:
			if int(temple["uid"])==int(command.get("uid",-1)) and not temple["complete"]: return {"ok":true,"cost":0,"reason":"Guide followers to this shrine."}
		return {"ok":false,"cost":0,"reason":"This shrine is already complete."}
	if kind=="voyage_chest":
		for chest: Dictionary in voyage["chests"]:
			if int(chest["id"])==int(command.get("id",-1)) and not chest["opened"] and int(state["terrain"][roundi(chest["z"])*int(state["width"])+roundi(chest["x"])])<=int(chest["height"]): return {"ok":true,"cost":0,"reason":"Open chest."}
		return {"ok":false,"cost":0,"reason":"Uncover this chest first."}
	if not kind in ["sculpt_drag","raise","lower","dig"]: return {"ok":false,"cost":0,"reason":"Sculpt a route to the temple."}
	return {"ok":true}


static func start(state: Dictionary, count: int) -> void:
	state["voyage"]["phase"]="running"
	state["voyage"]["aboard"]=count


static func command(world: RefCounted, state: Dictionary, input: Dictionary, events: Array) -> void:
	var host := Challenges.new()
	host.configure(world,state,events)
	var voyage: Dictionary = state["voyage"]
	match input["type"]:
		"start_voyage":
			start(state,int(input.get("followers",voyage["definition"]["minimum"])))
			host.hook("onStartPlay",[0])
			host.hook("onEventMissionBegin",[0])
		"voyage_power":
			host.hook("onPowerSelected",[{"GodPower_PlaceSpeed":7,"GodPower_Beautify":8,"GodPower_FingerOfGod":10}.get(input["power"],0)])
			host.cast(input["power"],Vector2(input["x"],input["z"]))
		"voyage_temple":
			voyage["target_uid"]=int(input["uid"])
			for agent: Dictionary in state["followers"]: agent["voyage_revision"]=-1
		"voyage_chest":
			for chest: Dictionary in voyage["chests"]:
				if int(chest["id"])==int(input["id"]):
					chest["opened"]=true
					voyage["score"]+=roundi(float(voyage["config"].get("MissionScoreExpedChest",100)))
			host.hook("onChestOpened",[input["id"]])


static func record_result(previous: Dictionary, state: Dictionary) -> Dictionary:
	var result := previous.duplicate(true)
	if not state.has("voyage") or state["voyage"]["phase"]!="won": return result
	var voyage: Dictionary = state["voyage"]
	var id: String = voyage["definition"]["id"]
	if int(previous.get(id,{}).get("score",-1))>=int(voyage["score"]): return result
	result[id]={"stars":int(voyage["stars"]),"score":int(voyage["score"]),"rescued":int(voyage["rescued"])}
	return result


static func objective(world: RefCounted, state: Dictionary, agent: Dictionary) -> Dictionary:
	var voyage: Dictionary = state["voyage"]
	var start := Vector2i(roundi(agent["x"]),roundi(agent["z"]))
	var goal := {"x":voyage["definition"]["goal"][0],"z":voyage["definition"]["goal"][1],"uid":1000,"type":"Expedition_Goal"}
	var best := INF
	for temple: Dictionary in voyage["temples"]:
		if temple["type"]=="Expedition_Goal": goal=temple; continue
		if temple["complete"] or temple.get("deconstructed",false): continue
		var target := Vector2i(roundi(temple["x"]),roundi(temple["z"]))
		var distance := Vector2(start).distance_to(Vector2(target))
		if int(temple["uid"])==int(voyage["target_uid"]): distance=-1
		if distance<best and (start==target or not world._route(start,target).is_empty()): goal=temple; best=distance
	return goal


static func arrival_score(config: Dictionary, seconds: float, remaining: float) -> int:
	# godus.s86:100f44dc..100f453f: pow(remaining / limit, power) * limit,
	# multiply by time bonus, add one, multiply by base, truncate to integer.
	var fraction := float(PackedFloat32Array([remaining/maxf(0.1,seconds)])[0])
	var shaped := float(PackedFloat32Array([pow(fraction,float(config.get("MissionScoreFollowerTimePower",2)))*seconds])[0])
	var bonus := float(PackedFloat32Array([1.0+float(config.get("MissionScoreFollowerReachedTempleTimeMult",0.1))*shaped])[0])
	return floori(float(config.get("MissionScoreFollowerReachedTemple",1000))*bonus)


static func advance(world: RefCounted, state: Dictionary, events: Array) -> void:
	var voyage: Dictionary = state["voyage"]
	if voyage["phase"]!="running": return
	var definition: Dictionary = voyage["definition"]
	var host := Challenges.new()
	host.configure(world,state,events)
	var due: Array = []
	for job: Dictionary in voyage["scheduled"]:
		if int(job["tick"])<=int(voyage["elapsed"]): due.append(job)
	for job: Dictionary in due:
		voyage["scheduled"].erase(job)
		host.vm.invoke(job["callback"],job["args"])
	if not host.vm.error.is_empty(): voyage["script_error"]=host.vm.error
	var interval := maxi(1,roundi(float(definition["spawn_seconds"])/0.1))
	if int(voyage["elapsed"])%interval==0 and voyage["aboard"]>0:
		var agent: Dictionary = world._agent(int(definition["dock"][0]),int(definition["dock"][1]),false)
		agent["voyage_revision"]=-1
		agent["health"]=float(definition.get("races",{}).get("BrownHead",{}).get("MaxHealth",100))
		agent["stamina"]=1.0
		agent["scale"]=float(definition.get("races",{}).get("BrownHead",{}).get("Scale",1))
		state["followers"].append(agent)
		voyage["aboard"]-=1
		voyage["launched"]+=1
	var arrived: Array = []
	for agent: Dictionary in state["followers"]:
		var position := Vector2(agent["x"],agent["z"])
		var target: Dictionary = objective(world,state,agent)
		var goal := Vector2i(roundi(target["x"]),roundi(target["z"]))
		if position.distance_to(Vector2(goal))<0.15:
			if target["type"]=="Expedition_Goal": arrived.append(agent)
			else:
				agent["state"]="building"
				target["progress"]+=0.1
				if target["progress"]>=float(target.get("build_seconds",0)):
					target["complete"]=true
					host.hook("onTempleComplete",[target["uid"]])
					events.append({"type":"voyage_shrine","message":"Shrine restored.","uid":target["uid"]})
					state["terrain_revision"]+=1
			continue
		if agent.get("voyage_revision",-1)!=state["terrain_revision"] or agent.get("voyage_target",-1)!=target["uid"]:
			agent["path"]=world._route(Vector2i(roundi(position.x),roundi(position.y)),goal)
			agent["voyage_revision"]=state["terrain_revision"]
			agent["voyage_target"]=target["uid"]
			if not agent["path"].is_empty() and not voyage.get("found_path",false):
				voyage["found_path"]=true
				host.hook("onEventFollowerFoundPath",[agent["id"]])
		if agent["path"].is_empty(): agent["state"]="waiting"; continue
		var cell := int(agent["path"][0])
		var destination := Vector2(cell%int(state["width"]),cell/int(state["width"]))
		var speed := float(definition.get("races",{}).get("BrownHead",{}).get("RouteSpeed",definition["speed"]))
		for temple: Dictionary in voyage["temples"]:
			if temple["type"]=="Monument_Speed" and temple["complete"] and position.distance_to(Vector2(temple["x"],temple["z"]))<=float(temple.get("radius",10)): speed*=float(definition.get("temple_effects",{}).get("Monument_Speed",{}).get("multiplier",2)); break
		var field_cell := clampi(roundi(position.y)*int(state["width"])+roundi(position.x),0,state["terrain"].size()-1)
		if voyage["beauty"][field_cell]>0: speed*=float(definition.get("races",{}).get("BrownHead",{}).get("FullBeautifySpeedMult",1.25))
		var next := position.move_toward(destination,speed*0.1)
		agent["x"]=next.x
		agent["z"]=next.y
		agent["state"]="walking"
		if next.distance_to(destination)<0.001: agent["path"].pop_front()
	for agent: Dictionary in arrived:
		state["followers"].erase(agent)
		voyage["rescued"]+=1
		var remaining := maxf(0,float(definition["seconds"])-float(voyage["elapsed"])*0.1)
		voyage["score"]+=arrival_score(voyage["config"],float(definition["seconds"]),remaining)
	advance_hazards(world,state,host)
	var dead: Array = []
	for agent: Dictionary in state["followers"]:
		var cell := clampi(roundi(agent["z"])*int(state["width"])+roundi(agent["x"]),0,state["terrain"].size()-1)
		var stats: Dictionary = definition.get("races",{}).get("BrownHead",{})
		var damage := float(stats.get("SwampDamage",40)) if voyage["swamp"][cell]>0 else float(stats.get("BlightedDamage",1))*(int(voyage["blight"][cell])/255.0)
		agent["health"]-=damage*0.1
		if agent["health"]<=0: dead.append(agent)
	for agent: Dictionary in dead:
		state["followers"].erase(agent)
		voyage["dead"]+=1
		host.hook("onFollowerDied",[agent["id"]])
	voyage["elapsed"]+=1
	if float(voyage["elapsed"])*0.1>=float(definition["seconds"]) or (voyage["aboard"]==0 and state["followers"].is_empty()):
		var won: bool = voyage["rescued"]>=int(definition["required"])
		voyage["phase"]="won" if won else "lost"
		state["won"]=won
		if won: voyage["stars"]=3 if voyage["score"]>=float(voyage["config"].get("MissionStar3Score",definition["MissionStar3Score"])) else (2 if voyage["score"]>=float(voyage["config"].get("MissionStar2Score",definition["MissionStar2Score"])) else 1)
		host.hook("onEventMissionEnd",[1 if won else 0])
		events.append({"type":"victory" if won else "voyage_failed","message":"One Voyage Complete!" if won else "Time has run out."})


static func advance_hazards(world: RefCounted, state: Dictionary, host: RefCounted) -> void:
	var voyage: Dictionary = state["voyage"]
	var stats: Dictionary = voyage["definition"].get("races",{}).get("Champion",{})
	var dead: Array = []
	for enemy: Dictionary in state["enemies"]:
		if enemy["health"]<=0: dead.append(enemy); continue
		var position := Vector2(enemy["x"],enemy["z"])
		if float(enemy["stamina"])<1:
			enemy["stamina"]=minf(1,float(enemy["stamina"])+float(stats.get("StaminaGainSitting",0.04))*0.1)
			enemy["state"]="resting"
			continue
		var nearest := float(stats.get("Vision",7))
		var target := {}
		for agent: Dictionary in state["followers"]:
			var distance := position.distance_to(Vector2(agent["x"],agent["z"]))
			if distance<nearest: nearest=distance; target=agent
		if target.is_empty(): enemy["state"]="idle"; continue
		enemy["cooldown"]=maxi(0,int(enemy["cooldown"])-1)
		if nearest<1.2:
			enemy["state"]="attacking"
			if int(enemy["cooldown"])==0:
				target["health"]+=float(voyage["config"].get("championDamagePerPunch",-40))
				enemy["cooldown"]=10
				enemy["stamina"]=maxf(0,float(enemy["stamina"])-float(stats.get("StaminaDecay",0.005)))
		else:
			var start := Vector2i(roundi(position.x),roundi(position.y))
			var route: Array = world._route(start,Vector2i(roundi(target["x"]),roundi(target["z"])))
			if not route.is_empty():
				var cell := int(route[0])
				var next := position.move_toward(Vector2(cell%int(state["width"]),cell/int(state["width"])),float(stats.get("RouteSpeed",0.45))*0.1)
				enemy["x"]=next.x
				enemy["z"]=next.y
				enemy["state"]="walking"
	for enemy: Dictionary in dead: state["enemies"].erase(enemy)


static func valid(state: Dictionary) -> bool:
	var voyage: Variant = state.get("voyage")
	if not voyage is Dictionary or not voyage.get("definition") is Dictionary: return false
	if not voyage.get("phase") in ["ready","running","won","lost"]: return false
	for key: String in ["elapsed","aboard","launched","rescued","score","stars"]:
		var value: Variant = voyage.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<0 or value!=int(value): return false
	var definition: Dictionary = voyage["definition"]
	for key: String in ["seconds","spawn_seconds","speed","minimum","maximum","required","MissionStar2Score","MissionStar3Score","MissionScoreFollowerReachedTemple","MissionScoreFollowerReachedTempleTimeMult"]:
		var value: Variant = definition.get(key)
		if not (value is float or value is int) or not is_finite(value) or value<0: return false
	if definition["seconds"]<=0 or definition["spawn_seconds"]<=0 or definition["speed"]<=0 or definition["maximum"]>200 or definition["minimum"]<1 or definition["minimum"]>definition["maximum"]: return false
	if voyage["aboard"]+voyage["launched"]>definition["maximum"] or voyage["rescued"]>voyage["launched"] or voyage["stars"]>3: return false
	for key: String in ["dock","goal"]:
		if not definition.get(key) is Array or definition[key].size()!=2: return false
		for value: Variant in definition[key]:
			if not (value is int or value is float) or not is_finite(value) or value<0 or value>=int(state["width"]): return false
	return definition.get("id") is String
