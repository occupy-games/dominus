extends RefCounted
## Homeworld6's timed Finger of God. A stroke owns its position until contact.

const POWER := "GodPower_FingerOfGod"
const CARD := "Card_Adv_FingerOfGod_1"
const ARM := "campaign_finger_arm"
const RELEASE := "campaign_finger_release"
const CANCEL := "campaign_finger_cancel"
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Influence = preload("res://simulation/influence.gd")
const Rocks = preload("res://simulation/authored_rocks.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const COST_KINDS := ["home","settlement","tree","rock","follower","flick"]
const TICK_SECONDS := 0.1


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get("finger_of_god",{})


static func handles(command: Dictionary) -> bool:
	return command.get("type") in [ARM,RELEASE,CANCEL] or command.get("type")=="use_power" and command.get("power")==POWER


static func price(state: Dictionary,kind: String) -> int:
	var rules := rules_for(state)
	var config: Dictionary=state["progression"]["rules"]["config"]
	return int(float(config.get(rules["cost_keys"][kind],rules["costs"][kind])))


static func minimum(state: Dictionary) -> int:
	return mini(mini(price(state,"home"),price(state,"follower")),mini(price(state,"tree"),price(state,"rock")))


static func status(state: Dictionary) -> Dictionary:
	if rules_for(state).is_empty(): return {}
	var cast: Dictionary=state["opening"].get("finger_cast",{})
	var threshold := minimum(state)
	return {"minimum":threshold,"affordable":state["belief"]>=threshold,
		"active":not cast.is_empty(),"remaining_ticks":maxi(0,int(cast.get("until",0))-int(state["tick"]))}


static func inspect(state: Dictionary,command: Dictionary) -> Dictionary:
	var reject := {"ok":false,"cost":0,"reason":""}
	var rules := rules_for(state)
	if rules.is_empty() or not Unlocks.enabled(state["progression"],POWER): return reject
	var cast: Dictionary=state["opening"].get("finger_cast",{})
	match command["type"]:
		ARM:
			return {"ok":cast.is_empty() and state["belief"]>=maxi(minimum(state),rules["activation_cost"]),
				"cost":int(rules["activation_cost"]),"reason":""}
		CANCEL:
			return {"ok":not cast.is_empty(),"cost":0,"reason":""}
		RELEASE:
			return {"ok":cast.get("pressed",false),"cost":0,"reason":""}
	if cast.get("phase")!="rest" or int(state["tick"])>=int(cast["until"]): return reject
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	if not coordinate(x,state["width"]) or not coordinate(z,state["width"]): return reject
	x=Terrain.f32(float(x))
	z=Terrain.f32(float(z))
	if not coordinate(x,state["width"]) or not coordinate(z,state["width"]) or not Influence.contains(state,x,z,true): return reject
	return {"ok":true,"cost":0,"reason":"","x":x,"z":z}


static func apply(world: RefCounted,state: Dictionary,kind: String,plan: Dictionary,events: Array) -> void:
	var opening: Dictionary=state["opening"]
	var cast: Dictionary=opening.get("finger_cast",{})
	match kind:
		ARM:
			var duration := float(state["progression"]["rules"]["config"].get("FingerOfGodLength",rules_for(state)["duration"]))
			opening["finger_cast"]={"until":int(state["tick"])+maxi(1,roundi(duration/TICK_SECONDS)),"phase":"rest","pressed":false}
		CANCEL:
			stop(opening,events)
		RELEASE:
			cast["pressed"]=false
			if cast["phase"]=="contact":
				cast["phase"]="rising"
				cast["rise_until"]=int(state["tick"])+1
		"use_power":
			var ground := Terrain.surface_height(world.source_raw_height_at(plan["x"],plan["z"]))-float(rules_for(state)["sea_height"])
			cast.merge({"phase":"descending","pressed":true,"impact_tick":int(state["tick"])+1,
				"x":plan["x"],"z":plan["z"],"ground":maxf(ground,0.0)},true)
			events.append({"type":"campaign_finger_down","x":cast["x"],"z":cast["z"],"ground":cast["ground"]})


static func advance(state: Dictionary,tick: int,events: Array) -> Dictionary:
	var opening: Dictionary=state["opening"]
	var cast: Dictionary=opening.get("finger_cast",{})
	if cast.is_empty(): return {}
	if cast["phase"]=="descending" and tick==int(cast["impact_tick"]):
		cast["phase"]="contact" if cast["pressed"] else "rising"
		if cast["phase"]=="rising": cast["rise_until"]=tick+1
		return {"x":cast["x"],"z":cast["z"]}
	if tick>=int(cast["until"]) or state["belief"]<minimum(state):
		stop(opening,events)
	elif cast["phase"]=="rising" and tick>=int(cast["rise_until"]):
		for key: String in ["x","z","ground","impact_tick","rise_until"]: cast.erase(key)
		cast["phase"]="rest"
	return {}


static func stop(opening: Dictionary,events: Array) -> void:
	if opening.erase("finger_cast"): events.append({"type":"campaign_finger_ended"})


static func contact(world: RefCounted,state: Dictionary,point: Vector2,rock_tiles: Dictionary,events: Array) -> void:
	if not Influence.contains(state,point.x,point.y,true): return
	var rules := rules_for(state)
	var radius: float=rules["radius"]
	var tick := int(state["tick"])+1
	var hit := false
	var opening: Dictionary=state["opening"]
	var exposed: Array=state["followers"].filter(func(follower: Dictionary) -> bool: return follower["state"]!="indoors")
	exposed.append_array(state.get("enemies",[]))
	exposed.append_array(state.get("astari_village",{}).get("performers",[]))
	for home: Dictionary in state["homes"].duplicate():
		if not home.get("kind","") in ["","farm","mine"] or not hits_abode(home,point,radius) or not state["homes"].has(home): continue
		if not Influence.contains(state,home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]),true): continue
		var kind := "settlement" if home.get("settlement_core",false) else "home"
		if not pay(state,kind,events): continue
		hit=true
		if kind=="settlement" and not repeated_hit(opening,"finger_settlement_hit",home["id"],tick,rules,"settlement"):
			continue
		if home["residents"]>0 and home["progress"]>=home["build_ticks"] and home.get("kind","")=="":
			happiness(state,kind,int(home.get("allegiance",0)))
		world.destroy_source_abode(home)
		events.append({"type":"campaign_finger_destroyed","target":kind,"id":home["id"]})
	for prop: Dictionary in state["props"].duplicate():
		if prop.get("kind")!="fountain": continue
		var fountain: Dictionary=opening["definition"]["fountain"]
		var area := Rect2(Vector2(prop["x"],prop["z"]),Vector2(fountain["width"],fountain["depth"]))
		if not area.grow(radius).has_point(point) or not pay(state,"home",events): continue
		if repeated_hit(opening,"finger_monument_hit",prop["id"],tick,rules,"monument"):
			happiness(state,"gift",0)
			world.destroy_finger_fountain(prop)
			events.append({"type":"campaign_finger_destroyed","target":"gift","id":prop["id"]})
			hit=true
		break
	var width: int=state["width"]
	var struck_rocks := {}
	for z in range(maxi(0,floori(point.y-radius)),mini(width,ceili(point.y+radius)+1)):
		for x in range(maxi(0,floori(point.x-radius)),mini(width,ceili(point.x+radius)+1)):
			var cell := z*width+x
			var tree: Dictionary=world.source_tree_at_cell(cell)
			if not tree.is_empty() and point.distance_squared_to(Vector2(tree["x"],tree["z"]))<=radius*radius:
				hit=ignite_tree(state,tree,tick,events) or hit
			var rock := Rocks.at(state,cell)
			if rock.is_empty(): continue
			var root := Rocks.cell(state,rock)
			if struck_rocks.has(root) or not Rocks.alive(state,root) or not Influence.contains(state,rock["x"],rock["z"],true): continue
			if point.distance_squared_to(Vector2(rock["x"],rock["z"]))>pow(radius+0.5,2): continue
			struck_rocks[root]=true
			if not pay(state,"rock",events): continue
			world.break_finger_rock(root,rock,rock_tiles,events)
			hit=true
	for follower: Dictionary in exposed:
		if follower.has("ark_passenger") or follower.get("health",0)<=0 or follower.has("sacrifice_due"): continue
		if point.distance_squared_to(Vector2(follower["x"],follower["z"]))>radius*radius: continue
		if not Influence.contains(state,follower["x"],follower["z"],true) or not pay(state,"follower",events): continue
		happiness(state,"follower",int(follower.get("allegiance",0)))
		if follower.get("kind")=="astari_archer": state["enemies"].erase(follower)
		elif follower.get("allegiance",0)==1: world.remove_astari_performer(follower)
		else: world.remove_follower(follower)
		events.append({"type":"campaign_finger_destroyed","target":"follower","id":follower["id"]})
		hit=true
	if hit: events.append({"type":"source_sound","event":rules["sound"]})
	events.append({"type":"campaign_finger_contact","x":point.x,"z":point.y,"hit":hit})


static func hits_abode(home: Dictionary,point: Vector2,radius: float) -> bool:
	var anchor := Vector2(home["x"],home["z"])-Vector2.ONE*0.5
	var end := anchor+Vector2.ONE*float(home.get("span",2))
	return point.distance_squared_to(point.clamp(anchor,end))<=radius*radius


static func pay(state: Dictionary,kind: String,events: Array) -> bool:
	var cost := price(state,kind)
	if state["belief"]<cost: return false
	state["belief"]-=cost
	events.append({"type":"campaign_finger_paid","target":kind,"belief":cost})
	return true


static func repeated_hit(opening: Dictionary,key: String,id: int,tick: int,rules: Dictionary,kind: String) -> bool:
	var prior: Dictionary=opening.get(key,{})
	var repeat: bool=prior.get("id")==id and (tick-int(prior["tick"]))*TICK_SECONDS<float(rules[kind+"_reset"])
	var count := int(prior.get("count",0))+1 if repeat else 1
	if count>=int(rules[kind+"_taps"]):
		opening.erase(key)
		return true
	opening[key]={"id":id,"tick":tick,"count":count}
	return false


static func happiness(state: Dictionary,kind: String,tribe: int) -> void:
	if not Unlocks.enabled(state["progression"],"Happiness"): return
	tribe=clampi(tribe,0,1)
	var values: Dictionary=state["progression"]["happiness"]
	var name: String=["player","astari"][tribe]
	var rules := rules_for(state)
	var floor_value := -1.0 if tribe==1 and state.has("astari_village") else 0.0
	values[name]=clampf(float(values[name])+Terrain.f32(float(rules["happiness"][kind][tribe])*float(rules["happiness_multiplier"])),floor_value,1.0)


static func ignite_tree(state: Dictionary,tree: Dictionary,tick: int,events: Array) -> bool:
	var opening: Dictionary=state["opening"]
	if not opening.has("finger_fires"): opening["finger_fires"]={}
	var key := str(int(tree["cell"]))
	if opening["finger_fires"].has(key) or opening.get("finger_burned",{}).has(key) or not Influence.contains(state,tree["x"],tree["z"],true) or not pay(state,"tree",events): return false
	var burn_ticks := ceili(1.0/(float(rules_for(state)["burn_rate"])*TICK_SECONDS))
	opening["finger_fires"][key]=tick+burn_ticks
	var point := Vector2(tree["x"],tree["z"])
	var near := false
	var tribe := 0
	for home: Dictionary in state["homes"]:
		if home.get("kind","")!="" or not home.has("vision_radius"): continue
		var center := Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"]))
		if point.distance_squared_to(center)>pow(float(home["vision_radius"]),2): continue
		near=true
		tribe=int(home.get("allegiance",0))
		break
	happiness(state,"tree_near" if near else "tree_far",tribe)
	events.append({"type":"campaign_finger_ignited","cell":tree["cell"]})
	return true


static func valid_rules(value: Variant) -> bool:
	if not value is Dictionary or value.get("power")!=POWER or value.get("card")!=CARD: return false
	if not integer(value.get("population"),1,8192) or not integer(value.get("activation_cost"),0,1000000): return false
	for key: String in ["duration","radius","settlement_reset","monument_reset","rock_raise_radius","rock_raise_height","burn_rate",
			"rest_height","hover_height","sea_height","acceleration","max_velocity","model_scale","surface_offset"]:
		if not number(value.get(key),0.000001,1000.0): return false
	for key: String in ["rotation_z","rotation_x","target_offset_x","target_offset_z","happiness_multiplier","rock_raise_threshold"]:
		if not number(value.get(key),-1000.0,1000.0): return false
	for key: String in ["burn_tint","burn_imposter_scale"]:
		if not number(value.get(key),0,1): return false
	for key: String in ["settlement_taps","monument_taps"]:
		if not integer(value.get(key),1,100): return false
	if not value.get("costs") is Dictionary or not value.get("cost_keys") is Dictionary or not value.get("happiness") is Dictionary: return false
	for kind: String in COST_KINDS:
		if not integer(value["costs"].get(kind),0,1000000) or not value["cost_keys"].get(kind) is String: return false
	for key: String in ["home","settlement","gift","follower","flick","tree_near","tree_far"]:
		var pair: Variant=value["happiness"].get(key)
		if not pair is Array or pair.size()!=2 or not number(pair[0],-1,1) or not number(pair[1],-1,1): return false
	return value.get("model")=="god_finger.group.bin:280f48d9" and value.get("sound")=="Finger of God impact"


static func valid_state(state: Dictionary) -> bool:
	var opening: Dictionary=state["opening"]
	var tick: int=state["tick"]
	var width: int=state["width"]
	var cast: Variant=opening.get("finger_cast",{})
	if not cast is Dictionary: return false
	var has_state: bool=not cast.is_empty() or opening.has("finger_settlement_hit") or opening.has("finger_monument_hit") or opening.has("finger_fires") or opening.has("finger_burned")
	if has_state and rules_for(state).is_empty(): return false
	if not cast.is_empty():
		if not integer(cast.get("until"),tick,tick+10000000000000) or not cast.get("pressed") is bool: return false
		if not cast.get("phase") in ["rest","descending","contact","rising"]: return false
		if cast["phase"]!="rest":
			if not coordinate(cast.get("x"),width) or not coordinate(cast.get("z"),width) or not number(cast.get("ground"),0,1000): return false
			if not integer(cast.get("impact_tick"),0,tick+1): return false
		if cast["phase"]=="rising" and not integer(cast.get("rise_until"),tick,tick+1): return false
	for key: String in ["finger_settlement_hit","finger_monument_hit"]:
		if not opening.has(key): continue
		var hit: Variant=opening[key]
		if not hit is Dictionary or not integer(hit.get("id"),1,state["next_id"]-1) or not integer(hit.get("tick"),0,tick) or not integer(hit.get("count"),1,99): return false
	var fires: Variant=opening.get("finger_fires",{})
	if not fires is Dictionary or fires.size()>65536: return false
	for key: Variant in fires:
		if not key is String or not key.is_valid_int() or not integer(int(key),0,width*width-1) or not integer(fires[key],tick+1,tick+10000000): return false
	var burned: Variant=opening.get("finger_burned",{})
	if not burned is Dictionary or burned.size()>65536: return false
	for key: Variant in burned:
		if not key is String or not key.is_valid_int() or not integer(int(key),0,width*width-1) or burned[key]!=true or fires.has(key): return false
	return true


static func integer(value: Variant,lower: int,upper: int) -> bool:
	return number(value,lower,upper) and value==int(value)


static func coordinate(value: Variant,width: int) -> bool:
	return number(value,0,width) and value<width


static func number(value: Variant,lower: float,upper: float) -> bool:
	return (value is float or value is int) and is_finite(value) and value>=lower and value<=upper
