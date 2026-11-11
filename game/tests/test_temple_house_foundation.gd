extends "res://tests/test_temple_house_propagation.gd"

const Foundation = preload("res://simulation/source_building_foundation.gd")
var foundation_rules: Dictionary={}


func fixture_path() -> String:
	return "res://tests/fixtures/source_temple_house_foundation.json"


func test_name() -> String:
	return "Original house shrine foundation"


func restore_state(saved: Variant) -> Dictionary:
	return Propagation.restore_house_foundation(saved)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path()))
	foundation_rules=preload("res://infrastructure/building_foundation.gd").rules(fixture["executable_sha256"])
	check(not foundation_rules.is_empty(),"Composed house foundation rules must match the source executable")
	if foundation_rules.is_empty(): quit(1); return
	super._initialize()


func service(name: String,args: Array) -> Variant:
	var result: Variant=super.service(name,args)
	events[-1].append(int(current["uneven_count"]))
	if name=="terrain_overlay": return bool(example.get("overlay_available",false))
	return result


func overlay(x: int,z: int) -> Dictionary:
	service("overlay",[x,z])
	var data: Dictionary=example.get("overlay",{})
	return data.get("values",{}).get("%d,%d"%[x,z],data.get("default",{"found":false,"height":0.0})).duplicate(true)


func ground(x: int,z: int) -> float:
	service("ground",[x,z])
	var data: Dictionary=example.get("ground",{})
	return float(data.get("values",{}).get("%d,%d"%[x,z],data.get("default",0.0)))


func advance_case() -> bool:
	events=[]
	var sites: Array=example["sites"].duplicate(true)
	if example.has("unlocked"):
		for site: Dictionary in sites:
			check(Modifiers.refresh(site,example["records"],unlocked,modifier_service),"Original shrine unlock refresh must feed stored house masks")
	return Propagation.refresh_house_foundation(current,sites,example.get("owners",{}),foundation_rules,service,overlay,ground)


func compare_case(expected: Dictionary,label: String) -> void:
	super.compare_case(expected,label)
	if not current["reference_attached"]:
		var region := Foundation.bounds(current,foundation_rules)
		check([region.position.x,region.position.y,region.size.x,region.size.y]==Numbers.canonical_numbers(expected["bounds"]),label+" actual foundation bounds inside house callback")
	else: check(expected["bounds"].is_empty(),label+" attached references must not run the foundation scan")


func additional_checks() -> void:
	var before := current.duplicate(true)
	current["nav_size"]=1025
	var invalid := current.duplicate(true)
	example={"sites":[]}
	check(not advance_case() and current==invalid and events.is_empty(),"Invalid later foundation state rejects before stored masks clear")
	current=before
