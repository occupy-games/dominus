extends RefCounted
## Original labels/illustrations only. Live numeric values arrive from simulation.

static var source: Dictionary = {}


static func content() -> Dictionary:
	if source.is_empty():
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/ui/building-info.json"))
		if value is Dictionary and value.get("version")==1: source=value
	return source


static func record(stats: Dictionary) -> Dictionary:
	var records: Dictionary=content().get("records",{})
	var key := ""
	if stats.get("entity")=="temple" and not str(stats.get("site_type","")).is_empty(): key="Temple_"+str(stats["site_type"])
	elif stats.get("entity")=="settlement": key="Settlement_"+str(stats["role"]).capitalize()
	elif stats.get("kind","")=="shrine": key="Shrine_LandExpansion" if stats.get("reward_card","")=="Card_Expansion" else "Shrine_GodPower"
	elif stats.get("kind","") in ["farm","mine"]: key="%s_Rank_%d"%[str(stats["kind"]).capitalize(),int(stats.get("rank",1))]
	elif stats.get("kind","")=="":
		# Legacy campaigns retain their original house names. Resolve those names
		# against the supplied current table; never substitute unrelated artwork.
		for id: String in records:
			if not str(stats.get("name","")).strip_edges().is_empty() and str(records[id]["title"]).strip_edges().nocasecmp_to(str(stats["name"]).strip_edges())==0: key=id; break
		if key.is_empty() and int(stats.get("family",0))==0 and int(stats.get("rank",1))==1: key="AbodeType_0_Rank_1"
	# Legacy campaign/save descriptors use the same older type names resolved
	# by progression_content for their models. Resolve info from that class too.
	if stats.get("entity")=="temple" and stats.get("site_type","") in ["shrine1x1","shrine2x2","shrineLandExp"]:
		key="Temple_Shrine_LandExp" if stats.get("reward_card","")=="Card_Expansion" else "Temple_Shrine_GodPower"
	var result: Dictionary=records.get(key,{}).duplicate(true)
	if stats.get("entity")=="temple":
		var labels: Dictionary=content().get("labels",{})
		if labels.has(stats.get("title_key","")): result["title"]=labels[stats["title_key"]]
	if result.has("texture_path"): result["texture"]=load(result["texture_path"])
	return result
