extends RefCounted
## Shared authoritative site costs and completion gates. Temple repair remains
## a follower construction task; presentation never completes a site or pays it.


static func footprint(site: Dictionary) -> Rect2i:
	var offset := 0.0 if site.get("source_center",false) else 0.5
	var center := Vector2(float(site["x"])+offset,float(site["z"])+offset)
	var dimensions := Vector2(maxf(1,float(site.get("width",2))),maxf(1,float(site.get("depth",site.get("width",2)))))
	var left := Vector2i(floori(center.x-dimensions.x*0.5+0.5),floori(center.y-dimensions.y*0.5+0.5))
	var right := Vector2i(ceili(center.x+dimensions.x*0.5+0.5),ceili(center.y+dimensions.y*0.5+0.5))
	return Rect2i(left,right-left)


static func costs(state: Dictionary,site: Dictionary) -> Dictionary:
	var result := {"ok":true,"costs":{},"missing":{}}
	for pair: Array in [["food_cost","wheat"],["ore_cost","ore"]]:
		var value: Variant=site.get(pair[0],0)
		if not preload("res://simulation/source_plot_schedule.gd").integer_between(value,0,4294967295): return {"ok":false,"costs":{},"missing":{}}
		var count := int(value)
		if count==0: continue
		result["costs"][pair[1]]=count
		if int(state.get(pair[1],0))<count:
			result["ok"]=false
			result["missing"][pair[1]]=count-int(state.get(pair[1],0))
	return result


static func completed(progression: Dictionary,id: String) -> bool:
	for site: Dictionary in progression.get("shrines",[]):
		if site["id"]==id: return bool(site.get("complete",false))
	return false


static func complete(progression: Dictionary,id: String) -> bool:
	for site: Dictionary in progression.get("shrines",[]):
		if site["id"]!=id or not site.get("started",false) or site.get("complete",false): continue
		site["complete"]=true
		progression["revision"]=int(progression.get("revision",0))+1
		return true
	return false
