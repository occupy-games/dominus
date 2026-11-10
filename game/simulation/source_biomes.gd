extends RefCounted
## Native biome selection (0x1025b570/0x1025b610) and height bands (0x10153980).


static func f32(value: float) -> float:
	return float(PackedFloat32Array([value])[0])


static func scheme_at(rows: Array,x: float,z: float) -> int:
	var best := 0.0
	var scheme := -1
	# Native CSV storage has 32 entries and ends at the first outer radius < 1.
	for index in range(mini(32,rows.size())):
		var row: Dictionary=rows[index]
		var radius := f32(float(row["outer"]))
		if radius<1: break
		var dx := f32(f32(float(row["x"]))-f32(x))
		var dz := f32(f32(float(row["z"]))-f32(z))
		var distance := f32(sqrt(f32(dx*dx+dz*dz)))
		var margin := f32(radius-distance)
		if margin>best:
			best=margin
			scheme=int(row["scheme"])
	return scheme


static func biome_at(rows: Array,configuration: Dictionary,x: float,z: float) -> int:
	var scheme := scheme_at(rows,x,z)
	for index in range(1,4):
		if float(scheme)==float(configuration["biome%dIndex"%index]): return index
	return 0


static func band(raw_height: float,configuration: Dictionary) -> int:
	if raw_height>=float(configuration["loc3Start"]): return 2
	return 1 if raw_height>=float(configuration["loc2Start"]) else 0


static func valid(environment: Variant) -> bool:
	if not environment is Dictionary or not environment.get("biomes") is Array or environment["biomes"].size()>32 or not environment.get("configuration") is Dictionary: return false
	for key: String in ["loc2Start","loc3Start","biome1Index","biome2Index","biome3Index"]:
		var value: Variant=environment["configuration"].get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return false
	for row: Variant in environment["biomes"]:
		if not row is Dictionary: return false
		for key: String in ["x","z","inner","outer","scheme"]:
			var value: Variant=row.get(key)
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if row["scheme"]!=int(row["scheme"]): return false
	return true
