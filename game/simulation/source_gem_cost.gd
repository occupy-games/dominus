extends RefCounted
## Construction prices use the source gem curve and single-precision rounding.

const Terrain = preload("res://simulation/source_terrain.gd")


static func valid(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("prices") is Array or rules["prices"].size()<2 or rules["prices"].size()>16: return false
	if not rules.get("labels") is Dictionary: return false
	for key: String in ["home","farm","mine","temple","title","currency"]:
		if not rules["labels"].get(key) is String or rules["labels"][key].is_empty(): return false
	var padding: Variant=rules.get("completion_padding")
	if not (padding is int or padding is float) or not is_finite(float(padding)) or padding<=0 or padding>1: return false
	var previous: Array=[-1,-1,-1]
	for row: Variant in rules["prices"]:
		if not row is Array or row.size()!=3: return false
		for column in range(3):
			var value: Variant=row[column]
			if not (value is int or value is float) or not is_finite(float(value)) or value<=previous[column] or value>1000000000: return false
		previous=row
	return rules["prices"][0]==[0,0,0]


static func price(rules: Dictionary, seconds: float, ark: bool=false) -> int:
	var remaining := Terrain.f32(seconds)
	if remaining<=0.0: return 0
	var prices: Array=rules["prices"]
	var column:=2 if ark else 1
	var upper:=1
	while upper<prices.size()-1 and remaining>float(prices[upper][column]):
		upper+=1
	var lower: Array=prices[upper-1]
	var higher: Array=prices[upper]
	var fraction:=Terrain.f32((remaining-float(lower[column]))/(float(higher[column])-float(lower[column])))
	return ceili(Terrain.f32(float(lower[0])+fraction*(float(higher[0])-float(lower[0]))))


static func remaining(home: Dictionary, tick_seconds: float, builders: int, falloff: float) -> float:
	var duration := Terrain.f32(float(home["build_ticks"])*tick_seconds)
	var work := Terrain.f32((float(home["progress"])+float(home.get("work_accumulator",0)))*tick_seconds)
	if home.get("kind")=="shrine":
		work=float(home.get("temple_work",work))
		var speed:=Terrain.f32(pow(float(maxi(1,builders)),Terrain.f32(falloff)))
		return Terrain.f32(Terrain.f32(duration-work)/speed)
	return Terrain.f32(duration-work)
