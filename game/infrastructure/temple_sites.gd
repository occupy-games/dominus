extends RefCounted
## Resolve the authored source record without creating a replacement model.


static func sites(scope: String,source_sha256: String) -> Array:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-sites.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("source_sha256")!=source_sha256 or not data.get("scopes") is Dictionary: return []
	if not data.get("ambiguous_ids",{}).get(scope,[]).is_empty(): return []
	var models: Dictionary={}
	for model: Dictionary in preload("res://infrastructure/asset_catalog.gd").model_records().get("models",[]):
		if not model.get("building_assembly",{}).is_empty(): models[model["id"]]=true
	var result: Array=[]
	for raw: Dictionary in data["scopes"].get(scope,[]):
		var site: Dictionary=preload("res://simulation/progression.gd").canonical_numbers(raw.duplicate(true))
		site["model_id"]=""
		var id: String=str(site["model"])+".group.bin:dff1563f"
		if not str(site["model"]).is_empty() and models.has(id): site["model_id"]=id
		result.append(site)
	return result
