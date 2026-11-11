extends RefCounted
## Persistent source unlocks determine the authoritative actionable region.

const SourceInfluence = preload("res://simulation/source_influence.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")

static func refresh(state: Dictionary) -> void:
	var p: Dictionary = state["progression"]
	if not p["rules"].get("influence_enabled",true):
		p["influence_enabled"]=false
		p["influence"]=[]
		return
	p["influence_enabled"]=true
	if state.has("source_influence"):
		var current: Array=[]
		var definitions: Array=p["rules"]["influence_areas"]
		for index in range(definitions.size()):
			var radius := float(state["source_influence"]["radii"][index])
			if radius<=0: continue
			var active: Dictionary=definitions[index].duplicate(true)
			# Canonical public values keep a completed float32 radius equivalent
			# to the integer token used by a saved snapshot.
			active["radius"]=int(radius) if radius==int(radius) else radius
			active["powers_only"]=state["source_influence"]["powers_only"][index]
			current.append(active)
		if current!=p.get("influence",[]):
			p["influence"]=current
			p["influence_revision"]=int(p.get("influence_revision",0))+1
		return
	var thresholds := {}
	for row: Array in state["campaign"]["population_unlocks"]:
		if row.size()>1 and str(row[0]).is_valid_int() and state["followers"].size()>=int(row[0]): thresholds[int(row[0])]=true
	p["player_level"]=maxi(int(p.get("player_level",0)),thresholds.size())
	var enabled := {}
	for lock: String in p["rules"]["unlocks"]:
		var key: String = p["rules"]["unlocks"][lock]
		if key=="always" or key in p["discovered"] or (key.ends_with("_COMPLETED") and key.trim_suffix("_COMPLETED") in p["completed"]): enabled[lock]=true
		if key.begins_with("PLAYER_LEVEL_") and p["player_level"]>=int(key.trim_prefix("PLAYER_LEVEL_")): enabled[lock]=true
		if key.begins_with("TEMPLE_COMPLETE_"):
			for shrine: Dictionary in p["shrines"]:
				if shrine["complete"] and shrine["id"]==key.trim_prefix("TEMPLE_COMPLETE_"): enabled[lock]=true
	var areas: Array = []
	var source_campaign: bool=state.has("opening") and state["opening"]["definition"].has("influence_rules")
	var source_unlocks: bool = source_campaign or p["rules"].has("registered_scope")
	for area: Dictionary in p["rules"].get("influence_areas",[]):
		if area["force"] or (Unlocks.enabled(p,str(area["unlock"])) if source_unlocks else enabled.has(area["unlock"])):
			var active := area.duplicate(true)
			if source_campaign:
				for field: String in ["x","z","radius"]: active[field]=preload("res://simulation/source_terrain.gd").f32(float(active[field]))
			if source_unlocks and active.get("powers_only",false) and Unlocks.enabled(p,str(active.get("sculpt_unlock",""))):
				active["powers_only"]=false
			areas.append(active)
	if areas!=p.get("influence",[]):
		p["influence"]=areas
		p["influence_revision"]=int(p.get("influence_revision",0))+1


static func contains(state: Dictionary,x: float,z: float,power: bool=false) -> bool:
	if not state.has("progression") or not state["progression"].get("influence_enabled",false): return true
	if state.has("source_influence"):
		return preload("res://simulation/source_influence.gd").allows(state["source_influence"]["raster"],int(x),int(z),true,state["opening"]["definition"]["influence_rules"]) if x>=0 and z>=0 and x<1024 and z<1024 else false
	if state.has("opening") and state["opening"]["definition"].has("influence_rules"):
		if x<0 or z<0 or x>=1024 or z>=1024: return false
		var rules: Dictionary=state["opening"]["definition"]["influence_rules"]
		var maximum := 0
		for area: Dictionary in state["progression"]["influence"]:
			maximum=maxi(maximum,preload("res://simulation/source_influence.gd").circle_byte(float(area["x"]),float(area["z"]),float(area["radius"]),int(x),int(z),rules))
		return float(maximum)*float(rules["decode_scale"])>=float(rules["threshold"])
	var registered: Dictionary=state["progression"]["rules"].get("registered_influence_rules",{})
	if not registered.is_empty():
		if x<0 or z<0 or x>=state["width"] or z>=state["width"]: return false
		var own := 0
		var restricted := 0
		for area: Dictionary in state["progression"]["influence"]:
			var strength := SourceInfluence.circle_byte(area["x"],area["z"],area["radius"],int(x),int(z),registered)
			if area.get("powers_only",false): restricted=maxi(restricted,strength)
			else: own=maxi(own,strength)
		return SourceInfluence.allows_bytes(own,restricted,power,registered)
	for area: Dictionary in state["progression"]["influence"]:
		if Vector2(x,z).distance_squared_to(Vector2(area["x"],area["z"]))<=float(area["radius"])*float(area["radius"]): return true
	return false


static func command_allowed(state: Dictionary,command: Dictionary) -> bool:
	var p: Dictionary = state["progression"]
	match command.get("type",""):
		"open_chest":
			for item: Dictionary in p["chests"]:
				if item["id"]==command.get("id"): return contains(state,item["x"],item["z"])
		"repair_shrine":
			for item: Dictionary in p["shrines"]:
				if item["id"]==command.get("id"): return contains(state,item["x"],item["z"])
		"tap_object","tap_tree":
			if command.has("cell"):
				var cell := int(command["cell"])
				return contains(state,cell%int(state["width"]),cell/int(state["width"]))
			for item: Dictionary in p["objects"]:
				if item["id"]==command.get("id"): return contains(state,item["x"],item["z"])
		"upgrade_home":
			for item: Dictionary in state["homes"]:
				if item["id"]==int(command.get("id",-1)): return contains(state,item["x"],item["z"])
	if command.has("x") and command.has("z"): return contains(state,float(command["x"]),float(command["z"]),command.get("type")=="use_power")
	return true
