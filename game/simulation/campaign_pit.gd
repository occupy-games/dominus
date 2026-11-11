extends RefCounted
## Leashed followers commit on arrival. Fixed ticks own the original clip
## durations, weighted gem payout and happiness change.

const CLIPS := ["sacrifice_1","sacrifice_2"]


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("clips") is Dictionary or not rules.get("gems") is Array or rules["gems"].size()!=5: return false
	for role: String in CLIPS:
		if not number(rules["clips"].get(role),0.1,60): return false
	if not number(rules.get("happiness"),-1,0) or not number(rules.get("gem_delay"),0,60) or not number(rules.get("audio_delay"),0,60): return false
	if not number(rules.get("beam_delay"),0,60): return false
	if not number(rules.get("roll_divisor"),1,32767) or rules["roll_divisor"]!=int(rules["roll_divisor"]): return false
	if not number(rules.get("birth_factor"),0.01,10000) or not number(rules.get("settlement_birth_factor"),0.01,10000): return false
	var total:=0.0
	for pair: Variant in rules["gems"]:
		if not pair is Array or pair.size()!=2 or not number(pair[0],0,1) or not number(pair[1],1,100) or pair[1]!=int(pair[1]): return false
		total+=float(pair[0])
	return is_equal_approx(total,1.0)


static func number(value: Variant,low: float,high: float) -> bool:
	return (value is float or value is int) and is_finite(value) and value>=low and value<=high


static func target(world: RefCounted,state: Dictionary,cell: Vector2i) -> Dictionary:
	var opening: Dictionary=state["opening"]
	if not opening["definition"].has("pit_sacrifice") or int(opening.get("pit_step",-1))<1: return {}
	var site: Dictionary=world.source_shrine_site()
	if not site.get("complete",false) or not world.source_shrine_bounds(site).has_point(cell): return {}
	return site


static func route(world: RefCounted,state: Dictionary,site: Dictionary,origin: Vector2i) -> Array:
	var building_id:=-1
	for home: Dictionary in state["homes"]:
		if home.get("shrine_id")==site["id"]: building_id=int(home["id"]); break
	return world._route(origin,Vector2i(site["x"],site["z"]),building_id)


static func advance(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,seconds_per_tick: float,events: Array) -> Array:
	var opening: Dictionary=state["opening"]
	var rules: Dictionary=opening["definition"].get("pit_sacrifice",{})
	var completed: Array=[]
	if rules.is_empty(): return completed
	var pending:=0
	var tick: int=state["tick"]
	var gem_delay:=ceili(float(rules["gem_delay"])/seconds_per_tick)
	var audio_delay:=roundi(float(rules["audio_delay"])/seconds_per_tick)
	var beam_delay:=ceili(float(rules["beam_delay"])/seconds_per_tick)
	for agent: Dictionary in state["followers"]:
		if not agent.get("leash_sacrifice",false): continue
		pending+=1
		if agent.has("leash_goal"): continue
		if not agent.has("sacrifice_due"):
			var site: Dictionary=world.source_shrine_site()
			var clip: String=CLIPS[random.randi_range(0,CLIPS.size()-1)]
			agent.merge({"x":float(site["x"]),"z":float(site["z"]),"state":clip,
				"sacrifice_due":int(state["tick"])+ceili(float(rules["clips"][clip])/seconds_per_tick)},true)
			continue
		var duration:=ceili(float(rules["clips"][agent["state"]])/seconds_per_tick)
		if tick==int(agent["sacrifice_due"])-duration+audio_delay:
			events.append({"type":"source_sound","event":"Pit of Doom sacrifice"})
		if tick==int(agent["sacrifice_due"])+beam_delay:
			events.append({"type":"campaign_pit_beam","site":opening["definition"]["discovery_site_id"]})
		if tick<int(agent["sacrifice_due"])+gem_delay: continue
		completed.append(agent)
	var ids: Array=[]
	# The source waits until every pending entry has finished and reached its gem delay.
	if completed.size()!=pending: return ids
	var divisor: int=rules["roll_divisor"]
	for agent: Dictionary in completed:
		var amount:=payout(rules["gems"],float(random.randi_range(0,divisor))/float(divisor))
		state["gems"]=int(state.get("gems",0))+amount
		if not opening.has("pit_totals"): opening["pit_totals"]={"followers":0,"gems":0}
		opening["pit_totals"]["followers"]+=1
		opening["pit_totals"]["gems"]+=amount
		var happiness: Dictionary=state["progression"]["happiness"]
		happiness["player"]=clampf(float(happiness["player"])+float(rules["happiness"]),0,1)
		if agent.has("away_home"):
			for home: Dictionary in state["homes"]:
				if home["id"]!=agent["away_home"]: continue
				home["sacrificed_followers"]=int(home.get("sacrificed_followers",0))+1
				break
		state["followers"].erase(agent)
		ids.append(agent["id"])
		events.append({"type":"campaign_follower_sacrificed","id":agent["id"],"gems":amount})
	if not ids.is_empty(): events.append({"type":"campaign_autosave"})
	return ids


static func payout(weights: Array,roll: float) -> int:
	var source:=preload("res://simulation/source_terrain.gd")
	roll=source.f32(roll)
	for pair: Array in weights:
		var weight:=source.f32(float(pair[0]))
		if roll<=weight: return int(pair[1])
		roll=source.f32(roll-weight)
	return int(weights.back()[1])
