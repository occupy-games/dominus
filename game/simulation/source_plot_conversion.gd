extends RefCounted
## Source constructor request and successful-construction plot release.
## The complete house constructor and follower job remain separate operations.

const Terrain = preload("res://simulation/source_terrain.gd")
const Biomes = preload("res://simulation/source_biomes.gd")
const Houses = preload("res://simulation/source_houses.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["height_offset","pi"]:
		var value: Variant=rules.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value<=0 or value>10: return false
	return true


static func valid_input(plot: Dictionary,existing: Array) -> bool:
	if not Schedule.integer_between(plot.get("size"),1,16): return false
	for axis: String in ["x","z"]:
		if not Schedule.integer_between(plot.get(axis),0,1023) or int(plot[axis])+int(plot["size"])>1024: return false
	var angle: Variant=plot.get("rotation",0.0)
	if not (angle is int or angle is float) or not is_finite(float(angle)) or absf(float(angle))>1000000: return false
	var offset: Variant=plot.get("offset",[0.0,0.0])
	if not offset is Array or offset.size()!=2: return false
	for value: Variant in offset:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1024: return false
	for building: Variant in existing:
		if not building is Dictionary or not Schedule.integer_between(building.get("index"),0,63) or not Schedule.integer_between(building.get("owner"),0,7): return false
	return true


static func request(plot: Dictionary,owner: int,kind: int,special: bool,reuse: bool,existing: Array,rows: Array,environment: Dictionary,rules: Dictionary,unlocked: Callable,ground: Callable,random_word: Callable) -> Dictionary:
	if not valid_rules(rules) or not valid_input(plot,existing) or owner<0 or owner>7 or kind<0 or kind>2: return {}
	var half := float(int(plot["size"]))*0.5
	var center_x := Terrain.f32(Terrain.f32(float(plot["x"]))+half)
	var center_z := Terrain.f32(Terrain.f32(float(plot["z"]))+half)
	var offset: Array=plot.get("offset",[0.0,0.0])
	var x := Terrain.f32(center_x+Terrain.f32(float(offset[0])))
	var z := Terrain.f32(center_z+Terrain.f32(float(offset[1])))
	var sampled: Variant=ground.call(x,z)
	if not (sampled is int or sampled is float) or not is_finite(float(sampled)) or absf(float(sampled))>10000: return {}
	var height := Terrain.f32(Terrain.f32(float(sampled))+float(rules["height_offset"]))
	# House selection uses the moved point's height, but the original center's
	# biome. It occurs after the native anti-z-fighting height offset is added.
	var band := Biomes.band(int(height/Terrain.HEIGHT_SCALE),environment["configuration"])
	var biome := Biomes.biome_at(environment["biomes"],environment["configuration"],center_x,center_z)
	# Native 0x10026a30 accepts only professions one/two when the special
	# flag is set. Special=true/kind=0 therefore has no matching source type.
	var house := {} if special and kind==0 else Houses.choose(rows,int(plot["size"]),band,biome,unlocked,kind if special else 0,false,unlocked.call("HousesBiomeLocked"))
	var index := int(house.get("index",0))
	var matching := 0
	for building: Dictionary in existing:
		if int(building["index"])==index and int(building["owner"])==owner: matching+=1
	var turn := 0.0
	if matching>=3:
		var quarter := ((int(random_word.call())&0x7fff)*4)>>15
		turn=Terrain.f32(float(quarter)*float(rules["pi"])*0.5)
	var angle := Terrain.f32(Terrain.f32(float(plot.get("rotation",0.0)))+turn)
	return {"position":[x,z,height,angle],"index":index,"owner":owner,"extra":0,"kind":kind,"special":int(special),"unknown_a":0,"unknown_b":0,"configuration":4294967295,"reuse":reuse}


static func release_plot(registry: Dictionary,id: int,created: bool,reuse: bool) -> bool:
	# Native allocation failure and reconstruction of an existing house both
	# preserve the plot. Successful new construction bypasses fade lifetime.
	if not created or reuse or not Schedule.integer_between(id,0,1023) or not registry["active"].has(id): return false
	var plot: Dictionary=registry["slots"][id]
	Registry.unregister(registry,plot)
	Schedule.mark(registry["schedule"],int(plot["x"]),int(plot["z"]))
	registry["active"].erase(id)
	registry["slots"][id]={}
	registry["free"].push_front(id)
	return true
