extends RefCounted
## Original CSV/configuration conversion only. Queries live in simulation.


static func from_rows(rows: Array,configuration: Dictionary) -> Dictionary:
	var result := {"biomes":[],"configuration":{}}
	for key: String in ["loc2Start","loc3Start","biome1Index","biome2Index","biome3Index"]:
		if not configuration.has(key) or not str(configuration[key]).is_valid_float() or not is_finite(float(configuration[key])): return {}
		result["configuration"][key]=float(configuration[key])
	for index in range(1,rows.size()):
		var row: Array=rows[index]
		if row.size()<5: continue
		if result["biomes"].size()==32: return {}
		for value: Variant in row.slice(0,5):
			if not str(value).is_valid_float() or not is_finite(float(value)): return {}
		if float(row[4])!=int(float(row[4])): return {}
		result["biomes"].append({"x":float(row[0]),"z":float(row[1]),"inner":float(row[2]),"outer":float(row[3]),"scheme":int(row[4])})
	return result
