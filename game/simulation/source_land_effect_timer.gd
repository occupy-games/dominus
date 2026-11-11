extends RefCounted
## Original field 7 countdown and expiration pass (0x100d0730).

const Fields = preload("res://simulation/source_map_fields.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const INTEGER_LIMIT := 9223372036854775808.0


static func valid_rules(rules: Variant) -> bool:
	return rules is Dictionary and Numbers.integer_between(rules.get("milliseconds_per_second"),1,1000000) and Numbers.integer_between(rules.get("catch_up_limit"),1,255)


static func advance(raster: Dictionary,now: int,seconds_per_step: float,override_seconds: float,rules: Dictionary) -> Array:
	if not valid_rules(rules) or now<0:
		return []
	var scale := float(rules["milliseconds_per_second"])
	var interval := Terrain.f32(seconds_per_step)*scale
	var override_ms := Terrain.f32(override_seconds)*scale
	if not is_finite(interval) or interval<1.0 or interval>=INTEGER_LIMIT or not is_finite(override_ms) or override_ms>=INTEGER_LIMIT:
		return []
	var previous := int(raster.get("land_effect_clock",now))
	if not raster.has("land_effect_clock"):
		raster["land_effect_clock"]=now
	# Zero keeps clock-derived elapsed time but takes the explicit rebase path.
	var manual := override_ms>=0.0
	var elapsed := int(override_ms) if override_ms>0.0 else now-previous
	@warning_ignore("integer_division")
	var steps := (elapsed/int(interval))&0xffffffff
	# The original tests the low word of the quotient as a signed step count.
	if steps==0 or steps>=0x80000000:
		return []
	if not manual and steps>int(rules["catch_up_limit"]):
		raster["land_effect_clock"]=now
		return []
	raster["land_effect_clock"]=now if manual else previous+steps*int(interval)
	return expire(raster,steps)


static func morton(x: int,z: int) -> int:
	var index := 0
	for bit in range(5):
		index|=((x>>bit)&1)<<(2*bit)
		index|=((z>>bit)&1)<<(2*bit+1)
	return index


static func expire(raster: Dictionary,steps: int) -> Array:
	var timers: Dictionary=raster["fields"].get("7",{})
	var tiles: Array=[]
	for key: String in timers:
		tiles.append(int(key))
	tiles.sort()
	var changed: Array=[]
	for tile: int in tiles:
		var key := str(tile)
		var bytes: PackedByteArray=timers[key]
		var expired := {}
		for index in range(Fields.TILE_CELLS):
			var remaining := int(bytes[index])
			if remaining==0:
				continue
			bytes[index]=maxi(0,remaining-steps)
			if bytes[index]==0:
				@warning_ignore("integer_division")
				var local := Vector2i(index%Fields.TILE_SIZE,index/Fields.TILE_SIZE)
				expired[morton(local.x,local.y)]=local
		timers[key]=bytes
		if expired.is_empty():
			continue
		var order := expired.keys()
		order.sort()
		@warning_ignore("integer_division")
		var origin := Vector2i(tile%32,tile/32)*Fields.TILE_SIZE
		for index: int in order:
			var cell: Vector2i=origin+expired[index]
			var notify := false
			for kind: int in [2,3,1]:
				if Fields.allocated(raster,kind,cell.x,cell.y):
					Fields.overwrite(raster,kind,cell.x,cell.y,0.0)
					notify=true
			if notify:
				changed.append([cell.x,cell.y])
	return changed
