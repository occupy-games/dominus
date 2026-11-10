extends RefCounted
## Recovered 2.4 IDs, localized text and exact art references; images are lazy.

static var metadata: Dictionary = {}
static var images: Dictionary = {} # Weak references never pin off-screen textures.
static var image_loads := 0

const ALIASES := {
	"Card_Spirituality":"Card_GenerateBelief",
	"Card_MaxRank_2":"Card_AbodeType1_Rank1", "Card_DoubleClick":"Card_SmartSculpting",
	"Card_AbodeType_2":"Card_AbodeType2_Rank1", "Card_GodPower_Sculpting":"Card_Sculpting",
	"Card_GodPower_TotemActivate":"Card_Adv_Leash_1", "Card_TotemCapacity":"Card_Adv_Leash_2",
	"Card_BuildingMaterial_1":"Sticker_BuildingMaterial_1", "Card_BuildingMaterial_2":"Sticker_BuildingMaterial_2",
	"Card_Tools_1":"Sticker_Tools_1", "Card_Tools_2":"Sticker_Tools_1", "Card_Tools_3":"Sticker_Tools_2",
	"Card_Textile_1":"Sticker_Textile_1", "Card_Textile_2":"Sticker_Textile_2", "Card_Textile_3":"Sticker_Textile_3",
	"Card_ReligiousObject_1":"Sticker_ReligiousObject_3", "Card_ReligiousObject_2":"Sticker_ReligiousObject_1", "Card_ReligiousObject_3":"Sticker_ReligiousObject_2",
	"Card_Food_1":"Sticker_Food_1", "Card_Food_2":"Sticker_Food_2", "Card_Writing_1":"Sticker_Writing_1", "Card_Writing_2":"Sticker_Writing_2",
	"Card_Seeds":"Sticker_Currency_1", "Card_Container_1":"Sticker_Currency_2"}


static func entries() -> Dictionary:
	if metadata.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/cards_24/catalog.json"))
		if raw is Dictionary: metadata = raw.get("cards", {})
	var result := {}
	var frame: Texture2D = preload("res://infrastructure/ui_content.gd").textures().get("GFX_CardSmallBorders_01.png")
	for id: String in metadata:
		var entry: Dictionary = metadata[id].duplicate(false)
		entry["frame"] = null if entry.get("sticker", false) else frame
		entry["resolve_texture"] = image
		entry["bindings"] = [id]
		result[id] = entry
	for id: String in ALIASES:
		var canonical: String = ALIASES[id]
		if not result.has(canonical): continue
		result[canonical]["bindings"].append(id)
		var entry: Dictionary = result[canonical].duplicate(false)
		entry["id"] = id
		result[id] = entry
	return result


static func image(entry: Dictionary, detail: bool = false) -> Texture2D:
	if not entry.get("available", false): return null
	var path: String = entry.get("texture_path", "") if detail else entry.get("thumbnail_path", "")
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var key := path + (":detail" if detail else ":thumb")
	if images.has(key):
		var live: Variant = images[key].get_ref()
		if live != null: return live
	var texture: Texture2D = load(path)
	if detail and not entry.get("sticker", false):
		var cropped := AtlasTexture.new()
		cropped.atlas = texture
		cropped.region = Rect2(0,61,256,390)
		texture = cropped
	images[key] = weakref(texture)
	image_loads += 1
	return texture


static func live_image_count() -> int:
	var count := 0
	for reference: WeakRef in images.values():
		if reference.get_ref() != null: count += 1
	return count
