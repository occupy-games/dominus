extends RefCounted
## Projects the detached sparse terrain fields into a shader data texture.

const TILE_SIZE := 32
const TILES_PER_ROW := 32


static func fields_for(state: Dictionary) -> Array:
	if state.has("voyage"):
		return []
	var raster: Dictionary=state.get("source_influence",{}).get("raster",state.get("map_fields",{}))
	var fields: Dictionary=raster.get("fields",{})
	var beauty: Dictionary=fields.get("1",{})
	return [] if beauty.is_empty() else [beauty,fields.get("2",{}),fields.get("3",{})]


static func image_for(width: int,fields: Array) -> Image:
	if fields.is_empty():
		return null
	var bounds := Rect2i(0,0,width,width)
	var image: Image
	for key: String in fields[0]:
		var tile := int(key)
		@warning_ignore("integer_division")
		var origin := Vector2i(tile%TILES_PER_ROW,tile/TILES_PER_ROW)*TILE_SIZE
		var region := Rect2i(origin,Vector2i.ONE*TILE_SIZE).intersection(bounds)
		if not region.has_area():
			continue
		var bytes: PackedByteArray=fields[0][key]
		if fields[1].has(key) or fields[2].has(key):
			bytes=bytes.duplicate()
			var first: PackedByteArray=fields[1].get(key,PackedByteArray())
			var second: PackedByteArray=fields[2].get(key,PackedByteArray())
			for i in range(bytes.size()):
				var blight := maxi(first[i] if not first.is_empty() else 0,second[i] if not second.is_empty() else 0)
				bytes[i]=maxi(0,int(bytes[i])-blight)
		if bytes.count(0)==bytes.size():
			continue
		if image==null:
			image=Image.create_empty(width,width,false,Image.FORMAT_R8)
		var tile_image := Image.create_from_data(TILE_SIZE,TILE_SIZE,false,Image.FORMAT_R8,bytes)
		image.blit_rect(tile_image,Rect2i(Vector2i.ZERO,region.size),origin)
	return image
