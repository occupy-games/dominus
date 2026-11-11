extends RefCounted
## Original terrace-local spread, with source field 3 and per-cast membership.

const Fields = preload("res://simulation/source_map_fields.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const CARD := "Card_Adv_Swamp_1"
const POWER := "GodPower_Swamp"
const DIRECTIONS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or rules.get("card")!=CARD or rules.get("power")!=POWER: return false
	for key: String in ["population","belief","max_tiles","max_puddle_size"]:
		if not Numbers.integer_between(rules.get(key),1,100000): return false
	for key: String in ["min_radius","max_radius","seconds","max_delta","expansion","min_blight","max_blight","blight_per_second","elevation_tolerance","bounds_margin","timeout"]:
		var value: Variant=rules.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<=0.0: return false
	if not rules.get("initial") is Array or rules["max_radius"]>32.0 or rules["max_puddle_size"]>32: return false
	if not Numbers.integer_between(rules.get("min_puddle_size"),0,int(rules["max_puddle_size"])): return false
	if rules["min_radius"]>rules["max_radius"] or rules["min_blight"]>=rules["max_blight"] or rules["max_blight"]>1.0: return false
	if not rules.get("clips") is Dictionary or not rules.get("clear_hint") is String or not rules.get("damage") is Dictionary: return false
	for role: String in ["swamp_stand","swamp_struggle","swamp_die","swamp_sink"]:
		var duration: Variant=rules["clips"].get(role)
		if not (duration is float or duration is int) or not is_finite(float(duration)) or float(duration)<=0.0: return false
	for key_: String in ["drown_threshold","sculpt_clear_chance"]:
		var value: Variant=rules.get(key_)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0.0 or float(value)>1.0: return false
	for race: String in ["Brown Head","Red Head","Champion","Astari","NakedRace"]:
		var damage: Variant=rules["damage"].get(race)
		if not (damage is float or damage is int) or not is_finite(float(damage)) or float(damage)<0.0: return false
	for point: Variant in rules["initial"]:
		if not point is Array or point.size()!=2: return false
		for coordinate: Variant in point:
			if not Numbers.integer_between(coordinate,0,1023): return false
	return true


static func key(x: int,z: int,width: int) -> String:
	return str(z*width+x)


static func start(x: float,z: float,raw_height: int,until: int,width: int,raster: Dictionary) -> Dictionary:
	var px:=Terrain.f32(x)
	var pz:=Terrain.f32(z)
	var cell:=key(int(px),int(pz),width)
	Fields.overwrite(raster,1,int(px),int(pz),0.0)
	Fields.overwrite(raster,3,int(px),int(pz),1.0)
	return {"x":px,"z":pz,"raw_height":raw_height,"until":until,"progress":0.0,"radius":0.0,"count":0,"cells":{cell:true}}


static func has_neighbor(cells: Dictionary,x: int,z: int,width: int) -> bool:
	for direction: Vector2i in DIRECTIONS:
		var px:=x+direction.x
		var pz:=z+direction.y
		if px>=0 and pz>=0 and px<width and pz<width and cells.has(key(px,pz,width)): return true
	return false


static func spread(cast: Dictionary,raster: Dictionary,rules: Dictionary,ground: Callable,width: int,seconds: float) -> Array[Vector2i]:
	var changed: Array[Vector2i]=[]
	if float(cast["progress"])>=1.0: return changed
	var dt:=Terrain.f32(seconds)
	var progress:=minf(1.0,Terrain.f32(float(cast["progress"])+minf(dt,float(rules["max_delta"]))/float(rules["seconds"])))
	cast["progress"]=progress
	var radius:=Terrain.f32(minf(float(rules["max_radius"]),lerpf(float(rules["min_radius"]),float(rules["max_radius"]),progress*float(rules["expansion"]))))
	cast["radius"]=radius
	var squared:=Terrain.f32(radius*radius)
	var cx: float=cast["x"]
	var cz: float=cast["z"]
	var margin: float=rules["bounds_margin"]
	var min_x:=maxi(0,int(cx-radius))
	var max_x:=mini(width,int(cx+radius+margin))
	var min_z:=maxi(0,int(cz-radius))
	var max_z:=mini(width,int(cz+radius+margin))
	var cells: Dictionary=cast["cells"]
	var height:=Terrain.surface_height(int(cast["raw_height"]))
	for z in range(min_z,max_z):
		var dz:=Terrain.f32(z-cz)
		for x in range(min_x,max_x):
			var dx:=Terrain.f32(x-cx)
			var distance:=Terrain.f32(dx*dx+dz*dz)
			if distance>=squared: continue
			var target:=Terrain.f32((1.0-distance/squared)*float(rules["max_blight"]))
			if target<=float(rules["min_blight"]): continue
			if absf(Terrain.surface_height(int(ground.call(x,z)))-height)>float(rules["elevation_tolerance"]): continue
			var cell:=key(x,z,width)
			if not cells.has(cell):
				if int(cast["count"])>=int(rules["max_tiles"]) or not has_neighbor(cells,x,z,width): continue
				cells[cell]=true
				cast["count"]+=1
			var previous:=Fields.read(raster,3,x,z)
			var value:=Terrain.f32(previous+dt*float(rules["blight_per_second"])) if previous<target else previous
			var dirty:=Fields.byte_at(raster,1,x,z)>0
			if dirty: Fields.overwrite(raster,1,x,z,0.0)
			if int(value*Fields.BYTE_SCALE)!=int(previous*Fields.BYTE_SCALE):
				Fields.overwrite(raster,3,x,z,value)
				dirty=true
			if dirty: changed.append(Vector2i(x,z))
	return changed
