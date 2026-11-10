extends RefCounted
## Original registered circles, quantized influence fields and plot/power gates.
## Field tiles use plain row order; source Morton storage has identical values.

const Terrain = preload("res://simulation/source_terrain.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func initial() -> Dictionary:
	return {"circles":[],"fields":{"4":{},"6":{}}}


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for field: String in ["half_cell","feather","maximum_weight","encode_scale","decode_scale","threshold"]:
		var value: Variant=rules.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<=0: return false
	if rules.has("expand") or rules.has("expand_rate") or rules.has("finish_event"):
		var rate: Variant=rules.get("expand_rate")
		if not rules.get("expand") is bool or not (rate is int or rate is float) or not is_finite(float(rate)) or float(rate)<=0 or not rules.get("finish_event") is String or rules["finish_event"].is_empty(): return false
	return true


static func byte_at(state: Dictionary,field: int,x: int,z: int) -> int:
	if x<0 or z<0 or x>=1024 or z>=1024: return 0
	var tiles: Dictionary=state["fields"][str(field)]
	var key := str((z/32)*32+x/32)
	return int(tiles[key][(z%32)*32+x%32]) if tiles.has(key) else 0


static func write_byte(state: Dictionary,field: int,x: int,z: int,value: int) -> void:
	var tiles: Dictionary=state["fields"][str(field)]
	var key := str((z/32)*32+x/32)
	if not tiles.has(key):
		var bytes := PackedByteArray()
		bytes.resize(1024)
		tiles[key]=bytes
	# Packed array dictionary lookups are values: assign the edited tile back.
	var bytes: PackedByteArray=tiles[key]
	bytes[(z%32)*32+x%32]=value
	tiles[key]=bytes


static func circle_byte(x: float,z: float,radius: float,cell_x: int,cell_z: int,rules: Dictionary) -> int:
	var dx := Terrain.f32(x-float(cell_x)-float(rules["half_cell"]))
	var dz := Terrain.f32(z-float(cell_z)-float(rules["half_cell"]))
	var distance_squared := Terrain.f32(dx*dx+dz*dz)
	var inner := Terrain.f32(radius-float(rules["feather"]))
	var outer := Terrain.f32(radius+float(rules["feather"]))
	var weight := 0
	if distance_squared<inner*inner: weight=int(rules["maximum_weight"])
	elif distance_squared<=outer*outer and outer*outer!=inner*inner:
		weight=int((outer*outer-distance_squared)*float(rules["maximum_weight"])/(outer*outer-inner*inner))
	return int(Terrain.f32(float(weight)/float(rules["maximum_weight"]))*float(rules["encode_scale"]))&255


static func circle(state: Dictionary,command: Dictionary,rules: Dictionary) -> bool:
	# Native identity keys are uint64, including values above JSON's exact
	# integer range. Persist their decimal strings without a float conversion.
	var id := str(command["id"]) if command["id"] is String else str(int(command["id"]))
	var x := Terrain.f32(float(command["x"]))
	var z := Terrain.f32(float(command["z"]))
	var radius := Terrain.f32(float(command["radius"]))
	var entry: Dictionary={}
	for cached: Dictionary in state["circles"]:
		if str(cached["id"])==id: entry=cached; break
	if not entry.is_empty() and not command.get("force",false) and float(entry["x"])==x and float(entry["z"])==z and float(entry["radius"])==radius: return false
	if entry.is_empty():
		if state["circles"].size()<256:
			entry={"id":id}
			state["circles"].append(entry)
		else: entry=state["circles"][0] # Original fixed registry fallback retains its first identity.
	entry["x"]=x
	entry["z"]=z
	entry["radius"]=radius
	var center := Vector2i(int(x+float(rules["half_cell"])),int(z+float(rules["half_cell"])))
	var reach := ceili(Terrain.f32(radius+float(rules["feather"])))
	var field := 6 if command.get("powers_only",false) else 4
	for row in range(maxi(0,center.y-reach),mini(1023,center.y+reach)+1):
		for column in range(maxi(0,center.x-reach),mini(1023,center.x+reach)+1):
			# The source non-maximum branch clears its bounding rectangle.
			var value := maxi(byte_at(state,field,column,row),circle_byte(x,z,radius,column,row,rules)) if command.get("maximum",true) else 0
			write_byte(state,field,column,row,value)
	return true


static func allows(state: Dictionary,x: int,z: int,power: bool,rules: Dictionary) -> bool:
	var own := Terrain.f32(float(byte_at(state,4,x,z))*float(rules["decode_scale"]))
	var restricted := Terrain.f32(float(byte_at(state,6,x,z))*float(rules["decode_scale"]))
	return maxf(own,restricted)>=float(rules["threshold"]) if power else own>=float(rules["threshold"]) and restricted<=float(rules["threshold"])


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not state.get("circles") is Array or state["circles"].size()>256 or not state.get("fields") is Dictionary: return false
	var identities := {}
	for entry: Variant in state["circles"]:
		if not entry is Dictionary or not entry.get("id") is String: return false
		var id: String=entry["id"]
		if id.is_empty() or id.length()>20 or (id.length()>1 and id.begins_with("0")) or (id.length()==20 and id>"18446744073709551615") or identities.has(id): return false
		for character in id.to_ascii_buffer():
			if character<48 or character>57: return false
		identities[id]=true
		for field: String in ["x","z","radius"]:
			var value: Variant=entry.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or Terrain.f32(float(value))!=float(value): return false
		if float(entry["x"])<-1024 or float(entry["x"])>2048 or float(entry["z"])<-1024 or float(entry["z"])>2048 or float(entry["radius"])<0 or float(entry["radius"])>2048: return false
	for field: String in ["4","6"]:
		if not state["fields"].get(field) is Dictionary: return false
		for key: Variant in state["fields"][field]:
			if not key is String or not key.is_valid_int() or str(int(key))!=key or not Schedule.integer_between(int(key),0,1023): return false
			var bytes: Variant=state["fields"][field][key]
			if not (bytes is Array or bytes is PackedByteArray) or bytes.size()!=1024: return false
			for value: Variant in bytes:
				if not Schedule.integer_between(value,0,255): return false
	return true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var state: Dictionary=saved.duplicate(true)
	for field: String in ["4","6"]:
		for key: String in state["fields"][field]: state["fields"][field][key]=PackedByteArray(state["fields"][field][key])
	return state


static func export_state(state: Dictionary) -> Dictionary:
	var saved := state.duplicate(true)
	for field: String in ["4","6"]:
		for key: String in saved["fields"][field]: saved["fields"][field][key]=Array(saved["fields"][field][key])
	return saved
