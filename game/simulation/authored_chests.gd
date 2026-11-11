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
const Era = preload("res://simulation/source_era.gd")
const Storms = preload("res://simulation/campaign_storms.gd")
const Spawn = preload("res://simulation/source_storm_chests.gd")
const Factory = preload("res://simulation/source_chest_factory.gd")
const Placement = preload("res://simulation/source_chest_placement.gd")
const Fields = preload("res://simulation/source_map_fields.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Dispatch = preload("res://simulation/source_reward_dispatch.gd")
const Queue = preload("res://simulation/source_reward_queue.gd")
const SourceHash = preload("res://simulation/source_hash.gd")
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


func construct(row: Dictionary,handle: int,random: RandomNumberGenerator,use_original_ground: bool=false) -> Dictionary:
	var definition: Dictionary=state["opening"]["definition"]
	var sample: Callable=ground
	if use_original_ground:
		# Saves can already contain edits at a newly registered authored site.
		var floor_: PackedByteArray=definition["raw_floor"]
		var width: int=state["width"]
		var vertex := func(x: int,z: int) -> int: return floor_[z*width+x]
		sample=func(x: float,z: float) -> float: return Terrain.surface_height(Terrain.raw_at(vertex,width,x,z))
	var word := func() -> int: return random.randi_range(0,32767)
	var core := Core.initialize({"kind":int(row["type"].trim_prefix("treasure"))-1,"position":[row["x"],row["z"],0],"depth":row["depth"],"rotation":row["rotation"]},definition["chest_core_rules"],sample,word,func(_spatial: Dictionary) -> void: pass)
	return {"handle":handle,"source_id":row["id"],"reward":row["reward"],"core":core}


static func authored_count(definition: Dictionary) -> int:
	return definition.get("authored_sticker_chests",[]).size()+definition.get("authored_pack_chests",[]).size()


func register_sticker_chests(random: RandomNumberGenerator) -> void:
	var opening: Dictionary=state["opening"]
	var definition: Dictionary=opening["definition"]
	var count := authored_count(definition)
	var registered: int=opening.get("registered_sticker_chests",count if opening.get("sticker_chests_registered",false) else 0)
	if registered>=count: return
	var stickers: Array=definition.get("authored_sticker_chests",[])
	var rows: Array=stickers+definition.get("authored_pack_chests",[])
	for index in range(registered,rows.size()):
		opening["chests"].append(construct(rows[index],index+1,random,index>=stickers.size()))
	opening["registered_sticker_chests"]=rows.size()
	opening["sticker_chests_registered"]=true


static func install_pack_chests(opening: Dictionary,definition: Dictionary,source: Dictionary) -> bool:
	var count: int=definition.get("authored_sticker_chests",[]).size()+source["authored_pack_chests"].size()
	if count>65534: return false
	var chests: Array=opening.get("chests",[])
	var reserved := {}
	for chest: Dictionary in chests:
		if int(chest["handle"])>count: reserved[int(chest["handle"])]=true
	var moved := {}
	var next := count+1
	for chest: Dictionary in chests:
		var handle := int(chest["handle"])
		if not chest.has("serial") or handle>count: continue
		while reserved.has(next): next+=1
		if next>65534: return false
		moved[handle]=next
		next+=1
	# Storm IDs use their saved serial. Only the colliding internal handles move.
	for chest: Dictionary in chests:
		if moved.has(int(chest["handle"])): chest["handle"]=moved[int(chest["handle"])]
	if opening.get("sticker_chests_registered",false) and not opening.has("registered_sticker_chests"):
		opening["registered_sticker_chests"]=authored_count(opening["definition"])
	for key: String in ["authored_pack_chests","reward_catalog","reward_queue_rules","bound_sticker_selection_rules"]:
		definition[key]=Progression.canonical_numbers(source[key])
	return true


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
	if Storms.advance(opening,unlocked("Storms"),0.1,random_word): replenish(opening)


func random_word() -> int:
	return random.randi_range(0,32767)


func unlocked(name: String) -> bool:
	return Unlocks.enabled(state["progression"],name)


func ground(x: float,z: float) -> float:
	return Terrain.surface_height(world.source_raw_height_at(x,z))


func replenish(opening: Dictionary) -> void:
	var definition: Dictionary=opening["definition"]
	var minimum := int(definition["chest_factory_rules"]["sea_level"])+int(world.sculpt_minimum_layer())
	var chests: Array=[]
	for chest: Dictionary in opening["chests"]:
		if chest["source_id"]!=0: continue
		var core: Dictionary=chest["core"]
		var position: Array=core["position"]
		# Older storms could leave chests below the lowest editable terrace.
		# Keep their saved locations while freeing the slot for a usable chest.
		if roundi(float(core["base_height"])/Terrain.HEIGHT_SCALE)<minimum: continue
		if not world.can_act_at(position[0],position[1]) or world._occupied(roundi(position[0]),roundi(position[1])): continue
		chests.append({"source_id":chest["source_id"],"x":position[0],"z":position[1]})
	var place := func(request: Dictionary) -> void: generate(opening,request)
	Spawn.replenish(definition["storm_chest_areas"],chests,definition["storm_chest_rules"],unlocked,[],random_word,place)


func generate(opening: Dictionary,request: Dictionary) -> void:
	if request["count"]<=0: return
	var definition: Dictionary=opening["definition"]
	var rules: Dictionary=definition["chest_placement_rules"]
	var minimum := int(definition["chest_factory_rules"]["sea_level"])+int(world.sculpt_minimum_layer())
	var raster: Dictionary=state.get("source_influence",{}).get("raster",state.get("map_fields",{"fields":{}}))
	var field := func(name: String,x: int,z: int) -> int: return Fields.byte_at(raster,2 if name=="category" else 5,x,z)
	var nearby := func(_kind: int,_x: float,_z: float,_radius: float) -> Array: return []
	var acceptable := func(x: float,z: float,scenery: Array,buildings: Array) -> bool:
		if not world.can_act_at(x,z) or world.source_raw_height_at(x,z)<=minimum: return false
		if not Placement.acceptable(x,z,scenery,buildings,rules,field,ground,unlocked): return false
		return world.chest_site_clear(roundi(x),roundi(z),ceili(float(rules["spawn_padding"])))
	var create := func(point: Dictionary) -> void:
		var layers: int=world.source_raw_height_at(point["x"],point["z"])-minimum
		point["depth"]=minf(float(point["depth"]),float(layers))
		spawn(opening,point)
	var width: float=definition["storm_timing"]["ChestWidth"]
	Spawn.generate(request,definition["storm_chest_rules"],[width,0.0,0.0,0.0],nearby,acceptable,random_word,create,func(_objects: Array) -> void: pass)


func spawn(opening: Dictionary,point: Dictionary) -> void:
	var definition: Dictionary=opening["definition"]
	var storm: Dictionary=opening["storm"]
	if storm["serial"]>=2147483647: return
	# Authored handles stay reserved even after their chest disappears.
	var used := {}
	for chest: Dictionary in opening["chests"]: used[int(chest["handle"])]=true
	var handle := authored_count(definition)+1
	while used.has(handle): handle+=1
	if handle>65534: return
	var core := {}
	var build := func(_handle: int,request: Dictionary) -> Array:
		core.merge(Core.initialize(request,definition["chest_core_rules"],ground,random_word,func(_spatial: Dictionary) -> void: pass))
		return core["position"]
	var result := Factory.spawn(point["x"],point["z"],point["depth"],definition["chest_factory_rules"],func() -> int: return handle,ground,random_word,build,func(_handle: int,_id: int,_reward: String) -> void: pass,func(_handle: int,_position: Array) -> void: pass)
	if result.is_empty(): return
	storm["serial"]+=1
	opening["chests"].append({"handle":handle,"source_id":0,"serial":storm["serial"],"reward":result["reward"],"core":core})


static func identifier(chest: Dictionary) -> String:
	if chest.has("serial"): return "storm:"+str(int(chest["serial"]))
	return "reward:"+str(int(chest["source_id"]))


func identifier_at(handle: int) -> String:
	for chest: Dictionary in state["opening"]["chests"]:
		if int(chest["handle"])==handle: return identifier(chest)
	return ""


func snapshot() -> Array:
	var result: Array=[]
	var opening: Dictionary=state["opening"]
	var sea_level: float=opening["definition"].get("chest_factory_rules",{}).get("sea_level",19)
	var sea_height := Terrain.surface_height(int(sea_level))
	var minimum: int=world.sculpt_minimum_layer()
	for chest: Dictionary in opening.get("chests",[]):
		var core: Dictionary=chest["core"]
		var position: Array=core["position"]
		var phase := int(core["source_slots"]["60"])
		var height := float(position[2])/Terrain.HEIGHT_SCALE-sea_level
		var view := {"id":identifier(chest),"type":"treasure"+str(int(core["kind"])+1),"x":position[0],"z":position[1],"rotation":core["rotation"],"height":0.0 if is_zero_approx(height) else height,"card":chest["reward"],"opened":phase==2,"opening":phase>0,"native":true,"exposed":Lifetime.exposed(chest,opening["definition"]["chest_lifetime_rules"],service)}
		if phase==0 and height>=float(minimum)-0.001 and Influence.contains(state,position[0],position[1]):
			var surface := ground(position[0],position[1])
			view["glint"]={"height":surface-sea_height,"depth":surface-float(position[2]),"initial_delay":core["source_slots"]["9c"]}
		result.append(view)
	return result


func service(name: String,handle: int,args: Array) -> Variant:
	var opening: Dictionary=state["opening"]
	var definition: Dictionary=opening["definition"]
	var progression: Dictionary=state["progression"]
	match name:
		"ground": return ground(args[0],args[1])
		"sculpt": return {"active":false}
		"influence": return Influence.contains(state,args[0],args[1])
		"mission_mode": return 0
		"increment_opened": opening["opened_chests"]+=1
		"open_notification":
			events.append({"type":"chest_opening","id":identifier_at(handle)})
		"opened_log":
			if int(args[0])!=0: opening["chest_history"][str(int(args[0]))]=int(args[1])
		"reward_available":
			if int(handle)>authored_count(definition) and args[0]==definition["chest_factory_rules"]["story_reward"]: return true
			if pack_id(definition,str(args[0]))!=0: return true
			if definition.get("source_chest_stickers",false) and args[0] in Selection.KINDS: return true
			return progression["rules"]["cards"].has(args[0]) and Availability.available(opening["chest_capacity"],args[0],definition["availability_rules"],[])>0
		"reward_type_a": return definition.get("source_chest_stickers",false) and args[0] in Selection.KINDS
		"reward_status","reward_type_b": return false
		"unlocked": return unlocked(args[0])
		"unlock":
			if not progression.has("script_unlocks"): progression["script_unlocks"]={}
			progression["script_unlocks"][args[0]]=true
		"grant":
			var reward := str(args[0])
			var pack := pack_id(definition,reward)
			if int(args[1])==0 and reward==definition["chest_factory_rules"]["story_reward"]:
				grant_story(opening,handle,int(args[2]))
			elif pack!=0: grant_pack(opening,handle,pack,int(args[1]),int(args[2]))
			else: grant_card(opening,handle,reward)
		"animation","finish_target","destroy","unregister","release": pass
	return null


func grant_card(opening: Dictionary,handle: int,reward: String) -> void:
	var definition: Dictionary=opening["definition"]
	var progression: Dictionary=state["progression"]
	if definition.get("source_chest_stickers",false) and reward in Selection.KINDS:
		reward=select_sticker(definition,progression,reward)
	if reward=="Sticker_Gem_1":
		credit_gems(handle,1)
		return
	if not progression["rules"]["cards"].has(reward): return
	if not Availability.acquire(opening["chest_capacity"],reward,1,definition["availability_rules"],[]): return
	Progression.reward(state,reward)
	events.append({"type":"chest_opened","id":identifier_at(handle),"card":reward,"reward":{}})


func credit_gems(handle: int,amount: int) -> void:
	if amount<=0: return
	state["gems"]+=amount
	events.append({"type":"chest_opened","id":identifier_at(handle),"card":"","reward":{"gems":amount}})


static func pack_id(definition: Dictionary,reward: String) -> int:
	if not definition.has("authored_pack_chests") or not reward.begins_with("Pack_"): return 0
	for pack: Dictionary in definition["reward_catalog"]["records"]["packs"]:
		if pack["name"]==reward: return int(pack["id"])
	return 0


static func reward_records(definition: Dictionary) -> Dictionary:
	var catalog: Variant=definition.get("reward_catalog")
	if not catalog is Dictionary or not catalog.get("records") is Dictionary: return {}
	var records: Dictionary=catalog["records"].duplicate(false)
	records["stories"]=definition.get("chest_stories",[])
	return records


static func dispatch_state(opening: Dictionary) -> Dictionary:
	if not opening.has("chest_story_dispatch"):
		opening["chest_story_dispatch"]={"stories_acquired":[],"pack_count":0,"pack_index":0}
	return opening["chest_story_dispatch"]


func grant_pack(opening: Dictionary,handle: int,pack: int,source_id: int,flags: int) -> void:
	var definition: Dictionary=opening["definition"]
	var progression: Dictionary=state["progression"]
	var records := reward_records(definition)
	var dispatch := dispatch_state(opening)
	var gem: int=definition["reward_queue_rules"]["gem_sticker"]
	var selectors: Dictionary=definition["bound_sticker_selection_rules"]["kinds"]
	var route := func(name: String,args: Array) -> Variant:
		match name:
			"card_acquired":
				var card := Queue.registered(records["cards"],int(args[0]))
				return int(card.get("source_id","") in progression["discovered"])
			"select_sticker":
				var selector: String=selectors.get(Availability.key(args[0]),"")
				if selector.is_empty(): return 0
				var reward := select_sticker(definition,progression,selector,int(args[1]))
				return SourceHash.text(reward) if not reward.is_empty() else 0
			"story": events.append({"type":"chest_story_found","id":identifier_at(handle),"story":args[0]})
			"grant":
				if args[1] and int(args[0])==gem:
					if not bool(int(args[2])&12):
						credit_gems(handle,Queue.gem_credit_amount(int(dispatch["pack_count"]),int(dispatch["pack_index"])))
				else:
					var reward := Queue.registered(records["stickers" if args[1] else "cards"],int(args[0]))
					if not reward.is_empty(): grant_card(opening,handle,str(reward["source_id"]))
		return 0
	Dispatch.from_site(dispatch,records,definition["reward_dispatch_rules"],pack,source_id,flags,false,random_word,route)


func grant_story(opening: Dictionary,handle: int,flags: int) -> void:
	var definition: Dictionary=opening["definition"]
	var rules: Dictionary=definition["reward_dispatch_rules"]
	var records := {"stories":definition["chest_stories"],"packs":[],"cards":[],"stickers":[]}
	var route := func(name: String,args: Array) -> Variant:
		match name:
			"story": events.append({"type":"chest_story_found","id":identifier_at(handle),"story":args[0]})
			"select_sticker": grant_card(opening,handle,definition["chest_factory_rules"]["normal_reward"])
		return 0
	Dispatch.from_site(dispatch_state(opening),records,rules,int(rules["random_story"]),0,flags,false,random_word,route)


func select_sticker(definition: Dictionary,progression: Dictionary,kind: String,override: int=0) -> String:
	var cards: Array=definition["source_research_cards"]
	var stickers: Array=definition["source_research_stickers"]
	var era:=Era.sticker_era(progression,definition.get("era_rules",{}))
	var query:=func(name: String,index: int,_args: Array) -> Variant:
		if name=="era": return era
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
	var choice: Variant=Selection.select(kind,cards,stickers,definition["sticker_selection_rules"],override,word,query)
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
	var pack_sites: Variant=definition.get("authored_pack_chests",[])
	if not pack_sites is Array: return false
	if not pack_sites.is_empty():
		if not Dispatch.valid_records(reward_records(definition)) or not Queue.valid_rules(definition.get("reward_queue_rules")): return false
		for site: Variant in pack_sites:
			if not site is Dictionary or not site.get("reward") is String or pack_id(definition,site["reward"])==0: return false
	var rows: Array=[definition["first_chest"]]
	if opening.get("sticker_chests_registered",false):
		var sources: Array=definition.get("authored_sticker_chests",[])+pack_sites
		var count: Variant=opening.get("registered_sticker_chests",sources.size())
		if not preload("res://simulation/source_plot_schedule.gd").integer_between(count,0,sources.size()): return false
		rows.append_array(sources.slice(0,int(count)))
	var storm_serial := 0
	if opening.has("storm"):
		if not Storms.valid(opening["storm"],definition.get("storm_timing")): return false
		storm_serial=int(opening["storm"]["serial"])
	if opening.has("chest_story_dispatch") and not Dispatch.valid_state(opening["chest_story_dispatch"]): return false
	if definition.has("storm_timing"):
		if not Storms.valid_rules(definition["storm_timing"]) or not Spawn.valid_rules(definition.get("storm_chest_rules")) or not Spawn.valid_areas(definition.get("storm_chest_areas")) or not Factory.valid_rules(definition.get("chest_factory_rules")) or not Placement.valid_rules(definition.get("chest_placement_rules")): return false
		if not Dispatch.valid_rules(definition.get("reward_dispatch_rules")) or not Dispatch.valid_records({"stories":definition.get("chest_stories"),"packs":[],"cards":[],"stickers":[]}): return false
	if not Numbers.integer_between(opening.get("opened_chests"),0,rows.size()+storm_serial): return false
	var identities:={}
	for row: Dictionary in rows: identities[str(int(row["id"]))]=true
	for id: Variant in opening["chest_history"]:
		if not identities.has(id) or opening["chest_history"][id]!=2: return false
	if not opening["chests"] is Array or opening["chests"].size()>rows.size()+storm_serial or not Lifetime.restore(opening["chests"])["ok"]: return false
	var serials := {}
	for chest: Dictionary in opening["chests"]:
		var index: int=chest["handle"]
		if chest.has("serial"):
			if chest["source_id"]!=0 or index<=authored_count(definition) or not Numbers.integer_between(chest["serial"],1,storm_serial) or serials.has(int(chest["serial"])): return false
			var factory: Dictionary=definition["chest_factory_rules"]
			var expected: String=factory["story_reward"] if int(chest["core"]["kind"])==4 else factory["normal_reward"]
			if chest["reward"]!=expected: return false
			serials[int(chest["serial"])]=true
			continue
		if index<0 or index>=rows.size(): return false
		var row: Dictionary=rows[index]
		if chest["source_id"]!=row["id"] or chest["reward"]!=row["reward"]: return false
		if chest["core"]["position"][0]!=row["x"] or chest["core"]["position"][1]!=row["z"]: return false
	return true
