extends SceneTree
const Source=preload("res://infrastructure/campaign_content.gd")
const Constants=preload("res://infrastructure/live_constants.gd")
const World=preload("res://simulation/world.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message); failures+=1
func rewrite(path: String,column: String,id: String,value: String) -> void:
	var file := FileAccess.open(path,FileAccess.READ)
	var header := file.get_csv_line()
	var rows: Array=[]
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size()!=header.size(): continue
		if row[0]==id: row[header.find(column)]=value
		rows.append(row)
	file.close()
	file=FileAccess.open(path,FileAccess.WRITE)
	file.store_csv_line(header)
	for row: PackedStringArray in rows: file.store_csv_line(row)
	file.close()
func run() -> void:
	var directory := "res://../build/three-unit-table-test"
	var constants := Constants.new()
	constants.path=directory+"/Update.csv"
	var source := Source.homeworld()
	constants.initialize(source["progression_rules"])
	for filename: String in ["Adobes.csv","Followers.csv","Update.csv"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(directory+"/"+filename))
	check(constants.ensure_file()["ok"],"Create exactly three editable tables")
	for filename: String in ["Adobes.csv","Followers.csv","Update.csv"]: check(FileAccess.file_exists(directory+"/"+filename),"Missing table "+filename)
	var file := FileAccess.open(directory+"/Adobes.csv",FileAccess.READ)
	var header := file.get_csv_line()
	var shelter := file.get_csv_line()
	var hut := file.get_csv_line()
	file.close()
	check(header.slice(0,6)==PackedStringArray(["House Rank","Capacity","Vision Radius","Build Capacity","Build Time","Build Priority"]),"Adobes must use the columns visible in the original video")
	check(shelter[0]=="Shelter" and shelter[4]=="15" and hut[0]=="Coastal Hut" and hut[4]=="45","Visible reference values must be present as actual unit rows")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":source},random)
	var parsed := constants.read()
	check(parsed.get("ok",false),"Read all three tables")
	check(world.reconfigure(parsed.get("changes",[]))["ok"],"Apply all three tables")
	rewrite(directory+"/Adobes.csv","Capacity","Shelter","12.5")
	rewrite(directory+"/Adobes.csv","Build Time","Shelter","2")
	rewrite(directory+"/Adobes.csv","Build Capacity","Shelter","3")
	rewrite(directory+"/Adobes.csv","New Builder Contribution","Shelter","0.7")
	rewrite(directory+"/Followers.csv","RouteSpeed","Brown Head","2.6")
	rewrite(directory+"/Followers.csv","Scale","Brown Head","1.25")
	parsed=constants.read()
	var before_tick: int=world.snapshot(false)["tick"]
	check(parsed.get("ok",false) and world.reconfigure(parsed.get("changes",[]))["ok"],"Reload OpenOffice unit edits")
	var spec := world.house_spec(1)
	check(spec["capacity"]==12.5 and spec["build_ticks"]==20 and spec["build_capacity"]==3,"Abode edits must update the actual house definition")
	check(is_equal_approx(spec["new_builder_contribution"],0.7),"The OpenOffice builder-contribution column must update the actual work rule")
	var state := world.snapshot(false)
	check(state["progression"]["rules"]["followers"]["Brown Head"]["RouteSpeed"]==2.6 and state["followers"][0]["scale"]==1.25,"Follower edits must update simulation and presentation data")
	check(state["tick"]==before_tick,"Reload must not advance simulation")
	rewrite(directory+"/Followers.csv","RouteSpeed","Brown Head","invalid")
	var before := world.export_state()
	parsed=constants.read()
	check(not parsed.get("ok",false) and world.export_state()==before,"One invalid cell must reject the entire three-file reload")
	for filename: String in ["Adobes.csv","Followers.csv","Update.csv"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(directory+"/"+filename))
	print("Three OpenOffice unit tables: %d failures" % failures)
	quit(1 if failures else 0)
