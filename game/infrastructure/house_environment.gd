extends RefCounted

const EnvironmentBuffs = preload("res://simulation/source_house_environment.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func content(executable_sha256: String,source_sha256: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/house-environment.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256:
		return {}
	var rows: Variant=data.get("records")
	if not rows is Array or rows.is_empty():
		return {}
	for row: Variant in rows:
		if not row is Dictionary:
			return {}
		for field: String in ["value","cap"]:
			if not (row.get(field) is float or row.get(field) is int):
				return {}
			row[field]=Terrain.f32(float(row[field]))
	var rules: Variant=data.get("surroundings")
	if not preload("res://simulation/source_house_surroundings.gd").valid_rules(rules) or not EnvironmentBuffs.valid(rows):
		return {}
	return {"records":rows,"surroundings":rules}


static func records(executable_sha256: String,source_sha256: String) -> Array:
	return content(executable_sha256,source_sha256).get("records",[])
