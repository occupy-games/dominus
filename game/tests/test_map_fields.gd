extends "res://tests/test_house_surroundings.gd"

const MapFields = preload("res://simulation/source_map_fields.gd")
const Influence = preload("res://simulation/source_influence.gd")
const InfluenceAreas = preload("res://simulation/source_influence_areas.gd")
const World = preload("res://simulation/world.gd")


func compare_field_stage(raster: Dictionary,stage: Dictionary,probes: Array) -> void:
	for op: Dictionary in stage["writes"]:
		var protected_tile: bool=op.get("checked",false) and op.get("protected",false)
		MapFields.overwrite(raster,int(op["kind"]),int(op["x"]),int(op["z"]),float(op["value"]),protected_tile)
	var actual: Array=[]
	for probe: Array in probes:
		var kind := int(probe[0])
		var x := int(probe[1])
		var z := int(probe[2])
		actual.append(MapFields.surroundings("blight",x,z,raster) if kind==-1 else MapFields.read(raster,kind,x,z))
	var expected: Dictionary=stage["expected"]
	check(Numbers.canonical_numbers(actual)==expected["reads"],"Original map field values and tile coordinates")
	check(Numbers.canonical_numbers(raster["field_notifications"])=={"serial":expected["serial"],"cells":expected["cells"]},"Original notification count and coordinate order")
	var layers := {}
	for kind: String in raster["fields"]:
		if raster["fields"][kind].is_empty():
			continue
		var tiles: Array=[]
		for tile: String in raster["fields"][kind]:
			tiles.append(int(tile))
		tiles.sort()
		layers[kind]=tiles
	check(layers==expected["layers"],"Original sparse tile allocation")


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_map_fields.json")
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(raw))
	var raster := Influence.initial()
	raster["field_notifications"]={"serial":fixture["serial"],"cells":[]}
	for stage: Dictionary in fixture["sequence"]:
		compare_field_stage(raster,stage,fixture["probes"])
		var saved := JSON.stringify(codec.encode_numbers(Influence.export_state(raster)))
		raster=Influence.restore(codec.decode_numbers(JSON.parse_string(saved)))
		check(not raster.is_empty(),"Source map tiles and notifications must restore")
	var areas := InfluenceAreas.initial([])
	areas["raster"]=raster
	var expected_map: Dictionary=raster["fields"]["1"].duplicate(true)
	InfluenceAreas.advance(areas,[],{},func(_name: String) -> bool: return true,0.0,[],true,true)
	check(raster["fields"]["1"]==expected_map and raster["fields"]["4"].is_empty() and raster["fields"]["6"].is_empty(),"Influence rebuild must preserve beautification tiles")
	check(raster["field_notifications"]["cells"].size()==128,"Rebuild must preserve the original pending map notifications")
	var refresh_data: Dictionary=source_floats(fixture["surroundings"])
	raster=Influence.initial()
	for item: Array in refresh_data["bytes"]:
		MapFields.write_byte(raster,int(item[0]),int(item[1]),int(item[2]),int(item[3]))
	surroundings_pool=HousePool.restore(refresh_data["initial"])
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var definition: Dictionary=opening["story"].duplicate(true)
	for key: String in refresh_data["radii"]:
		definition["house_base_stats"]["rows"][int(key)]["values"]["visionradius"]=float(refresh_data["radii"][key])
	var services := {"unlocked":func(_name: String) -> bool: return false,"query":query,"release":release,"raster":raster}
	check(Surroundings.refresh_pool(surroundings_pool,definition,{},services,refresh_data["area"]),"House refresh must read the concrete source map")
	check(Numbers.canonical_numbers(surroundings_pool)==refresh_data["expected"],"Native house refresh over the actual map bytes")
	var random := RandomNumberGenerator.new()
	random.seed=2026
	var world := World.new()
	world.initialize({"campaign_data":opening},random)
	var world_map: Dictionary=world._state["source_influence"]["raster"]
	MapFields.overwrite(world_map,2,160,120,1.5)
	check(world._source_plot_field_at(160,120,15)["blight"]==0.0,"The plot rule uses field 5 separately from the combined house sample")
	MapFields.overwrite(world_map,5,160,120,0.75)
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"The authored world must restore additional map fields")
	check(restored._source_plot_field_at(160,120,15)["blight"]==0.75,"The actual plot query must read the saved field 5 byte")
	print("Original map fields: %d write stages, %d probes per stage, saved tiles and house refresh, %d failures"%[fixture["sequence"].size(),fixture["probes"].size(),failures])
	quit(1 if failures else 0)
