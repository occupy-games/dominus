extends RefCounted
## Native existing-plot cell and owned-footprint predicates, not resize policy.

const Terrain = preload("res://simulation/source_terrain.gd")
const Plots = preload("res://simulation/source_plots.gd")


static func blight_blocks(raw_height: int,map_byte: int,blight: float) -> bool:
	# Native 0x101454a0: the rotation/height byte and blight field must both
	# qualify. The inclusive height interval is independent of biome/flatness.
	return map_byte>=raw_height and map_byte<=raw_height+2 and blight!=0.0


static func cell_valid(plot: Dictionary,cell: Dictionary) -> bool:
	if not cell["flat"] or cell["scenery"] or cell["blocked"]: return false
	# The native routine truncates original absolute height / its double scale;
	# e.g. float32 6.0 / .30000001192092896 truncates to raw 19, not 20.
	var raw_height := int(Terrain.f32(float(plot["height"]))/Terrain.HEIGHT_SCALE)
	if blight_blocks(raw_height,int(cell["map_byte"]),float(cell["blight"])): return false
	var owner: Dictionary=cell["owner"]
	if not owner.is_empty() and owner["claimed"] and int(owner["id"])!=int(plot["id"]): return false
	# Native 0x102363c0 reads these two gates at the current plot's origin,
	# whereas the blight check above uses the tested cell. Keep them separate.
	return Plots.map_byte_allows(int(plot["origin_byte"])) and plot["biome_allowed"]


static func owned_footprint_valid(plot: Dictionary,cell_at: Callable,interior: bool=false) -> bool:
	var first := 1 if interior else 0
	var last := int(plot["size"])-first
	var x := int(Terrain.f32(float(plot["x"])))
	var z := int(Terrain.f32(float(plot["z"])))
	for dz in range(first,last):
		for dx in range(first,last):
			var cell: Dictionary=cell_at.call(x+dx,z+dz)
			var owner: Dictionary=cell["owner"]
			if owner.is_empty() or int(owner["id"])!=int(plot["id"]) or not cell_valid(plot,cell): return false
	return true
