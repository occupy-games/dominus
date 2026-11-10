extends RefCounted
## Detached currency intervals. Presentation never chooses progression thresholds.


static func interval(amount: int, levels: Array) -> Dictionary:
	var previous := 0
	var next := 0
	for threshold: int in levels:
		if threshold <= amount: previous = maxi(previous,threshold)
		elif next == 0 or threshold < next: next = threshold
	return {"amount":amount,"previous":previous,"next":next,"progress":clampf(float(amount-previous)/maxi(1,next-previous),0,1) if next>0 else 1.0}


static func snapshot(state: Dictionary) -> Dictionary:
	var levels := {"followers":[],"wheat":[],"ore":[]}
	var source_levels: Array = state.get("progression",{}).get("rules",{}).get("research_levels",[])
	if source_levels.is_empty():
		for row: Array in state.get("campaign",{}).get("population_unlocks",[]):
			if row.size()>1 and str(row[0]).is_valid_int(): levels["followers"].append(int(row[0]))
	for row: Dictionary in source_levels:
		var resource: String = row.get("resource","followers")
		if levels.has(resource): levels[resource].append(int(row["population"]))
	var result := {}
	for resource: String in levels:
		result[resource]=interval(state["followers"].size() if resource=="followers" else int(state.get(resource,0)),levels[resource])
	return result
