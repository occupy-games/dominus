extends RefCounted
## Homeworld6 owns paid projectiles, their terrain impacts and blast damage.

const KEY := "meteor"
const POWER := "GodPower_MeteorStrike"
const CARD := "Card_Adv_MeteorStrike_1"
const UPGRADE := "campaign_meteor_upgrade"
const MAX_FLIGHTS := 15
const SUBSTEPS := 6
const Source = preload("res://simulation/source_meteor.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Influence = preload("res://simulation/influence.gd")
const Temple = preload("res://simulation/temple_rules.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get(KEY,{})


static func discover(state: Dictionary,events: Array) -> void:
	var rules:=rules_for(state)
	if rules.is_empty(): return
	var progression: Dictionary=state["progression"]
	if state["followers"].size()>=int(rules["population"]) and not CARD in progression["discovered"]:
		preload("res://simulation/progression.gd").discover(progression,CARD)
		if CARD in progression["discovered"]:
			events.append({"type":"card_discovered","card":CARD})
			events.append({"type":"campaign_autosave"})
	if Unlocks.enabled(progression,POWER) and not POWER in progression["powers"]:
		progression["powers"].append(POWER)
		progression["revision"]+=1


static func status(state: Dictionary) -> Dictionary:
	var rules:=rules_for(state)
	if rules.is_empty() or not Unlocks.enabled(state["progression"],POWER): return {}
	var result:={"belief":int(rules["belief"]),"affordable":int(state["belief"])>=int(rules["belief"]),"upgrades":[]}
	for upgrade: Dictionary in rules["upgrades"]:
		if Unlocks.enabled(state["progression"],upgrade["unlock"]): continue
		result["upgrades"].append({"next":upgrade.duplicate(true),"affordable":int(state.get("gems",0))>=int(upgrade["cost"])})
	return result


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	var rules:=rules_for(state)
	if rules.is_empty() or not Unlocks.enabled(state["progression"],POWER): return reject
	if command.get("type")==UPGRADE:
		for offer: Dictionary in status(state)["upgrades"]:
			var upgrade: Dictionary=offer["next"]
			if command.get("id")==upgrade["id"] and offer["affordable"]:
				return {"ok":true,"cost":0,"reason":"","resource_cost":{"gems":int(upgrade["cost"])},"upgrade":upgrade["id"]}
		return reject
	if not state.has("source_influence") or state["opening"].get("meteor_flights",[]).size()>=MAX_FLIGHTS: return reject
	var width: int=state["width"]
	if not number(command.get("x"),0,width-1) or not number(command.get("z"),0,width-1): return reject
	var x:=Terrain.f32(float(command["x"]))
	var z:=Terrain.f32(float(command["z"]))
	if x>=width-1 or z>=width-1 or not Influence.contains(state,x,z,true): return reject
	if not pair(command.get("viewport"),1.0,16384.0) or not pair(command.get("drag"),-16384.0,16384.0): return reject
	if not pair(command.get("heading"),-1.0,1.0) or not number(command.get("seconds"),0.0,86400.0): return reject
	var viewport:=Vector2(command["viewport"][0],command["viewport"][1])
	var delta:=Vector2(command["drag"][0],command["drag"][1])
	var heading:=Vector2(command["heading"][0],command["heading"][1])
	if heading.is_zero_approx() or absf(delta.x)>viewport.x or absf(delta.y)>viewport.y: return reject
	var quote:=Source.swipe(delta,viewport,float(command["seconds"]),rules)
	if quote.is_empty(): return reject
	var ground:=Terrain.surface_height(world.source_raw_height_at(x,z))
	return {"ok":int(state["belief"])>=int(rules["belief"]),"cost":int(rules["belief"]),"reason":"",
		"flight":Source.launch(Vector3(x,ground,z),heading,quote,rules)}


static func cast(state: Dictionary,plan: Dictionary,events: Array) -> void:
	var opening: Dictionary=state["opening"]
	if not opening.has("meteor_flights"): opening["meteor_flights"]=[]
	var flight: Dictionary=plan["flight"]
	flight["id"]=int(state["next_id"])
	state["next_id"]+=1
	opening["meteor_flights"].append(flight)
	events.append({"type":"source_sound","event":"Meteor Strike launch","meteor_id":flight["id"]})


static func advance(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,tick_seconds: float,rock_tiles: Dictionary,events: Array) -> void:
	var opening: Dictionary=state["opening"]
	var flights: Array=opening.get("meteor_flights",[])
	if flights.is_empty(): return
	var rules:=rules_for(state)
	var ground := func(x: float,z: float) -> float: return Terrain.surface_height(world.source_raw_height_at(x,z))
	var delta:=tick_seconds/SUBSTEPS
	for flight: Dictionary in flights.duplicate():
		for _frame in range(SUBSTEPS):
			var result:=Source.advance(flight,ground,delta,rules)
			if result.has("impact"):
				impact(world,state,flight,result,rules,rock_tiles,events)
			elif result.has("splash"):
				events.append({"type":"source_sound","event":"PLAYSOUND_METEORIMPACTWATER","meteor_id":flight["id"]})
			elif result.has("trail"):
				crater(world,state,result["trail"],1.0,0.0,float(rules["water_trail_radius"]),1.0,rules,rock_tiles)
			if result.has("wave"):
				wave(world,state,random,flight,float(result["wave"]),rules,events)
			if result.get("finished",false):
				flights.erase(flight)
				break
	if flights.is_empty(): opening.erase("meteor_flights")


static func impact(world: RefCounted,state: Dictionary,flight: Dictionary,result: Dictionary,rules: Dictionary,rock_tiles: Dictionary,events: Array) -> void:
	var target: Vector3=result["impact"]
	var position: Vector3=result["position"]
	var strength: float=flight["strength"]
	var effects:={"crater_radius":rules["crater_radius"],"crater_depth":rules["crater_depth"],"blight":rules["blight"]}
	for upgrade: Dictionary in rules["upgrades"]:
		if not Unlocks.enabled(state["progression"],upgrade["unlock"]): continue
		for key: String in effects:
			effects[key]=Terrain.f32(float(effects[key])*float(upgrade["multipliers"][key]))
	var radius:=Terrain.f32(float(effects["crater_radius"])*float(rules["radius_scale"])*strength)
	var depth:=Terrain.f32(float(effects["crater_depth"])*float(rules["depth_scale"])*strength)
	var blight_radius:=Terrain.f32(strength*float(effects["blight"])*float(rules["blight_radius_scale"]))
	damage_abodes(world,state,position,rules,events)
	crater(world,state,target,radius,depth,blight_radius,float(effects["blight"]),rules,rock_tiles)
	events.append({"type":"campaign_meteor_impact","x":target.x,"z":target.z,"y":target.y})
	events.append({"type":"source_sound","event":"Meteor Strike impact","meteor_id":flight["id"]})


static func crater(world: RefCounted,state: Dictionary,point: Vector3,radius: float,depth: float,blight_radius: float,blight: float,rules: Dictionary,rock_tiles: Dictionary) -> void:
	var width: int=state["width"]
	if point.x<0.0 or point.z<0.0 or point.x>=width or point.z>=width: return
	var raster: Dictionary=state["source_influence"]["raster"]
	var foundations: Array[Rect2i]=[]
	for site: Dictionary in state["progression"]["shrines"]:
		var footprint:=Temple.footprint(site)
		if Rect2(footprint).grow(radius).has_point(Vector2(point.x,point.z)): foundations.append(footprint)
	var minimum:=func(x: int,z: int) -> int:
		for footprint: Rect2i in foundations:
			if footprint.has_point(Vector2i(x,z)): return world.source_raw_vertex(x,z)
		return 0
	var edits:=Source.crater(point,radius,depth,width,rules,world.source_raw_vertex,minimum)
	world.apply_layer_edits(edits,rock_tiles,false)
	Source.write_fields(raster,point,blight_radius,blight,width)


static func damage_abodes(world: RefCounted,state: Dictionary,point: Vector3,rules: Dictionary,events: Array) -> void:
	var radius: float=rules["house_radius"]
	for home: Dictionary in state["homes"].duplicate():
		if not home.get("kind","") in ["","farm","mine"] or not state["homes"].has(home): continue
		var offset:=(float(home.get("span",2))-1.0)*0.5
		var center:=Vector2(home.get("anchor_x",home["x"]+offset),home.get("anchor_z",home["z"]+offset))
		if center.distance_squared_to(Vector2(point.x,point.z))>=radius*radius: continue
		var height:=Terrain.surface_height(int(home.get("height",world.source_raw_height_at(center.x,center.y)-19))+19)
		if point.y-height>=float(rules["destruction_height"]): continue
		if home.get("settlement_core",false) and not settlement_hit(state["opening"],home["id"],state["tick"],rules): continue
		world.destroy_source_abode(home)
		events.append({"type":"campaign_meteor_destroyed","id":home["id"]})


static func settlement_hit(opening: Dictionary,id: int,tick: int,rules: Dictionary) -> bool:
	var prior: Dictionary=opening.get("meteor_settlement_hit",{})
	var count:=1
	if prior.get("id")==id and (tick-int(prior["tick"]))*0.1<float(rules["settlement_reset"]): count+=int(prior["count"])
	opening["meteor_settlement_hit"]={"id":id,"tick":tick,"count":count}
	return count>=int(rules["settlement_taps"])


static func wave(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,flight: Dictionary,radius: float,rules: Dictionary,events: Array) -> void:
	var pos:=Source.vector(flight["position"])
	var groups: Array=[state["followers"],state.get("enemies",[]),state.get("astari_village",{}).get("performers",[])]
	for index in range(groups.size()):
		for actor: Dictionary in groups[index].duplicate():
			if actor.get("state")=="indoors" or actor.has("ark_passenger") or actor.has("sacrifice_due"): continue
			var key:=str(actor["id"])
			if flight["hits"].has(key) or float(actor.get("health",0))<=0.0: continue
			var away:=Vector2(actor["x"]-pos.x,actor["z"]-pos.z)
			if away.length_squared()>=radius*radius: continue
			var rise:=0.7+Terrain.HEIGHT_SCALE*random.randf()
			var speed:=5.0+random.randf()
			var direction:=away.normalized()
			var impulse:=Vector3(direction.x,direction.y*rise,direction.y)*speed
			flight["hits"][key]=true
			actor["health"]=maxf(0.0,float(actor["health"])-impulse.length()*float(rules["damage"]))
			events.append({"type":"campaign_meteor_follower_hit","id":actor["id"],"health":actor["health"]})
			if actor["health"]>0.0: continue
			match index:
				0: world.remove_follower(actor)
				1: groups[index].erase(actor)
				2: world.remove_astari_performer(actor)
	if state["followers"].is_empty(): world.respawn_source_followers()


static func number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high


static func pair(value: Variant,low: float,high: float) -> bool:
	return value is Array and value.size()==2 and number(value[0],low,high) and number(value[1],low,high)


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER: return false
	if not Numbers.integer_between(rules.get("population"),1,100000) or not Numbers.integer_between(rules.get("belief"),1,1000000): return false
	for key: String in ["swipe_min","swipe_max","min_time","max_time","min_speed","max_speed","distance","strength","crater_radius","crater_depth","blight","blast_speed","blast_max","blast_size_start","blast_size_end","house_radius","damage","settlement_taps","settlement_reset","angle_scale","radians_per_degree","speed_scale","radius_scale","ground_skin","impact_drop","water_slowdown","drag","water_drag","gravity","rest_squared","destruction_height","bounds_margin","sea_height","blight_radius_scale","water_trail_radius","trail_squared","end_height"]:
		if not number(rules.get(key),0.000001,10000.0): return false
	if not number(rules.get("angle_min"),-180.0,0.0) or not number(rules.get("angle_max"),0.0,180.0) or not number(rules.get("depth_scale"),-100.0,-0.000001): return false
	if not number(rules.get("speed_from_length"),0.0,1.0) or rules["min_speed"]>rules["max_speed"] or rules["min_time"]>=rules["max_time"]: return false
	if rules["swipe_min"]>=rules["swipe_max"] or not rules.get("upgrades") is Array or rules["upgrades"].size()!=2: return false
	for upgrade: Variant in rules["upgrades"]:
		if not upgrade is Dictionary or upgrade.get("currency")!="gems" or not Numbers.integer_between(upgrade.get("cost"),1,1000000): return false
		for key: String in ["id","unlock","title","button","description"]:
			if not upgrade.get(key) is String or upgrade[key].is_empty(): return false
		if not upgrade.get("multipliers") is Dictionary: return false
		for key: String in ["crater_radius","crater_depth","blight"]:
			if not number(upgrade["multipliers"].get(key),0.0,10.0): return false
	return true


static func valid(opening: Dictionary) -> bool:
	var rules: Variant=opening["definition"].get(KEY)
	if rules==null: return not opening.has("meteor_flights") and not opening.has("meteor_settlement_hit")
	if not valid_rules(rules): return false
	var flights: Variant=opening.get("meteor_flights",[])
	if not flights is Array or flights.size()>MAX_FLIGHTS: return false
	var ids: Dictionary={}
	for flight: Variant in flights:
		if not flight is Dictionary or not flight.get("phase") in ["flight","splash","blast"] or not Numbers.integer_between(flight.get("id"),1,2147483647) or ids.has(flight["id"]): return false
		ids[flight["id"]]=true
		for key: String in ["target","velocity","position"]:
			var xyz: Variant=flight.get(key)
			if not xyz is Array or xyz.size()!=3: return false
			for value: Variant in xyz:
				if not number(value,-2048.0,2048.0): return false
		for key: String in ["strength","blast"]:
			if not number(flight.get(key),0.0,1000.0): return false
		if not flight.get("hits") is Dictionary: return false
		for id: Variant in flight["hits"]:
			if not id is String or not id.is_valid_int() or int(id)<=0 or flight["hits"][id]!=true: return false
	if not opening.has("meteor_settlement_hit"): return true
	var hit: Variant=opening["meteor_settlement_hit"]
	return hit is Dictionary and Numbers.integer_between(hit.get("id"),1,2147483647) and Numbers.integer_between(hit.get("tick"),0,9223372036854775807) and Numbers.integer_between(hit.get("count"),1,2147483647)
