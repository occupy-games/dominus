extends RefCounted
## Validates the source placement stream and loads the initial scenery.


static func load_layout(story: Dictionary,terrain: PackedByteArray,fingerprints: Dictionary) -> Dictionary:
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/homeworld6-scenery.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("map")!="Homeworld6" or metadata.get("record_bytes")!=28: return {}
	if metadata.get("source_sha256")!=story["source_sha256"] or metadata.get("executable_sha256")!=story["day_cycle"]["executable_sha256"]: return {}
	if metadata.get("source_fields")!=fingerprints: return {}
	var bytes := FileAccess.get_file_as_bytes("res://assets/original/"+metadata["path"])
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if hash.finish().hex_encode()!=metadata["sha256"] or bytes.size()<12 or bytes.slice(0,4).get_string_from_ascii()!="DSCN" or bytes.decode_u32(4)!=1: return {}
	var count := bytes.decode_u32(8)
	if bytes.size()!=12+28*count or count!=int(metadata["counts"]["trees"])+int(metadata["counts"]["rocks"]): return {}
	var result := {"trees":[],"rocks":[],"rock_field":PackedByteArray(),"provenance":metadata}
	result["rock_field"].resize(1024*1024)
	for index in range(count):
		var offset := 12+index*28
		var cell := bytes.decode_u32(offset)
		var origin := bytes.decode_u32(offset+20)
		var kind := int(bytes[offset+24])
		if cell>=1024*1024 or origin>=1024*1024 or not metadata["types"].has(str(kind)): return {}
		var specification: Dictionary = metadata["types"][str(kind)]
		var item := {"cell":cell,"x":bytes.decode_float(offset+4),"z":bytes.decode_float(offset+8),
			"source_y":float(bytes.decode_float(offset+12))-float(metadata["native_sea_height"]),
			"anchor_height":int(terrain[cell]),"rotation":bytes.decode_float(offset+16),
			"model_id":specification["model_id"],"variant":kind}
		if kind<20: result["trees"].append(item)
		else:
			item.merge({"origin_x":origin%1024,"origin_z":origin/1024,"size_x":specification["size_x"],"size_z":specification["size_z"],
				"type":kind,"model_name":specification["model_name"],"authored":bytes[offset+25]!=0})
			item["source_type"]="rock1" if item["authored"] else "density"
			result["rocks"].append(item)
			result["rock_field"][cell]=kind-19
	return result
