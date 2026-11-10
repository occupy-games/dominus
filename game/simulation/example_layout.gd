extends RefCounted
## Deterministic exhibit placement from injected source bounds. No asset access.

const SOURCE_SCALE := 0.003
const GAP := 5.0


func build(descriptors: Array) -> Dictionary:
	var grouped := {}
	var excluded: Array = []
	for descriptor: Dictionary in descriptors:
		if descriptor.get("material_status", "") != "source_texture":
			excluded.append(descriptor["id"])
			continue
		var category: String = descriptor.get("category", "Uncategorized")
		if not grouped.has(category): grouped[category] = {}
		var source: String = descriptor["source"]
		if not grouped[category].has(source): grouped[category][source] = []
		grouped[category][source].append(descriptor)
	var categories: Array = grouped.keys()
	categories.sort()
	var blocks: Array = []
	for category: String in categories:
		var items: Array = []
		var sources: Array = grouped[category].keys()
		sources.sort()
		var cursor := Vector2.ZERO
		var row_depth := 0.0
		var extent := Vector2.ZERO
		var area := 0.0
		for source: String in sources:
			var models: Array = grouped[category][source]
			var cell := Vector2(8, 8)
			for model: Dictionary in models:
				var low: Array = model.get("assembled_bounds", model["bounds"])[0]
				var high: Array = model.get("assembled_bounds", model["bounds"])[1]
				cell.x = maxf(cell.x, (high[0] - low[0]) * SOURCE_SCALE + GAP)
				cell.y = maxf(cell.y, (high[2] - low[2]) * SOURCE_SCALE + GAP)
			area += cell.x * cell.y * models.size()
		var target_width := maxf(120, sqrt(area) * 1.4)
		for source: String in sources:
			var models: Array = grouped[category][source]
			models.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
			var cell := Vector2(8, 8)
			for model: Dictionary in models:
				var low: Array = model.get("assembled_bounds", model["bounds"])[0]
				var high: Array = model.get("assembled_bounds", model["bounds"])[1]
				cell.x = maxf(cell.x, (high[0] - low[0]) * SOURCE_SCALE + GAP)
				cell.y = maxf(cell.y, (high[2] - low[2]) * SOURCE_SCALE + GAP)
			var columns := mini(8, ceili(sqrt(models.size())))
			var group_size := cell * Vector2(columns, ceili(models.size() / float(columns)))
			if cursor.x > 0 and cursor.x + group_size.x > target_width:
				cursor = Vector2(0, cursor.y + row_depth + 12)
				row_depth = 0
			for index in range(models.size()):
				var model: Dictionary = models[index]
				var low: Array = model.get("assembled_bounds", model["bounds"])[0]
				var high: Array = model.get("assembled_bounds", model["bounds"])[1]
				var size := Vector3(high[0] - low[0], high[1] - low[1], high[2] - low[2]) * SOURCE_SCALE
				var center := Vector2((high[0] + low[0]) * 0.5, (high[2] + low[2]) * 0.5) * SOURCE_SCALE
				var uv := cursor + cell * Vector2(index % columns + 0.5, index / columns + 0.5)
				items.append({"id": model["id"], "name": model["name"], "source": source,
					"environment": model.get("environment", "land"),
					"family": model.get("family", model["name"]), "category": category,
					"uv": uv, "size": size, "offset": Vector3(-center.x, -float(low[1]) * SOURCE_SCALE, -center.y),
					"footprint": Rect2(uv - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))})
			cursor.x += group_size.x + 12
			row_depth = maxf(row_depth, group_size.y)
			extent.x = maxf(extent.x, cursor.x)
			extent.y = maxf(extent.y, cursor.y + group_size.y)
		blocks.append({"name": category, "size": extent, "items": items})
	var column_width := 0.0
	for block: Dictionary in blocks: column_width = maxf(column_width, block["size"].x + 30)
	var items: Array = []
	var regions: Array = []
	var cursor := Vector2.ZERO
	var row_depth := 0.0
	var total := Vector2.ZERO
	for index in range(blocks.size()):
		var block: Dictionary = blocks[index]
		if index > 0 and index % 3 == 0:
			cursor = Vector2(0, cursor.y + row_depth + 30)
			row_depth = 0
		regions.append({"name": block["name"], "bounds": Rect2(cursor, block["size"]), "count": block["items"].size()})
		for item: Dictionary in block["items"]:
			item["uv"] += cursor
			item["footprint"].position += cursor
			items.append(item)
		total = total.max(cursor + block["size"])
		row_depth = maxf(row_depth, block["size"].y)
		cursor.x += column_width
	return {"surface": "plane", "items": items, "categories": regions, "bounds": Rect2(Vector2(-15, -15), total + Vector2(30, 30)), "excluded": excluded}
