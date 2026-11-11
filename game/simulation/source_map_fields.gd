extends RefCounted
## Original sparse byte fields. Tiles use row order in simulation and saves.

const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const BYTE_SCALE := 128.0
const TILE_SIZE := 32
const TILE_CELLS := 1024
const NOTIFICATION_CAPACITY := 128


static func tile_id(x: int,z: int) -> int:
	# The original checks the combined tile index after unsigned x shifting.
	return (((x&0xffffffff)>>5)+(z&0xffffffe0))&0xffffffff


static func byte_at(raster: Dictionary,kind: int,x: int,z: int) -> int:
	var tile := tile_id(x,z)
	if tile>=TILE_CELLS:
		return 0
	var layer: Variant=raster["fields"].get(str(kind))
	if layer==null:
		return 0
	var bytes: Variant=layer.get(str(tile))
	return int(bytes[(z&31)*TILE_SIZE+(x&31)]) if bytes!=null else 0


static func write_byte(raster: Dictionary,kind: int,x: int,z: int,value: int) -> void:
	var layer_key := str(kind)
	if not raster["fields"].has(layer_key):
		raster["fields"][layer_key]={}
	var layer: Dictionary=raster["fields"][layer_key]
	var tile := str(tile_id(x,z))
	var bytes: PackedByteArray
	if layer.has(tile):
		bytes=layer[tile]
	else:
		bytes.resize(TILE_CELLS)
	bytes[(z&31)*TILE_SIZE+(x&31)]=value
	layer[tile]=bytes


static func read(raster: Dictionary,kind: int,x: int,z: int) -> float:
	return float(byte_at(raster,kind,x,z))/BYTE_SCALE


static func allocated(raster: Dictionary,kind: int,x: int,z: int) -> bool:
	var tile := tile_id(x,z)
	var layer: Variant=raster["fields"].get(str(kind))
	return tile<TILE_CELLS and layer!=null and layer.has(str(tile))


static func surroundings(name: String,x: int,z: int,raster: Dictionary) -> float:
	match name:
		"beauty":
			return read(raster,1,x,z)
		"blight":
			return float(maxi(byte_at(raster,2,x,z),byte_at(raster,3,x,z)))/BYTE_SCALE
	return 0.0


static func overwrite(raster: Dictionary,kind: int,x: int,z: int,value: float,protected_tile: bool=false) -> bool:
	# Source 0x100cfe30 is unconditional. Its sibling 0x100cfd10 first checks
	# the tile flag supplied by the owning world.
	if protected_tile or kind<0 or kind>7 or tile_id(x,z)>=TILE_CELLS or not is_finite(Terrain.f32(value)):
		return false
	var scaled := Terrain.f32(value)*BYTE_SCALE
	var byte := int(scaled)&255 if scaled>=-2147483648.0 and scaled<2147483648.0 else 0
	if kind>=1 and kind<=3:
		if not raster.has("field_notifications"):
			raster["field_notifications"]={"serial":0,"cells":[]}
		var notifications: Dictionary=raster["field_notifications"]
		notifications["serial"]=(int(notifications["serial"])+1)&0xffffffff
		if notifications["cells"].size()<NOTIFICATION_CAPACITY:
			notifications["cells"].append([x&65535,z&65535])
	write_byte(raster,kind,x,z,byte)
	return true


static func valid(raster: Dictionary) -> bool:
	if not raster.get("fields") is Dictionary:
		return false
	if raster.has("land_effect_clock") and not Numbers.integer_between(raster["land_effect_clock"],0,9223372036854775807):
		return false
	for kind: Variant in raster["fields"]:
		if not kind is String or not kind.is_valid_int() or str(int(kind))!=kind or not Numbers.integer_between(int(kind),0,7):
			return false
		var layer: Variant=raster["fields"][kind]
		if not layer is Dictionary:
			return false
		for tile: Variant in layer:
			if not tile is String or not tile.is_valid_int() or str(int(tile))!=tile or not Numbers.integer_between(int(tile),0,TILE_CELLS-1):
				return false
			var bytes: Variant=layer[tile]
			if not (bytes is Array or bytes is PackedByteArray) or bytes.size()!=TILE_CELLS:
				return false
			if bytes is Array:
				for value: Variant in bytes:
					if not Numbers.integer_between(value,0,255):
						return false
	if not raster.has("field_notifications"):
		return true
	var notifications: Variant=raster["field_notifications"]
	if not notifications is Dictionary or not Numbers.integer_between(notifications.get("serial"),0,4294967295):
		return false
	if not notifications.get("cells") is Array or notifications["cells"].size()>NOTIFICATION_CAPACITY:
		return false
	for cell: Variant in notifications["cells"]:
		if not cell is Array or cell.size()!=2 or not Numbers.integer_between(cell[0],0,65535) or not Numbers.integer_between(cell[1],0,65535):
			return false
	return true
