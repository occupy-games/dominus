extends RefCounted
## Source CSV and original-kernel entities are independent of density bytes.


static func entries(data: Dictionary) -> Array:
	var definition: Dictionary = data.get("opening",{}).get("definition",{})
	return definition.get("rock_objects",definition.get("authored_rocks",{}).get("entries",[]))


static func cell(data: Dictionary,rock: Dictionary) -> int:
	return int(rock.get("cell",int(rock["z"])*int(data["width"])+int(rock["x"])))


static func prepare(definition: Dictionary) -> void:
	if definition.is_read_only() and definition.has("rock_cells"): return
	var objects: Array = definition.get("rock_objects",definition.get("authored_rocks",{}).get("entries",[]))
	var index := {}
	for i in range(objects.size()):
		var rock: Dictionary = objects[i]
		if not rock.has("cell"): rock["cell"]=int(rock["z"])*1024+int(rock["x"])
		for dz in range(int(rock["size_z"])):
			for dx in range(int(rock["size_x"])): index[str((int(rock["origin_z"])+dz)*1024+int(rock["origin_x"])+dx)]=i
	definition["rock_objects"]=objects
	definition["rock_cells"]=index


static func at(data: Dictionary,index: int) -> Dictionary:
	if index<0 or index>=int(data["width"])*int(data["width"]): return {}
	var definition: Dictionary = data.get("opening",{}).get("definition",{})
	if definition.has("rock_cells"):
		var i := int(definition["rock_cells"].get(str(index),-1))
		return {} if i<0 else definition["rock_objects"][i]
	var x := index%int(data["width"])
	var z := index/int(data["width"])
	for rock: Dictionary in entries(data):
		if x>=int(rock["origin_x"]) and x<int(rock["origin_x"])+int(rock["size_x"]) and z>=int(rock["origin_z"]) and z<int(rock["origin_z"])+int(rock["size_z"]): return rock
	return {}


static func canonical_cell(data: Dictionary,index: int) -> int:
	var rock := at(data,index)
	return index if rock.is_empty() else cell(data,rock)


static func alive(data: Dictionary,index: int) -> bool:
	var root := canonical_cell(data,index)
	if root<0 or root>=data.get("rocks",[]).size(): return false
	if at(data,root).is_empty() and int(data["rocks"][root])==0: return false
	var present := data.has("rock_motion") or int(data["terrain"][root])>0 and int(data["terrain"][root])==int(data["rock_heights"][root])
	return present and int(data["progression"]["rock_taps"].get(str(root),0))<int(data["opening"]["definition"]["object_config"]["taps_to_destroy_rock"])


static func visibility(data: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	for rock: Dictionary in entries(data):
		result.append(1 if alive(data,cell(data,rock)) else 0)
	return result


static func valid(definition: Dictionary) -> bool:
	# Older unpublished saves have no authored entity definition.
	if not definition.has("authored_rocks"): return not definition.has("rock_objects")
	if not definition["authored_rocks"] is Dictionary or not definition["authored_rocks"].get("entries") is Array: return false
	var occupied := {}
	var roots := {}
	for rock: Variant in definition.get("rock_objects",definition["authored_rocks"]["entries"]):
		if not rock is Dictionary: return false
		for key: String in ["origin_x","origin_z","size_x","size_z","type"]:
			var value: Variant = rock.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or value!=int(value): return false
		for key: String in ["x","z","rotation"]:
			var value: Variant = rock.get(key)
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if rock.has("source_y"):
			var height: Variant=rock["source_y"]
			if not (height is int or height is float) or not is_finite(float(height)) or height<=0: return false
		if rock["size_x"]!=2 or rock["size_z"]!=2 or int(rock["type"])<20 or int(rock["type"])>26: return false
		if rock["origin_x"]<0 or rock["origin_z"]<0 or rock["origin_x"]+2>1024 or rock["origin_z"]+2>1024: return false
		if absf(float(rock["x"])-float(rock["origin_x"])-1)>0.301 or absf(float(rock["z"])-float(rock["origin_z"])-1)>0.301: return false
		if rock.get("model_name")!="boulder%d"%(int(rock["type"])-19): return false
		var root: Variant = rock.get("cell",int(rock["z"])*1024+int(rock["x"]))
		if not (root is int or root is float) or not is_finite(float(root)) or root!=int(root) or root<0 or root>=1024*1024 or roots.has(int(root)): return false
		if int(root)%1024<int(rock["origin_x"]) or int(root)%1024>=int(rock["origin_x"])+2 or int(root)/1024<int(rock["origin_z"]) or int(root)/1024>=int(rock["origin_z"])+2: return false
		roots[int(root)]=true
		for dz in range(2):
			for dx in range(2):
				var index := (int(rock["origin_z"])+dz)*1024+int(rock["origin_x"])+dx
				if occupied.has(index): return false
				occupied[index]=true
	return true
