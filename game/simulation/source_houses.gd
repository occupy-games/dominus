extends RefCounted
## Original 0x100b72c0 building choice, with injected source rows/unlocks.


static func choose(rows: Array,size: int,location: int,biome: int,unlocked: Callable,kind: int=0,ignore_unlocks: bool=false,biome_locked: bool=true) -> Dictionary:
	if size<=0 or location<0 or location>2 or biome<0 or biome>3 or kind<0 or kind>2: return {}
	var best := {}
	var best_size := 0
	var best_order := -1
	for row: Dictionary in rows:
		if int(row["kind"])!=kind: continue
		var footprint := int(row["size"])
		var order := int(row["order"])
		if footprint>size or footprint<best_size or footprint==best_size and order<=best_order: continue
		if not ignore_unlocks and not unlocked.call(str(row["unlock"])): continue
		if (int(row["locations"]) & (1<<location))==0: continue
		if biome_locked and (int(row["biomes"]) & (1<<biome))==0: continue
		best=row
		best_size=footprint
		best_order=order
	# Index zero is the native null result, even if a controlled input selects it.
	return {} if best.is_empty() or int(best["index"])==0 else best.duplicate(true)


static func plot_limits(rows: Array,unlocked: Callable) -> Dictionary:
	# 0x102377f0: production rows contribute biome availability, but only abode
	# rows contribute the sizes of plots generated in each altitude band.
	var result := {"sizes":[[10000,0],[10000,0],[10000,0]],"minimum":10000,"maximum":0,"biomes":0}
	for row: Dictionary in rows:
		if not unlocked.call(str(row["unlock"])): continue
		result["biomes"]=int(result["biomes"]) | int(row["biomes"])
		if int(row["kind"])!=0: continue
		var size := int(row["size"])
		result["minimum"]=mini(int(result["minimum"]),size)
		result["maximum"]=maxi(int(result["maximum"]),size)
		for band in range(3):
			if (int(row["locations"]) & (1<<band))!=0:
				result["sizes"][band][0]=mini(int(result["sizes"][band][0]),size)
				result["sizes"][band][1]=maxi(int(result["sizes"][band][1]),size)
	return result


static func valid(rows: Variant) -> bool:
	if not rows is Array or rows.is_empty() or rows.size()>64: return false
	var ids := {}
	for index in range(rows.size()):
		var row: Variant=rows[index]
		if not row is Dictionary or not row.get("id") is String or row["id"].is_empty() or ids.has(row["id"]) or not row.get("unlock") is String: return false
		ids[row["id"]]=true
		for key: String in ["index","size","order","locations","biomes","kind"]:
			var value: Variant=row.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=int(value): return false
		if int(row["index"])!=index or int(row["size"])<0 or int(row["size"])>16 or int(row["locations"])<0 or int(row["locations"])>7 or int(row["biomes"])<0 or int(row["biomes"])>15 or int(row["kind"])<0 or int(row["kind"])>2: return false
	return true
