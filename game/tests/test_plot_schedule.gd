extends SceneTree

const Schedule = preload("res://simulation/source_plot_schedule.gd")
const Houses = preload("res://simulation/source_houses.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_schedule.json"))
	var profiles: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_house_selection.json"))["profiles"]
	var data: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()
	for example: Dictionary in fixture["marks"]:
		var state := Schedule.initial()
		Schedule.mark(state,int(example["cell"][0]),int(example["cell"][1]))
		var dirty: Array=[]
		for index in range(1024):
			if state["dirty"].has(str(index)): dirty.append(float(index))
		check(dirty==example["dirty"],"Original dirty neighborhood must match at %s"%[example["cell"]])
	for example: Dictionary in fixture["cases"]:
		var profile: Dictionary={}
		for entry: Dictionary in profiles:
			if entry["name"]==example["profile"]: profile=entry
		var limits := Houses.plot_limits(data["story"]["house_selection"],func(key: String) -> bool: return profile["unlocks"].has(key))
		var state := Schedule.initial()
		state["limits"]=example["previous"].duplicate(true)
		for index: float in example["dirty"]: state["dirty"][str(int(index))]=true
		var regions: Array=[]
		Schedule.dispatch(state,limits,func(tile: Vector2i) -> void: regions.append([float(tile.x),float(tile.y)]))
		check(regions==example["expected"]["regions"],"Original %s availability and dirty dispatch must match"%example["name"])
		check(state["dirty"].is_empty(),"Processed source dirty bits must clear")
	var state := Schedule.initial()
	state["limits"]={"sizes":[[4,4],[4,4],[4,4]],"minimum":4,"maximum":4,"biomes":7}
	state["dirty"]={"0":true}
	var seen: Array=[]
	Schedule.dispatch(state,state["limits"],func(tile: Vector2i) -> void:
		seen.append(tile)
		if tile==Vector2i.ZERO: state["dirty"]["32"]=true)
	check(seen==[Vector2i.ZERO,Vector2i(0,1)],"Later dirty rows raised during a scan must run in the same pass")
	print("Original plot schedule: %d neighborhoods, %d dispatch cases, %d failures"%[fixture["marks"].size(),fixture["cases"].size(),failures])
	quit(1 if failures else 0)
