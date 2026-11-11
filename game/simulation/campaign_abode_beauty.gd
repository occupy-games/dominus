extends RefCounted
## Connects the source area refresh and beauty buff to campaign abode records.

const Fields = preload("res://simulation/source_map_fields.gd")
const Surroundings = preload("res://simulation/source_house_surroundings.gd")
const EnvironmentBuffs = preload("res://simulation/source_house_environment.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Surroundings.valid_rules(rules.get("surroundings")):
		return false
	var buff: Variant=rules.get("buff")
	return EnvironmentBuffs.valid([buff]) and buff["kind"]==2 and buff["field"]=="belief modifier" and buff["abode"]==1


static func rules_for(state: Dictionary) -> Dictionary:
	return state.get("progression",{}).get("rules",{}).get("abode_beauty",{})


static func refresh(state: Dictionary,homes: Array,area: Array=[],only_cached: bool=false) -> void:
	var rules := rules_for(state)
	if rules.is_empty():
		return
	var raster: Dictionary=state.get("map_fields",{"fields":{}})
	var surroundings: Dictionary=rules["surroundings"]
	var field := Fields.surroundings.bind(raster)
	var has_beauty: bool=not raster["fields"].get("1",{}).is_empty()
	for home: Dictionary in homes:
		if home.get("kind","")!="" or (only_cached and not home.has("beauty_fraction")):
			continue
		var radius := Terrain.f32(float(home.get("vision_radius",0.0)))
		var offset := (float(home.get("span",2))-1.0)*0.5
		var position := [Terrain.f32(float(home["x"])+offset),Terrain.f32(float(home["z"])+offset)]
		if not area.is_empty():
			var reach := radius+float(area[2])+float(surroundings["area_padding"])
			if Surroundings.area_distance_squared(position,area)>=reach*reach:
				continue
		var fraction := 0.0
		if has_beauty and Surroundings.valid_radius(radius):
			fraction=Surroundings.scan_beauty(position,radius,float(surroundings["beauty_threshold"]),field)
		if fraction>0.0:
			home["beauty_fraction"]=fraction
		else:
			home.erase("beauty_fraction")


static func refresh_expired(state: Dictionary,cells: Array) -> void:
	var first := Vector2(cells[0][0],cells[0][1])
	var bounds := Rect2(first,Vector2.ZERO)
	for cell: Array in cells:
		bounds=bounds.expand(Vector2(cell[0],cell[1]))
	var center := bounds.get_center()
	# Revisit cached samples near the expired terrain. The padding in the area
	# check covers the gap between the abode position and its integer scan origin.
	refresh(state,state["homes"],[center.x,center.y,bounds.size.length()*0.5],true)


static func belief_modifier(state: Dictionary,home: Dictionary,base: float) -> float:
	var rules := rules_for(state)
	var fraction := float(home.get("beauty_fraction",0.0))
	var trees := int(home.get("nearby_trees",0))
	var seeds := int(home.get("nearby_seed_trees",0))
	if (trees>0 or seeds>0) and state.has("opening"):
		var records: Array=state["opening"]["definition"].get("house_environment",[])
		if not records.is_empty():
			var values := {"belief modifier":base}
			var unlocked := func(id: String) -> bool: return Unlocks.enabled(state["progression"],id)
			EnvironmentBuffs.apply(values,records,{"special":false},false,[trees,seeds,0],fraction,unlocked)
			return values["belief modifier"]
	if rules.is_empty() or fraction==0.0:
		return base
	var buff: Dictionary=rules["buff"]
	if not Unlocks.enabled(state["progression"],buff["unlock"]):
		return base
	var amount := EnvironmentBuffs.contribution(buff,fraction)
	base=Terrain.f32(base)
	return Terrain.f32(base*amount if int(buff["operation"])==1 else base+amount)
