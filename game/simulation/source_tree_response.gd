extends RefCounted
## Native planted-tree activation and plot occupancy after dirty terrain refresh.
## Runtime density regeneration and planted growth records are separate behavior.

const Terrain = preload("res://simulation/source_terrain.gd")


static func initial() -> Dictionary:
	return {"entries":{},"revision":0}


static func refresh(state: Dictionary,tiles: Dictionary,tree_tiles: Dictionary,rows: Dictionary,target: Callable,now: float) -> bool:
	var response: Dictionary=state["tree_response"]
	var sea := float(state["opening"]["definition"]["tree_response_config"]["sea_height"])
	var changed := false
	for tile: Vector2i in tiles:
		for cell: int in tree_tiles.get(tile,[]):
			var key := str(cell)
			if state["removed_trees"].has(key): continue
			var tree: Dictionary=state["trees"][int(rows[cell])]
			var sampled := Terrain.f32(float(target.call(tree)))
			var enabled: bool=sampled==0.0 or sampled==Terrain.f32(float(tree["source_y"])+sea)
			if enabled==response["entries"].get(key,{}).get("enabled",true): continue
			response["entries"][key]={"enabled":enabled,"changed_ms":Terrain.f32(Terrain.f32(now)*1000.0)}
			response["revision"]+=1
			changed=true
	return changed


static func valid_config(config: Variant) -> bool:
	if not config is Dictionary: return false
	for key: String in ["duration","sea_height","vertical_scale","minimum_scale","encouragement_scale"]:
		var value: Variant=config.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>80: return false
	return config["duration"]>0


static func valid(response: Variant,trees: Array,tick: int) -> bool:
	if not response is Dictionary or not response.get("entries") is Dictionary: return false
	if not preload("res://simulation/source_rock_motion.gd").is_integer(response.get("revision"),0,9223372036854775807): return false
	var cells := {}
	for tree: Dictionary in trees:
		if tree.has("source_y"): cells[str(int(tree["cell"]))]=true
	for key: Variant in response["entries"]:
		if not key is String or not cells.has(key): return false
		var entry: Variant=response["entries"][key]
		if not entry is Dictionary or not entry.get("enabled") is bool: return false
		var changed: Variant=entry.get("changed_ms")
		if not (changed is int or changed is float) or not is_finite(float(changed)) or changed<0 or changed>Terrain.f32(Terrain.f32(tick*0.1)*1000.0): return false
	return true
