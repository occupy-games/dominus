extends SceneTree

const World = preload("res://simulation/world.gd")
const Repair = preload("res://simulation/source_temple_repair.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_temple_repair.json"))
	var definition := preload("res://tests/fixtures/campaign_economy.gd").definition()
	definition["followers"]=[{"x":17,"z":18},{"x":17,"z":19}]
	definition["progression_rules"]["followers"]={"Brown Head":{"JobSkill":1.0}}
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/temple-sites.json"))
	var sites := preload("res://infrastructure/temple_sites.gd").sites("initialworldsetup6",metadata["source_sha256"])
	var beacon: Dictionary={}
	for site: Dictionary in sites:
		if site["id"]=="1012": beacon=site.duplicate(true)
	beacon.merge({"x":18,"z":18,"source_height":23,"build_ticks":10000},true)
	definition["progression_rules"]["shrines"]=[beacon]
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	world.step([{"type":"repair_shrine","id":"1012"}])
	for i in range(100):
		if world._state["followers"].all(func(f: Dictionary) -> bool: return f["state"]=="building"): break
		world.step()
	check(world._state["homes"].size()==1 and world._state["followers"].all(func(f: Dictionary) -> bool: return f["state"]=="building"),"Two real builders must reach their temple work positions")
	var baseline := world.export_state()
	baseline["state"]["homes"][0].merge({"temple_work":0.0,"progress":0,"work_accumulator":0.0},true)
	check(world.restore(baseline,RandomNumberGenerator.new()),"A controlled arrived-worker boundary must restore")
	for i in range(10): world.step()
	var original := preload("res://simulation/source_terrain.gd").f32(float(fixture["sequences"][0]["states"][-1]["state"]["progress"]))
	check(world._state["homes"][0]["temple_work"]==original,"Playable temple work must exactly match ten original two-builder exponent-0.35 ticks")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(world.export_state()))))
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"Original float32 temple work must survive the save codec")
	for i in range(20): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Temple progress and worker state must continue identically after restore")
	var legacy := baseline.duplicate(true)
	legacy["state"]["progression"]["rules"]["version"]=8
	legacy["state"]["progression"]["rules"]["config"].erase("templeFixerFalloff")
	legacy["state"]["progression"]["rules"].erase("temple_repair_rules")
	legacy["state"]["homes"][0].erase("temple_work")
	legacy["state"]["homes"][0]["progress"]=12
	legacy["state"]["homes"][0]["work_accumulator"]=0.25
	var migrated := World.new()
	check(migrated.restore(legacy,RandomNumberGenerator.new()),"An older in-progress temple save without source-work fields must remain readable")
	migrated.migrate_progression(definition["progression_rules"],definition["rock_field"])
	check(migrated._state["homes"][0]["temple_work"]==preload("res://simulation/source_terrain.gd").f32(1.225),"Migration must retain fractional work from an older repair job")
	check(migrated._state["homes"][0]["progress"]==12 and migrated._state["homes"][0]["work_accumulator"]==0.25,"Migration cannot advance the old repair timer")
	check(migrated._state["progression"]["rules"]["config"]["templeFixerFalloff"]==0.35,"Migration must supply the original missing temple exponent")
	migrated.step()
	check(migrated._state["homes"][0]["temple_work"]>preload("res://simulation/source_terrain.gd").f32(1.225),"The migrated job must resume normal worker-driven repair")
	var constants := preload("res://infrastructure/live_constants.gd").new()
	constants.path="res://../build/temple-work-balance/Update.csv"
	constants.initialize(definition["progression_rules"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(constants.path).get_base_dir())
	var file := FileAccess.open(constants.path,FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["Name","Value","Default","Group"]),";")
	file.store_csv_line(PackedStringArray(["Config.FirstCardIndex","1","1","Existing values"]),";")
	file.close()
	check(constants.ensure_file()["ok"] and constants.ensure_file()["ok"],"Reload must add the new temple value to existing semicolon-separated CSVs")
	file=FileAccess.open(constants.path,FileAccess.READ)
	var rows: Array=[]
	while not file.eof_reached():
		var row := file.get_csv_line(";")
		if row.size()>1: rows.append(row)
	file.close()
	check(rows.size()==3 and rows[1][0]=="Config.FirstCardIndex" and rows[2][0]=="Config.templeFixerFalloff","Adding a source value must preserve existing rows and avoid duplicates")
	rows[2][1]="1"
	file=FileAccess.open(constants.path,FileAccess.WRITE)
	for row: PackedStringArray in rows: file.store_csv_line(row,";")
	file.close()
	var changes := constants.read()
	check(changes.get("ok",false),"OpenOffice-edited temple values must parse through the real three-file reader")
	check(world.restore(baseline,RandomNumberGenerator.new()),"The same native comparison boundary must restore for CSV work")
	check(world.reconfigure(changes.get("changes",[]))["ok"],"CSV temple exponent must apply through the existing reload command")
	check(world._state["homes"][0]["temple_work"]==0.0,"Reloading an exponent cannot advance repair work")
	for i in range(10): world.step()
	var edited := preload("res://simulation/source_terrain.gd").f32(float(fixture["sequences"][1]["states"][-1]["state"]["progress"]))
	check(world._state["homes"][0]["temple_work"]==edited and edited>original,"Live edited temple work must match the original exponent-one sequence")
	var before := world.export_state()
	check(not world.reconfigure([{"category":"config","key":"templeFixerFalloff","value":9}])["ok"] and world.export_state()==before,"Invalid temple exponents must reject atomically")
	var previous := float(world._state["homes"][0]["temple_work"])
	check(world.reconfigure([{"category":"shrine","id":"1012","value":2000}])["ok"],"The authored repair duration remains reloadable")
	check(world._state["homes"][0]["temple_work"]==preload("res://simulation/source_terrain.gd").f32(previous*2),"Duration reload preserves the actual fractional temple work")
	var invalid := world.export_state()
	invalid["state"]["homes"][0]["temple_work"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Nonfinite temple work must reject before restoration")
	print("Original temple work in playable repair, CSV reload and save continuation: %d failures"%failures)
	quit(1 if failures else 0)
