extends SceneTree

const Brush = preload("res://simulation/source_beautify.gd")
const Raster = preload("res://simulation/source_influence.gd")
const Fields = preload("res://simulation/source_map_fields.gd")
const Numbers = preload("res://simulation/progression.gd")
const Content = preload("res://infrastructure/beautify.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/source_beautify.json")
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(raw))
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var rules := Content.rules(fixture["executable_sha256"],definition["story"]["source_sha256"])
	check(not rules.is_empty(),"Beautify must load its original rule provenance")
	for item: Dictionary in fixture["cases"]:
		var raster := Raster.initial()
		for entry: Array in item["bytes"]:
			Fields.write_byte(raster,int(entry[0]),int(entry[1]),int(entry[2]),int(entry[3]))
		var x := float(item["point"][0])
		var z := float(item["point"][1])
		if item.get("influence",true):
			Fields.write_byte(raster,6 if item.get("power_only",false) else 4,int(x),int(z),128)
		var ground := func(px: int,pz: int) -> float:
			return float(item.get("ground",{}).get("%d,%d"%[px,pz],item.get("height",20.0)))
		var events: Array=[]
		var applied := false
		if item.get("hit",true) and Raster.allows(raster,int(x),int(z),true,{"decode_scale":1.0/128.0,"threshold":0.5}):
			var plan := Brush.quote(raster,x,z,rules,item.get("configuration",{}),ground)
			check(not plan.is_empty(),str(item["name"])+" must produce a terrain plan")
			events.append(["payment",plan["charge"],8])
			if item.get("paid",true):
				events.append(["brush"]+plan["rect"])
				Brush.apply(raster,plan,rules,ground,events)
				applied=true
		var expected: Dictionary=item["expected"]
		check(applied==expected["ok"],str(item["name"])+" acceptance")
		check(Numbers.canonical_numbers(events)==expected["events"],"%s callback order and amount: %s / %s"%[item["name"],events,expected["events"]])
		var reads: Array=[]
		for probe: Array in expected["probes"]:
			reads.append(Fields.read(raster,int(probe[0]),int(probe[1]),int(probe[2])))
		check(Numbers.canonical_numbers(reads)==expected["reads"],str(item["name"])+" exact original field bytes")
		var notices: Dictionary=raster.get("field_notifications",{"serial":0,"cells":[]})
		check(Numbers.canonical_numbers(notices)=={"serial":expected["serial"],"cells":expected["cells"]},str(item["name"])+" notification order")
	print("Original Beautify terrain action: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
