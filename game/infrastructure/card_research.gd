extends RefCounted
## Validate original provenance before injecting plain source research records.


static func content(executable_sha256: String,source_sha256: String,scope: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/card-research.json"))
	if not data is Dictionary or data.get("version")!=1 or data.get("executable_sha256")!=executable_sha256 or data.get("source_sha256")!=source_sha256 or not data.get("scopes",{}).has(scope): return {}
	var Research = preload("res://simulation/source_card_research.gd")
	if not Research.valid_rules(data.get("rules")): return {}
	for card: Variant in data["scopes"][scope]:
		if not Research.valid_card(card): return {}
	for sticker: Variant in data.get("stickers",[]):
		if not Research.valid_sticker(sticker): return {}
	if not preload("res://simulation/source_sticker_selection.gd").valid_records(data["scopes"][scope],data["stickers"]): return {}
	return preload("res://simulation/progression.gd").canonical_numbers({"rules":data["rules"],"cards":data["scopes"][scope],"stickers":data["stickers"],"unavailable":data["unavailable"][scope]})
