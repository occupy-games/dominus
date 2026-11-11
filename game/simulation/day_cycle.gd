extends RefCounted
## Source day lengths and fixed simulation time; no wall clock or renderer.


static func initialize(definition: Dictionary) -> Dictionary:
	return {"time":float(definition["functions"]["Midday"]["value"]),"speed":0.0,"waiters":[]}


static func advance(clock: Dictionary,definition: Dictionary,seconds: float) -> Array:
	var period := float(definition["period"])
	var previous := float(clock["time"])
	var delta := maxf(0,seconds*float(clock["speed"]))
	var elapsed := previous+delta
	if elapsed>=period: clock["days"]=int(clock.get("days",0))+floori(elapsed/period)
	clock["time"]=fposmod(elapsed,period)
	var due: Array = []
	for waiter: Dictionary in clock["waiters"].duplicate(true):
		var distance := fposmod(float(waiter["time"])-previous,period)
		if distance<0.0000001: distance=period
		if distance<=delta+0.0000001:
			clock["waiters"].erase(waiter)
			due.append(waiter)
	return due


static func valid(clock: Variant,definition: Dictionary) -> bool:
	var period: Variant = definition.get("period")
	if not (period is int or period is float) or not is_finite(float(period)) or period<=0: return false
	if not clock is Dictionary or not clock.get("waiters") is Array or clock["waiters"].size()>1024: return false
	for key: String in ["time","speed"]:
		if not (clock.get(key) is int or clock.get(key) is float) or not is_finite(float(clock[key])) or clock[key]<0: return false
	if clock["time"]>=float(period) or clock["speed"]>10000: return false
	if not preload("res://simulation/source_plot_schedule.gd").integer_between(clock.get("days",0),0,2147483647): return false
	for waiter: Variant in clock["waiters"]:
		if not waiter is Dictionary or not (waiter.get("time") is int or waiter.get("time") is float) or not is_finite(float(waiter["time"])): return false
		if waiter["time"]<0 or waiter["time"]>=float(definition["period"]) or not waiter.get("args") is Array: return false
		if not (waiter.get("callback") is String or waiter.get("callback") is Dictionary): return false
	return true
