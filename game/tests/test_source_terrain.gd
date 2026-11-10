extends SceneTree

const Terrain = preload("res://simulation/source_terrain.gd")
const World = preload("res://simulation/world.gd")
const Opening = preload("res://simulation/campaign_opening.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_terrain_samples.json"))
	check(Terrain.HEIGHT_SCALE==float(fixture["height_scale"]),"The discrete terrain query must preserve the original world-height scale")
	var count := 0
	for sample: Dictionary in fixture["cases"]:
		var values: PackedByteArray=str(sample["values"]).hex_decode()
		var heights: Array=sample["corners"]
		var corners := Vector4i(int(heights[0]),int(heights[1]),int(heights[2]),int(heights[3]))
		for index in range(fixture["points"].size()):
			var point: Array=fixture["points"][index]
			check(Terrain.quad(corners,float(point[0])-100,float(point[1])-100)==int(values[index]),"Original contour diamonds, central medians and exact boundary ties must match at %s with %s"%[point,corners])
			count+=1
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var original: PackedByteArray=definition["story"]["raw_floor"]
	var vertex := func(x: int,z: int) -> int: return int(original[z*1024+x])
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	var before := world.export_state()
	for sample: Array in fixture["source_samples"]:
		check(Terrain.raw_at(vertex,1024,sample[0],sample[1])==int(sample[2]) and world.source_raw_height_at(sample[0],sample[1])==int(sample[2]),"Source map queries must preserve authored raw heights and fractional contour decisions")
	check(world.export_state()==before,"Fractional source map queries must not mutate authoritative state")
	var intro := Opening.new()
	intro.configure(world,world._state,[])
	before=world.export_state()
	for sample: Array in fixture["script_samples"]:
		check(world.source_step_at(sample[0],sample[1])==float(sample[2]) and intro.api("GetStepAtPoint",[sample[0],sample[1]])==float(sample[2]),"The original Lua terrain callback must preserve fractional coordinates and float32 scale conversion")
	check(world.export_state()==before,"Default source terrain queries must not mutate simulation state or callbacks")
	var uniform := func(_x: int,_z: int) -> int: return 20
	for sample: Array in fixture["edge_samples"]:
		check(Terrain.raw_at(uniform,1024,sample[0],sample[1])==int(sample[2]),"Native map-edge and negative-fraction truncation behavior must match")
	check(Terrain.raw_at(uniform,1024,NAN,100)==0 and Terrain.raw_at(uniform,1024,INF,100)==0,"Invalid query coordinates must reject without invoking a vertex callback")
	var saved := world.export_state()
	# A controlled submerged edit must override the immutable raw sea floor.
	var cell := 100*1024+100
	saved["state"]["terrain"][cell]=0
	saved["state"]["opening"]["submerged_levels"][str(cell)]=17
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()) and restored.source_raw_height_at(100,100)==17,"Source sampling must honor saved submerged sculpt levels")
	saved=restored.export_state()
	saved["state"]["terrain"][cell]=5
	check(restored.restore(saved,RandomNumberGenerator.new()) and restored.source_raw_height_at(100,100)==24,"Raised terrain must override an older submerged edit")
	var query := restored.query_copy()
	check(query.source_step_at(100,100)==restored.source_step_at(100,100),"Detached query owners must see the same edited raw terrain")
	var store := Store.new()
	store.database_path="res://../build/test-source-terrain.sqlite"
	check(store.save_world(restored.export_state()).get("ok",false),"Edited discrete source terrain must save through SQLite")
	var loaded := store.load_world()
	check(loaded.get("ok",false) and world.restore(loaded.get("data",{}),RandomNumberGenerator.new()) and world.source_step_at(100,100)==restored.source_step_at(100,100),"The source terrain query must remain exact after SQLite reload")
	print("Original terrain sampling: %d corner cases, %d source samples, %d failures"%[count,fixture["source_samples"].size(),failures])
	quit(1 if failures else 0)
