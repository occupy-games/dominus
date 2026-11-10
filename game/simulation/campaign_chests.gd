extends RefCounted
## Compatibility campaign supply. Original area budgets/sampling are projected
## by unlock identity onto the playable map. Source offline-storm delays drive
## this bounded refill clock until the complete weather controller is ported.

const Native = preload("res://simulation/source_storm_chests.gd")


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
	for active: Dictionary in p["influence"]:
		for source: Dictionary in config["areas"]:
			if source["unlock"]!=active["unlock"] or int(source["max_total"])<=0: continue
			var area: Dictionary=source.duplicate(true)
			for key: String in ["x","z","radius"]: area[key]=active[key]
			area["force"]=true
			areas.append(area)
	var chests: Array=[]
	for chest: Dictionary in p["chests"]:
		if not chest["opened"] and chest.get("generated",false): chests.append({"source_id":0,"x":chest["x"],"z":chest["z"]})
	# Retire opened generated entries after their disappearance. Authored chest
	# history is permanent; procedural supply has a bounded live population.
	p["chests"]=p["chests"].filter(func(chest: Dictionary) -> bool: return not (chest.get("generated",false) and chest["opened"]))
	var random_word := func() -> int: return random.randi_range(0,32767)
	var place := func(request: Dictionary) -> void:
		for i in range(int(request["count"])):
			var acceptable := func(x: float,z: float) -> bool:
				var px := roundi(x)
				var pz := roundi(z)
				if world.height_at(px,pz)<=0 or not world.can_act_at(px,pz): return false
				var padding := ceili(float(config["padding"]))
				for dz in range(-padding,padding+1):
					for dx in range(-padding,padding+1):
						if world._occupied(px+dx,pz+dz) or not world.plot_obstruction(px+dx,pz+dz).is_empty(): return false
				for chest: Dictionary in p["chests"]:
					if not chest["opened"] and Vector2(px,pz).distance_to(Vector2(chest["x"],chest["z"]))<=float(config["padding"])*2: return false
				return true
			var point := Native.sample(float(request["x"]),float(request["z"]),float(request["radius"]),config["sampling"],random_word,acceptable)
			if not point.get("ok",false): continue
			var x := roundi(point["position"][0])
			var z := roundi(point["position"][1])
			var depth := mini(int(request["max_depth"]),roundi(float(random_word.call())/float(config["sampling"]["random_divisor"])*(float(request["max_depth"])+1.0)))
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
	Native.replenish(areas,chests,config["sampling"],func(_key: String) -> bool: return true,[],random_word,place)
