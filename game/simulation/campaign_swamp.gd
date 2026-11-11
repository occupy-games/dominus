extends RefCounted
## Homeworld6 owns timed swamp casts, puddle footprints and exposed actors.

const Source = preload("res://simulation/source_swamp.gd")
const Fields = preload("res://simulation/source_map_fields.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const KEY := "swamp"


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("opening",{}).get("definition",{}).get(KEY,{})


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary) -> Dictionary:
	var rules:=rules_for(state)
	var reject:={"ok":false,"cost":0,"reason":""}
	if rules.is_empty() or not state.has("source_influence") or not Source.POWER in state["progression"]["powers"]: return reject
	var x: Variant=command.get("x")
	var z: Variant=command.get("z")
	var width: int=state["width"]
	if not position(x,width) or not position(z,width): return reject
	if not world.can_act_at(x,z) or world.height_at(int(x),int(z))<=0: return reject
	var cost:=int(rules["belief"])
	return {"ok":int(state["belief"])>=cost,"cost":cost,"reason":"","x":x,"z":z}


static func position(value: Variant,width: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and float(value)<width-1


static func discover(state: Dictionary,events: Array) -> void:
	var rules:=rules_for(state)
	if rules.is_empty(): return
	var p: Dictionary=state["progression"]
	if state["followers"].size()>=int(rules["population"]) and not Source.CARD in p["discovered"]:
		preload("res://simulation/progression.gd").discover(p,Source.CARD)
		if Source.CARD in p["discovered"]:
			events.append({"type":"card_discovered","card":Source.CARD})
			events.append({"type":"campaign_autosave"})
	if Unlocks.enabled(p,Source.POWER) and not Source.POWER in p["powers"]:
		p["powers"].append(Source.POWER)
		p["revision"]+=1


static func initialize(world: RefCounted,state: Dictionary,tick_seconds: float) -> void:
	var rules:=rules_for(state)
	if rules.is_empty() or state["opening"].has(KEY): return
	state["opening"][KEY]={"casts":[],"active":{},"casualties":[]}
	var expiry:=ceili(float(rules["timeout"])/tick_seconds)
	if int(state["tick"])>=expiry: return
	for point: Array in rules["initial"]:
		place(world,state,float(point[0]),float(point[1]),expiry,rules)


static func cast(world: RefCounted,state: Dictionary,plan: Dictionary,tick_seconds: float,events: Array) -> void:
	initialize(world,state,tick_seconds)
	var rules:=rules_for(state)
	var expiry:=int(state["tick"])+ceili(float(rules["timeout"])/tick_seconds)
	place(world,state,plan["x"],plan["z"],expiry,rules)
	events.append({"type":"use_power","power":Source.POWER,"x":plan["x"],"z":plan["z"]})
	events.append({"type":"source_sound","event":"Swamp cast"})


static func place(world: RefCounted,state: Dictionary,x: float,z: float,expiry: int,rules: Dictionary) -> void:
	var runtime: Dictionary=state["opening"][KEY]
	var width: int=state["width"]
	var raw: int=world.source_raw_height_at(int(x),int(z))
	var raster: Dictionary=state["source_influence"]["raster"]
	var spread:=Source.start(x,z,raw,expiry,width,raster)
	var reserved := {}
	for existing: Dictionary in runtime["casts"]:
		for pool: Array in existing["puddles"]: mark(reserved,pool,width)
	spread["puddles"]=pack_puddles(world,spread,rules,width,reserved)
	runtime["casts"].append(spread)


static func pack_puddles(world: RefCounted,cast_: Dictionary,rules: Dictionary,width: int,reserved: Dictionary) -> Array:
	var result: Array=[]
	var radius: float=rules["max_radius"]
	var center:=Vector2(cast_["x"],cast_["z"])
	var squared:=radius*radius
	var min_x:=maxi(0,int(center.x-radius))
	var max_x:=mini(width-1,int(center.x+radius+float(rules["bounds_margin"])))
	var min_z:=maxi(0,int(center.y-radius))
	var max_z:=mini(width-1,int(center.y+radius+float(rules["bounds_margin"])))
	for size in range(int(rules["max_puddle_size"]),int(rules["min_puddle_size"])-1,-1):
		var edge:=maxi(0,size-1)
		for z in range(min_z,max_z-size+1):
			for x in range(min_x,max_x-size+1):
				if int(world.source_raw_height_at(x,z))!=int(cast_["raw_height"]) or world._occupied(x,z): continue
				var origin:=Vector2i(x,z)
				if center.distance_squared_to(Vector2(origin))>=squared: continue
				var fits:=true
				# The native origin uses squared distance. Its corner checks
				# multiply the two offsets and sample the last tile of the span.
				for offset: Vector2i in [Vector2i.ZERO,Vector2i(edge,0),Vector2i(0,edge),Vector2i(edge,edge)]:
					var point:=origin+offset
					var delta:=Vector2(point)-center
					if reserved.has(Source.key(point.x,point.y,width)) or delta.x*delta.y>squared:
						fits=false
						break
				if not fits or (size>0 and int(world.source_plot_capacity(x,z,size))<size): continue
				var pool:=[x,z,size]
				result.append(pool)
				mark(reserved,pool,width)
	return result


static func mark(cells: Dictionary,pool: Array,width: int) -> void:
	for z in range(int(pool[1]),int(pool[1])+int(pool[2])+1):
		for x in range(int(pool[0]),int(pool[0])+int(pool[2])+1): cells[Source.key(x,z,width)]=true


static func active_at(state: Dictionary,x: int,z: int) -> bool:
	var cells: Dictionary=state.get("opening",{}).get(KEY,{}).get("active",{})
	if cells.is_empty(): return false
	var width: int=state["width"]
	return x>=0 and z>=0 and x<width and z<width and cells.has(Source.key(x,z,width))


static func sculpt(state: Dictionary,cell: int,random: RandomNumberGenerator) -> void:
	var runtime: Dictionary=state["opening"].get(KEY,{})
	if runtime.is_empty() or runtime["casts"].is_empty(): return
	var width: int=state["width"]
	var raster: Dictionary=state["source_influence"]["raster"]
	if Fields.byte_at(raster,3,cell%width,cell/width)==0: return
	if random.randf()>=float(rules_for(state)["sculpt_clear_chance"]): return
	for spread: Dictionary in runtime["casts"]: spread["cells"].erase(str(cell))
	Fields.overwrite(raster,3,cell%width,cell/width,0.0)


static func advance(world: RefCounted,state: Dictionary,tick_seconds: float,events: Array) -> void:
	var rules:=rules_for(state)
	if rules.is_empty() or not state.has("source_influence"): return
	initialize(world,state,tick_seconds)
	var runtime: Dictionary=state["opening"][KEY]
	var tick: int=state["tick"]
	var width: int=state["width"]
	var raster: Dictionary=state["source_influence"]["raster"]
	if not runtime["casualties"].is_empty():
		runtime["casualties"]=runtime["casualties"].filter(func(body: Dictionary) -> bool: return tick<int(body["expires"]))
	if runtime["casts"].is_empty(): return
	var expired := {}
	var casts: Array=runtime["casts"]
	var membership:=0
	for spread: Dictionary in casts.duplicate():
		if tick>=int(spread["until"]):
			expired.merge(spread["cells"])
			casts.erase(spread)
			continue
		var remaining:=tick_seconds
		while remaining>0.000001 and float(spread["progress"])<1.0:
			var frame:=minf(remaining,float(rules["max_delta"]))
			Source.spread(spread,raster,rules,world.source_raw_height_at,width,frame)
			remaining-=frame
		membership+=int(spread["count"])
	for spread: Dictionary in casts:
		for key: String in spread["cells"]: expired.erase(key)
	for key: String in expired:
		var cell:=int(key)
		Fields.overwrite(raster,3,cell%width,cell/width,0.0)
	var stamp:=[state["terrain_revision"],state["opening"].get("bathymetry_revision",0),raster.get("field_notifications",{}).get("serial",0),casts.size(),membership]
	if stamp!=runtime.get("footprint_stamp",[]):
		runtime["footprint_stamp"]=stamp
		refresh_active(world,state,runtime,width,raster)
	update_actors(world,state,runtime,rules,tick_seconds,events)


static func refresh_active(world: RefCounted,state: Dictionary,runtime: Dictionary,width: int,raster: Dictionary) -> void:
	var active := {}
	for spread: Dictionary in runtime["casts"]:
		for pool: Array in spread["puddles"]:
			if active_pool(world,spread,pool,width,raster): mark(active,pool,width)
	var previous: Dictionary=runtime["active"]
	if previous!=active:
		var schedule: Dictionary=state["source_plots"]["schedule"] if state.has("source_plots") else {}
		if not schedule.is_empty():
			for cells: Dictionary in [previous,active]:
				for key: String in cells:
					if previous.has(key)==active.has(key): continue
					var cell:=int(key)
					Numbers.mark(schedule,cell%width,cell/width)
		runtime["active"]=active


static func active_pool(world: RefCounted,spread: Dictionary,pool: Array,width: int,raster: Dictionary) -> bool:
	var x:=int(pool[0])
	var z:=int(pool[1])
	var size:=int(pool[2])
	var touched:=false
	for point: Vector2i in [Vector2i(x,z),Vector2i(x+size,z),Vector2i(x,z+size),Vector2i(x+size,z+size)]:
		touched=touched or spread["cells"].has(Source.key(point.x,point.y,width))
	if not touched or Fields.byte_at(raster,3,x+size/2,z+size/2)==0: return false
	for pz in range(z,z+size+1):
		for px in range(x,x+size+1):
			if Fields.byte_at(raster,1,px,pz)>0 or int(world.source_raw_height_at(px,pz))!=int(spread["raw_height"]): return false
	return true


static func update_actors(world: RefCounted,state: Dictionary,runtime: Dictionary,rules: Dictionary,tick_seconds: float,events: Array) -> void:
	var active: Dictionary=runtime["active"]
	var tick: int=state["tick"]
	var width: int=state["width"]
	var groups: Array=[state["followers"],state.get("enemies",[]),state.get("astari_village",{}).get("performers",[])]
	for group in range(groups.size()):
		var dead: Array=[]
		for actor: Dictionary in groups[group]:
			if actor["state"]=="indoors" or actor.has("ark_passenger") or actor.has("sacrifice_due") or not active.has(Source.key(int(actor["x"]),int(actor["z"]),width)):
				actor.erase("swamp_entered")
				continue
			var stats: Dictionary=world.follower_values(actor)
			var damage:=float(stats.get("SwampDamage",rules["damage"].get(actor.get("race","Brown Head"),0)))*tick_seconds
			if damage<=0.0:
				actor.erase("swamp_entered")
				continue
			if float(rules["drown_threshold"])<1.0 and not actor.has("swamp_entered"): actor["swamp_entered"]=tick
			actor["health"]=maxf(0.0,float(actor.get("health",stats.get("MaxHealth",100)))-damage)
			if float(actor["health"])<=0.0: dead.append(actor)
		for actor: Dictionary in dead:
			var body: Dictionary={"id":actor["id"],"x":actor["x"],"z":actor["z"],"rotation":actor.get("rotation",0.0),
				"scale":actor.get("scale",1.0),"state":"dying","race":actor.get("race","Brown Head"),"female":actor.get("female",false),
				"death_tick":tick,"expires":tick+ceili((float(rules["clips"]["swamp_die"])+float(rules["clips"]["swamp_sink"]))/tick_seconds)}
			runtime["casualties"].append(body)
			match group:
				0: world.remove_follower(actor)
				1: groups[group].erase(actor)
				2: world.remove_astari_performer(actor)
			events.append({"type":"follower_swamp_death","id":actor["id"]})
	if state["followers"].is_empty(): world.respawn_source_followers()


static func decorate_snapshot(state: Dictionary,tick_seconds: float) -> void:
	var runtime: Dictionary=state["opening"].get(KEY,{})
	if runtime.is_empty() or runtime["casualties"].is_empty(): return
	var duration: float=rules_for(state)["clips"]["swamp_die"]
	var bodies: Array=state.get("casualties",[])
	for body: Dictionary in runtime["casualties"]:
		var elapsed: float=(int(state["tick"])-int(body["death_tick"]))*tick_seconds
		body["swamp_animation"]="swamp_die" if elapsed<duration else "swamp_sink"
		body["swamp_elapsed"]=elapsed if elapsed<duration else elapsed-duration
		bodies.append(body)
	state["casualties"]=bodies


static func valid(runtime: Variant,rules: Dictionary) -> bool:
	if not runtime is Dictionary or not runtime.get("casts") is Array or not runtime.get("casualties") is Array: return false
	if not valid_cells(runtime.get("active")): return false
	for cast_: Variant in runtime["casts"]:
		if not cast_ is Dictionary or not position(cast_.get("x"),1024) or not position(cast_.get("z"),1024): return false
		for key_: String in ["progress","radius"]:
			var number: Variant=cast_.get(key_)
			if not (number is int or number is float) or not is_finite(float(number)) or float(number)<0.0: return false
		if cast_["progress"]>1.0 or cast_["radius"]>float(rules["max_radius"]): return false
		if not Numbers.integer_between(cast_.get("raw_height"),0,255) or not Numbers.integer_between(cast_.get("until"),0,9223372036854775807): return false
		if not Numbers.integer_between(cast_.get("count"),0,int(rules["max_tiles"])) or not valid_cells(cast_.get("cells")) or not cast_.get("puddles") is Array: return false
		for pool: Variant in cast_["puddles"]:
			if not pool is Array or pool.size()!=3 or not Numbers.integer_between(pool[2],int(rules["min_puddle_size"]),int(rules["max_puddle_size"])): return false
			if not Numbers.integer_between(pool[0],0,1023-int(pool[2])) or not Numbers.integer_between(pool[1],0,1023-int(pool[2])): return false
	for body: Variant in runtime["casualties"]:
		if not body is Dictionary or not position(body.get("x"),1024) or not position(body.get("z"),1024): return false
		if not Numbers.integer_between(body.get("id"),1,2147483647) or not Numbers.integer_between(body.get("death_tick"),0,9223372036854775807): return false
		if not Numbers.integer_between(body.get("expires"),int(body["death_tick"])+1,9223372036854775807) or body.get("state")!="dying": return false
	return true


static func valid_cells(cells: Variant) -> bool:
	if not cells is Dictionary: return false
	for key_: Variant in cells:
		if not key_ is String or not key_.is_valid_int() or not Numbers.integer_between(int(key_),0,1048575) or cells[key_]!=true: return false
	return true
