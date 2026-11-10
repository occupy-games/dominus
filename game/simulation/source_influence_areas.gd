extends RefCounted
## Original authored-area controller. Dynamic building circles are separate.

const Influence = preload("res://simulation/source_influence.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
const ID_BASE := 0x1aaaaaa00000000


static func initial(areas: Array) -> Dictionary:
	var state := {"radii":[],"powers_only":[],"raster":Influence.initial(),"dirty":{},"changed":false}
	for area: Dictionary in areas:
		state["radii"].append(0.0)
		state["powers_only"].append(bool(area["powers_only"]))
	return state


static func valid_rules(rules: Variant) -> bool:
	if not Influence.valid_rules(rules) or not rules.get("expand") is bool or not rules.get("finish_event") is String or rules["finish_event"].is_empty(): return false
	var rate: Variant=rules.get("expand_rate")
	return (rate is int or rate is float) and is_finite(float(rate)) and float(rate)>0


static func mark_radius(dirty: Dictionary,x: int,z: int,radius: int) -> void:
	# 0x10257780 samples the square at 16-cell grid points. This is distinct
	# from the 3x3 neighborhood used when terrain changes.
	for row in range((z-radius)&~15,((z+radius)&~15)+1,16):
		for column in range((x-radius)&~15,((x+radius)&~15)+1,16):
			if column>=0 and row>=0 and column<1024 and row<1024: dirty[str((row/32)*32+column/32)]=true


static func advance(state: Dictionary,areas: Array,rules: Dictionary,unlocked: Callable,delta: float,activated: Array=[],force: bool=false,rebuild: bool=false) -> Array:
	if rebuild:
		state["raster"]["fields"]={"4":{},"6":{}}
		for index in range(state["radii"].size()): state["radii"][index]=0.0
	var events: Array=[]
	var changed := false
	var active := {}
	for id: Variant in activated: active[int(id)]=true
	for index in range(areas.size()):
		var area: Dictionary=areas[index]
		if not area["force"] and not unlocked.call(str(area["unlock"])) and not active.has(index): continue
		var previous := float(state["radii"][index])
		var maximum := Terrain.f32(float(area["radius"]))
		var fraction := clampf(Terrain.f32(previous/maximum),0.0,1.0)
		fraction=Terrain.f32(fraction+Terrain.f32(Terrain.f32(delta)*float(rules["expand_rate"]))) if rules["expand"] else 1.0
		var radius := minf(maximum,Terrain.f32(maximum*fraction))
		state["radii"][index]=radius
		var sculpt: bool=unlocked.call(str(area["sculpt_unlock"]))
		var command := {"id":str(ID_BASE+index),"x":Terrain.f32(float(area["x"])),"z":Terrain.f32(float(area["z"])),"radius":radius,
			"powers_only":bool(state["powers_only"][index]) and not sculpt,"maximum":true,"force":force}
		var current := Influence.circle(state["raster"],command,rules)
		changed=changed or current
		if state["powers_only"][index] and sculpt:
			state["powers_only"][index]=false
			command["powers_only"]=true
			command["maximum"]=false
			command["force"]=true
			Influence.circle(state["raster"],command,rules)
			command["powers_only"]=false
			command["maximum"]=true
			Influence.circle(state["raster"],command,rules)
		# Native dirtiness tests the cumulative change flag, including a prior
		# area in this pass. Conversion's extra writes don't set that flag.
		if changed: mark_radius(state["dirty"],int(float(area["x"])),int(float(area["z"])),int(maxf(previous,radius)))
	if not changed and state["changed"]: events.append({"name":rules["finish_event"],"argument":0})
	state["changed"]=changed
	return events


static func valid(state: Variant,areas: Variant,rules: Dictionary) -> bool:
	if not areas is Array or areas.size()>64: return false
	for area: Variant in areas:
		if not area is Dictionary or not area.get("unlock") is String or not area.get("sculpt_unlock") is String or not area.get("force") is bool or not area.get("powers_only") is bool: return false
		for field: String in ["x","z","radius"]:
			var value: Variant=area.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)>2048 or float(value)<(-1024 if field!="radius" else 0) or (field=="radius" and float(value)==0): return false
	if not valid_rules(rules) or not state is Dictionary or not state.get("radii") is Array or state["radii"].size()!=areas.size(): return false
	if not state.get("powers_only") is Array or state["powers_only"].size()!=areas.size() or not state.get("changed") is bool or not state.get("dirty") is Dictionary or not Influence.valid(state.get("raster")): return false
	for index in range(areas.size()):
		var radius: Variant=state["radii"][index]
		if not (radius is int or radius is float) or not is_finite(float(radius)) or float(radius)<0 or float(radius)>Terrain.f32(float(areas[index]["radius"])) or Terrain.f32(float(radius))!=float(radius): return false
		if not state["powers_only"][index] is bool or state["powers_only"][index] and not areas[index]["powers_only"]: return false
	for key: Variant in state["dirty"]:
		if not key is String or not key.is_valid_int() or str(int(key))!=key or not Schedule.integer_between(int(key),0,1023) or not state["dirty"][key] is bool or not state["dirty"][key]: return false
	return true


static func export_state(state: Dictionary) -> Dictionary:
	var saved := state.duplicate(true)
	saved["raster"]=Influence.export_state(state["raster"])
	return saved


static func restore(saved: Variant,areas: Variant,rules: Dictionary) -> Dictionary:
	if not valid(saved,areas,rules): return {}
	var state: Dictionary=saved.duplicate(true)
	state["raster"]=Influence.restore(saved["raster"])
	for index in range(state["radii"].size()): state["radii"][index]=float(state["radii"][index])
	return state
