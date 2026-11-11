extends RefCounted

const Source = preload("res://simulation/source_house_base_stats.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func load_content(houses: Dictionary,selection: Dictionary) -> Dictionary:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-base-stats.json"))
	if not metadata is Dictionary or metadata.get("version")!=1 or metadata.get("executable_sha256")!=houses["native"]["executable_sha256"] or not metadata.get("rules") is Dictionary:
		return {}
	for key: String in ["source_sha256","table_sha256"]:
		if not metadata.has(key) or metadata[key]!=houses.get(key) or metadata[key]!=selection.get(key):
			return {}
	var records: Array=[]
	for selected: Dictionary in selection["rows"]:
		var record: Dictionary=houses["records"].get(selected["id"],{})
		if not record.get("values") is Dictionary:
			return {}
		var values: Dictionary=record["values"].duplicate()
		for field: String in values:
			if houses["native"]["fields"][field]["arithmetic"]=="float32":
				values[field]=Terrain.f32(float(values[field]))
		records.append({"id":selected["id"],"index":selected["index"],"values":values})
	var result := {"rules":metadata["rules"],"rows":records}
	return result if Source.valid(result) else {}
