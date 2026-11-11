extends RefCounted
## Adapts the recovered chest constructor/lifetime to the authored campaign.
## Geometry, rewards and story notifications remain fixed-tick simulation data.

const Core = preload("res://simulation/source_chest_constructor.gd")
const Lifetime = preload("res://simulation/source_chest_lifetime.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Progression = preload("res://simulation/progression.gd")
const Influence = preload("res://simulation/influence.gd")
const Selection = preload("res://simulation/source_sticker_selection.gd")
const Research = preload("res://simulation/research.gd")
var world: RefCounted
var state: Dictionary
var events: Array
var random: RandomNumberGenerator


func configure(owner: RefCounted,data: Dictionary,output: Array) -> void:
	world=owner
	state=data
	events=output


func initialize(random: RandomNumberGenerator) -> void:
	var opening: Dictionary=state["opening"]
	if opening.has("chests"): return
	var definition: Dictionary=opening["definition"]
	var row: Dictionary=definition["first_chest"]
	opening["chests"]=[construct(row,0,random)]
	opening["chest_capacity"]=Availability.initial()
	opening["chest_history"]={}
	opening["opened_chests"]=0


func construct(row: Dictionary,handle: int,random: RandomNumberGenerator) -> Dictionary:
	var definition: Dictionary=state["opening"]["definition"]
	var ground := func(x: float,z: float) -> float: return Terrain.surface_height(world.source_raw_height_at(x,z))
	var word := func() -> int: return random.randi_range(0,32767)
	var core := Core.initialize({"kind":int(row["type"].trim_prefix("treasure"))-1,"position":[row["x"],row["z"],0],"depth":row["depth"],"rotation":row["rotation"]},definition["chest_core_rules"],ground,word,func(_spatial: Dictionary) -> void: pass)
	return {"handle":handle,"source_id":row["id"],"reward":row["reward"],"core":core}


func register_sticker_chests(random: RandomNumberGenerator) -> void:
	var opening: Dictionary=state["opening"]
	var rows: Array=opening["definition"].get("authored_sticker_chests",[])
	var registered: int=opening.get("registered_sticker_chests",rows.size() if opening.get("sticker_chests_registered",false) else 0)
	if registered>=rows.size(): return
	for index in range(registered,rows.size()): opening["chests"].append(construct(rows[index],index+1,random))
	opening["registered_sticker_chests"]=rows.size()
	opening["sticker_chests_registered"]=true


func inspect(command: Dictionary) -> Dictionary:
	for chest: Dictionary in state["opening"].get("chests",[]):
		if command.get("id")!=identifier(chest): continue
		return {"ok":Influence.contains(state,chest["core"]["position"][0],chest["core"]["position"][1]) and Lifetime.exposed(chest,state["opening"]["definition"]["chest_lifetime_rules"],service),"cost":0,"reason":""}
	return {"ok":false,"cost":0,"reason":""}


func open(command: Dictionary) -> void:
	for chest: Dictionary in state["opening"].get("chests",[]):
		if command.get("id")==identifier(chest): Lifetime.try_open(chest,state["opening"]["definition"]["chest_lifetime_rules"],service)


func advance(seeded_random: RandomNumberGenerator) -> void:
	var opening: Dictionary=state["opening"]
	if not opening.has("chests"): return
	random=seeded_random
	Lifetime.advance(opening["chests"],opening["definition"]["chest_lifetime_rules"],0.1,0,1,service)


static func identifier(chest: Dictionary) -> String:
	return "reward:"+str(int(chest["source_id"]))


func snapshot() -> Array:
	var result: Array=[]
	for chest: Dictionary in state["opening"].get("chests",[]):
		var core: Dictionary=chest["core"]
		var position: Array=core["position"]
		var phase := int(core["source_slots"]["60"])
		result.append({"id":identifier(chest),"type":"treasure"+str(int(core["kind"])+1),"x":position[0],"z":position[1],"rotation":core["rotation"],"height":float(position[2])/Terrain.HEIGHT_SCALE-19.0,"card":chest["reward"],"opened":phase==2,"opening":phase>0,"native":true,"exposed":Lifetime.exposed(chest,state["opening"]["definition"]["chest_lifetime_rules"],service)})
	return result


func service(name: String,handle: int,args: Array) -> Variant:
	var opening: Dictionary=state["opening"]
	var definition: Dictionary=opening["definition"]
	var progression: Dictionary=state["progression"]
	match name:
		"ground": return Terrain.surface_height(world.source_raw_height_at(args[0],args[1]))
		"sculpt": return {"active":false}
		"influence": return Influence.contains(state,args[0],args[1])
		"mission_mode": return 0
		"increment_opened": opening["opened_chests"]+=1
		"open_notification":
			for chest: Dictionary in opening["chests"]:
				if chest["handle"]==handle: events.append({"type":"chest_opening","id":identifier(chest)}); break
		"opened_log": opening["chest_history"][str(int(args[0]))]=int(args[1])
		"reward_available":
			return progression["rules"]["cards"].has(args[0]) and Availability.available(opening["chest_capacity"],args[0],definition["availability_rules"],[])>0
		"reward_status","reward_type_a","reward_type_b": return false
		"unlocked": return preload("res://simulation/source_unlocks.gd").enabled(progression,args[0])
		"unlock":
			if not progression.has("script_unlocks"): progression["script_unlocks"]={}
			progression["script_unlocks"][args[0]]=true
		"grant":
			var reward := str(args[0])
			if definition.get("source_chest_stickers",false) and reward==definition["chest_lifetime_rules"]["fallback_reward"]:
				reward=select_sticker(definition,progression)
			if not progression["rules"]["cards"].has(reward): return null
			if not Availability.acquire(opening["chest_capacity"],reward,1,definition["availability_rules"],[]): return null
			Progression.reward(state,reward)
			events.append({"type":"chest_opened","id":"reward:"+str(int(args[1])),"card":reward,"reward":{}})
		"animation","finish_target","destroy","unregister","release": pass
	return null


func select_sticker(definition: Dictionary,progression: Dictionary) -> String:
	var cards: Array=definition["source_research_cards"]
	var stickers: Array=definition["source_research_stickers"]
	var query:=func(name: String,index: int,_args: Array) -> Variant:
		if name=="era": return int(progression["age"])
		if name=="owned": return Research.stock(progression,stickers[index]["source_id"])
		var id: String=cards[index]["source_id"]
		var rules: Dictionary=progression["rules"]
		for binding: String in rules["card_bindings"].get(id,[]):
			if rules["cards"].has(binding):
				id=binding
				break
		match name:
			"card_complete": return id in progression["completed"]
			"card_remaining": return maxi(0,int(cards[index]["research_needed"])-Research.points(progression,id))
			"acquired": return int(id in progression["discovered"])
		return 0
	var word:=func() -> int: return random.randi_range(0,32767)
	var choice: Variant=Selection.select(definition["chest_lifetime_rules"]["fallback_reward"],cards,stickers,definition["sticker_selection_rules"],0,word,query)
	if choice is String: return choice
	for sticker: Dictionary in stickers:
		if int(sticker["id"])==choice: return sticker["source_id"]
	return ""


static func valid(opening: Dictionary) -> bool:
	if not opening.has("chests"): return true
	if not opening.get("definition",{}).has("first_chest") or not opening.get("chest_history") is Dictionary or not Availability.valid(opening.get("chest_capacity")): return false
	var definition: Dictionary=opening["definition"]
	if not Core.valid_rules(definition.get("chest_core_rules")) or not Lifetime.valid_rules(definition.get("chest_lifetime_rules")) or not Availability.valid_rules(definition.get("availability_rules")): return false
	if not opening.get("sticker_chests_registered",false) is bool: return false
	var rows: Array=[definition["first_chest"]]
	if opening.get("sticker_chests_registered",false):
		var sources: Array=definition.get("authored_sticker_chests",[])
		var count: Variant=opening.get("registered_sticker_chests",sources.size())
		if not preload("res://simulation/source_plot_schedule.gd").integer_between(count,0,sources.size()): return false
		rows.append_array(sources.slice(0,int(count)))
	if not preload("res://simulation/source_plot_schedule.gd").integer_between(opening.get("opened_chests"),0,rows.size()): return false
	var identities:={}
	for row: Dictionary in rows: identities[str(int(row["id"]))]=true
	for id: Variant in opening["chest_history"]:
		if not identities.has(id) or opening["chest_history"][id]!=2: return false
	if not opening["chests"] is Array or opening["chests"].size()>rows.size() or not Lifetime.restore(opening["chests"])["ok"]: return false
	for chest: Dictionary in opening["chests"]:
		var index: int=chest["handle"]
		if index<0 or index>=rows.size(): return false
		var row: Dictionary=rows[index]
		if chest["source_id"]!=row["id"] or chest["reward"]!=row["reward"]: return false
		if chest["core"]["position"][0]!=row["x"] or chest["core"]["position"][1]!=row["z"]: return false
	return true
