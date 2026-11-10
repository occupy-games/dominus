extends RefCounted
## Source 0x1025fde0: density is an exclusive coordinate-hash threshold,
## not a model ID or a command to place one object in every painted cell.

const Hash = preload("res://simulation/source_hash.gd")


static func rocks(density: PackedByteArray,width: int,terrain: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(density.size())
	if width<=0 or density.size()!=terrain.size() or density.size()!=width*width: return result
	for cell in range(density.size()):
		if density[cell]==0 or terrain[cell]==0: continue
		var x := cell%width
		var z := cell/width
		if Hash.coordinate(x,z,71,0,255)>=int(density[cell]): continue
		result[cell]=Hash.coordinate(x,z,7777,20,27)-19
	return result
