extends SceneTree

const Candidates = preload("res://simulation/source_build_candidates.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_build_candidates.json"))
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(not definition.is_empty(),"The campaign must inject native builder priorities and capacities")
	var values: Dictionary=definition["story"]["build_candidate_values"]
	var environment: Dictionary=definition["story"]["plot_environment"]
	check(Candidates.valid_values(values),"All resolved source candidate inputs must validate")
	for example: Dictionary in fixture["cases"]:
		var parameters := {"position":example.get("position",[157.0,119.0,6.0]),"radius":example.get("radius",12.0),"height_balance":example.get("height_balance",1.0),"priority_scale":example.get("priority_scale",1.0),"disabled":example.get("disabled",false),"actor_mode":example.get("actor_mode",0)}
		var unlocks: Array=example.get("unlocks",["PlotsAppear"])
		var unlocked := func(key: String) -> bool: return key=="HousesBiomeLocked" or key in unlocks
		var plots: Array=example["plots"].duplicate(true)
		for plot: Dictionary in plots: plot["height"]=plot.get("height",6.0)
		var allows := func(x: int,z: int,power: bool) -> bool:
			check(power,"The original builder must request its power/max influence predicate")
			for plot: Dictionary in plots:
				var half := float(plot["size"])*0.5
				if int(float(plot["x"])+half)==x and int(float(plot["z"])+half)==z: return bool(plot.get("influence",true))
			return false
		var raw_height := func(x: float,z: float) -> int:
			for plot: Dictionary in plots:
				var half := float(plot["size"])*0.5
				if float(plot["x"])+half==x and float(plot["z"])+half==z: return int(plot.get("raw_height",20))
			return 0
		var before: Array=plots.duplicate(true)
		var actual := Candidates.choose_plots(plots,parameters,definition["story"]["house_selection"],values,environment,unlocked,allows,raw_height)
		var expected: Dictionary=example["expected"].duplicate(true)
		expected["action"]=int(expected["action"])
		expected["plot"]=int(expected["plot"])
		expected["score"]=Terrain.f32(float(expected["score"]))
		check(actual==expected,"Original %s candidate and exact float32 score must match: %s / %s"%[example["name"],actual,expected])
		check(plots==before,"Candidate inspection must not reserve workers or mutate source plots")
	var broken := values.duplicate(true)
	broken["AbodeType_0_Rank_1"]["buildplotpriority"]=NAN
	check(not Candidates.valid_values(broken),"Invalid saved native builder priorities must reject")
	broken={"position":[0,0,0],"radius":1,"height_balance":1,"priority_scale":NAN,"disabled":false,"actor_mode":0}
	check(not Candidates.valid_parameters(broken),"Non-finite query priorities must reject before scoring")
	print("Original builder plot selection: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
