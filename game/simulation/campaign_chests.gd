extends RefCounted
## Compatibility campaign supply. Original area budgets/sampling are projected
## by unlock identity onto the playable map. Source offline-storm delays drive
## this bounded refill clock until the complete weather controller is ported.

const Native = preload("res://simulation/source_storm_chests.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func describe_surfaces(world: RefCounted,chests: Array) -> void:
	# The caller supplies detached descriptors. This adds the current
	# actionable surface without changing chest placement or reward state.
	for chest: Dictionary in chests:
		if chest["opened"] or chest["height"]<0 or not world.can_act_at(chest["x"],chest["z"]): continue
		var surface := Terrain.surface_height(world.height_at(chest["x"],chest["z"]))
		var height := Terrain.surface_height(int(chest["height"]))
		chest["glint"]={"height":surface,"depth":surface-height}


static func valid(p: Dictionary) -> bool:
	var config: Dictionary=p.get("rules",{}).get("chest_supply",{})
	if config.is_empty(): return true
	if not Native.valid_rules(config.get("sampling")) or not Native.valid_areas(config.get("areas")) or not preload("res://simulation/source_chest_factory.gd").valid_rules(config.get("factory")): return false
	for key: String in ["minimum_seconds","maximum_seconds","padding"]:
		var value: Variant=config.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>31536000: return false
	if config["minimum_seconds"]<=0 or config["maximum_seconds"]<config["minimum_seconds"] or config["padding"]>16: return false
	for key: String in ["supply_next_tick","supply_serial"]:
		var value: Variant=p.get(key,0)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value!=int(value) or value>9007199254740991: return false
	return true


static func advance(world: RefCounted,state: Dictionary,random: RandomNumberGenerator,events: Array) -> void:
	var p: Dictionary=state["progression"]
	var config: Dictionary=p["rules"].get("chest_supply",{})
	if config.is_empty() or not p.get("influence_enabled",false): return
	if int(state["tick"])<int(p.get("supply_next_tick",0)): return
	var minimum := maxi(1,roundi(float(config["minimum_seconds"])/0.1))
	var maximum := maxi(minimum,roundi(float(config["maximum_seconds"])/0.1))
	p["supply_next_tick"]=int(state["tick"])+random.randi_range(minimum,maximum)
	var areas: Array=[]
	var sampling: Dictionary=config["sampling"]
	var active_radii := {}
	for active: Dictionary in p["influence"]:
		if active.get("powers_only",false): continue
		var center := Vector2(active["x"],active["z"])
		active_radii[center]=maxf(float(active_radii.get(center,0)),float(active["radius"]))
	for active: Dictionary in p["influence"]:
		for source: Dictionary in config["areas"]:
			if source["unlock"]!=active["unlock"] or int(source["max_total"])<=0: continue
			var area: Dictionary=source.duplicate(true)
			for key: String in ["x","z","radius"]: area[key]=active[key]
			# Some older starts have a tiny Default circle inside an already
			# active expansion at the same center. Keep one shared chest budget.
			if float(area["radius"])<=float(sampling["influence_padding"]):
				area["radius"]=maxf(float(area["radius"]),float(active_radii.get(Vector2(area["x"],area["z"]),0)))
			area["force"]=true
			areas.append(area)
	var chests: Array=[]
	for chest: Dictionary in p["chests"]:
		if chest["opened"] or not chest.get("generated",false) or world._occupied(chest["x"],chest["z"]): continue
		chests.append({"source_id":0,"x":chest["x"],"z":chest["z"]})
	# Retire opened generated entries after their disappearance. Authored chest
	# history is permanent; procedural supply has a bounded live population.
	p["chests"]=p["chests"].filter(func(chest: Dictionary) -> bool: return not (chest.get("generated",false) and chest["opened"]))
	var random_word := func() -> int: return random.randi_range(0,32767)
	var place := func(request: Dictionary) -> void:
		var center := Vector2(request["x"],request["z"])
		var radius := float(request["radius"])+float(sampling["influence_padding"])
		var inset := float(request["radius"])
		var padding := ceili(float(config["padding"]))
		for i in range(int(request["count"])):
			var acceptable := func(x: float,z: float) -> bool:
				var px := roundi(x)
				var pz := roundi(z)
				if center.distance_squared_to(Vector2(px,pz))>=radius*radius: return false
				if world.height_at(px,pz)<=0 or not world.can_act_at(px,pz): return false
				if not world.chest_site_clear(px,pz,padding): return false
				for chest: Dictionary in p["chests"]:
					if not chest["opened"] and Vector2(px,pz).distance_to(Vector2(chest["x"],chest["z"]))<=float(config["padding"])*2: return false
				return true
			var point := Native.sample(center.x,center.y,inset if inset>0 else radius,sampling,random_word,acceptable)
			# Try the rest of the actionable circle when its inset is occupied.
			if not point.get("ok",false) and inset>0 and inset<radius:
				point=Native.sample(center.x,center.y,radius,sampling,random_word,acceptable)
			if not point.get("ok",false): continue
			var x := roundi(point["position"][0])
			var z := roundi(point["position"][1])
			var depth := mini(int(request["max_depth"]),roundi(float(random_word.call())/float(sampling["random_divisor"])*(float(request["max_depth"])+1.0)))
			var height := maxi(0,world.height_at(x,z)-depth)
			var factory: Dictionary=config["factory"]
			var raw_height := height+float(factory["sea_level"])
			var kind := "treasure1" if raw_height<float(factory["second_level"]) else ("treasure2" if raw_height<float(factory["third_level"]) else "treasure3")
			p["supply_serial"]=int(p.get("supply_serial",0))+1
			var id := "supply:%d"%int(p["supply_serial"])
			var rotation: Variant=int(factory["rotation"]) if float(factory["rotation"])==int(factory["rotation"]) else float(factory["rotation"])
			p["chests"].append({"id":id,"type":kind,"x":x,"z":z,"height":height,"depth":depth,"rotation":rotation,"card":"","opened":false,"generated":true})
			p["revision"]+=1
			events.append({"type":"chest_replenished","id":id})
	Native.replenish(areas,chests,sampling,func(_key: String) -> bool: return true,[],random_word,place)
