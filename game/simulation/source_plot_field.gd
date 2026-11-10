extends RefCounted
## Lossless source byte-field representation, injected without asset access.

const Schedule = preload("res://simulation/source_plot_schedule.gd")


static func at(field: Dictionary,x: int,z: int) -> int:
	if x<0 or z<0 or x>=1024 or z>=1024: return int(field["default"])
	return int(field["values"].get(str(z*1024+x),field["default"]))


static func valid(field: Variant) -> bool:
	if not field is Dictionary or not Schedule.integer_between(field.get("default"),0,255) or not field.get("values") is Dictionary or not field.get("sha256") is String or field["sha256"].length()!=64: return false
	for key: Variant in field["values"]:
		if not key is String or not key.is_valid_int() or str(int(key))!=key or not Schedule.integer_between(int(key),0,1024*1024-1): return false
		if not Schedule.integer_between(field["values"][key],0,255) or int(field["values"][key])==int(field["default"]): return false
	return true
