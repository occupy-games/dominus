extends SceneTree

const World = preload("res://simulation/world.gd")
const Plots = preload("res://simulation/source_plots.gd")
const Biomes = preload("res://simulation/source_biomes.gd")
const PlotEnvironment = preload("res://infrastructure/plot_environment.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_allocation.json"))
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var environment := PlotEnvironment.from_rows(fixture["biomes"],fixture["configuration"])
	check(Biomes.valid(environment) and environment==definition["story"]["plot_environment"],"The private campaign must inject the actual source biome table and current indices")
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	check(world.source_biome_at(161,123)==0 and world.source_plot_band(161,123)==0,"The first tent must query its source default biome and lowland band")
	var blocked := {}
	for tree: Dictionary in definition["source_trees"]: blocked[int(tree["cell"])]=true
	for rock: Dictionary in definition["story"]["rock_objects"]:
		if rock["authored"] and int(rock["cell"])==123*1024+161: continue
		for dz in range(int(rock["size_z"])):
			for dx in range(int(rock["size_x"])): blocked[(int(rock["origin_z"])+dz)*1024+int(rock["origin_x"])+dx]=true
	var bounds: Array=fixture["bounds"]
	var contains := func(x: int,z: int) -> bool: return x>=int(bounds[0]) and x<int(bounds[2]) and z>=int(bounds[1]) and z<int(bounds[3])
	var occupied := func(x: int,z: int) -> bool: return blocked.has(z*1024+x)
	for example: Dictionary in fixture["cases"]:
		# These are the same explicit, clipped eligibility inputs supplied to the
		# native scan, not a claim to reproduce the original global AOI raster.
		var terrain: PackedByteArray=definition["terrain"].duplicate()
		for edit: Array in example.get("terrain_edits",[]): terrain[int(edit[1])*1024+int(edit[0])]=int(edit[2])-19
		if example.has("terrain_patch"):
			var patch: Array=example["terrain_patch"]
			for z in range(int(patch[1]),int(patch[3])):
				for x in range(int(patch[0]),int(patch[2])): terrain[z*1024+x]=int(patch[4])-19
		var rotation: PackedByteArray=str(fixture["plotrot_region"]).hex_decode()
		var stride := int(bounds[2])-int(bounds[0])
		for edit: Array in example.get("plotrot_edits",[]): rotation[(int(edit[1])-int(bounds[1]))*stride+int(edit[0])-int(bounds[0])]=int(edit[2])
		var capacity := func(x: int,z: int) -> int: return Plots.capacity(terrain,1024,x,z,occupied)
		var band := func(x: int,z: int) -> int: return Biomes.band(int(terrain[z*1024+x])+19,environment["configuration"])
		var eligible := func(x: int,z: int) -> bool:
			if not contains.call(x,z): return false
			if not Plots.map_byte_allows(int(rotation[(z-int(bounds[1]))*stride+x-int(bounds[0])])): return false
			return (int(fixture["biome_mask"]) & (1<<Biomes.biome_at(environment["biomes"],environment["configuration"],x,z)))!=0
		var plots := Plots.new_region(Vector2i(fixture["tile"][0],fixture["tile"][1]),1024,example.get("sizes",fixture["sizes"]),contains,capacity,band,eligible)
		var expected: Array=[]
		for native: Dictionary in example["plots"]: expected.append({"id":int(native["id"]),"x":int(native["x"]),"z":int(native["z"]),"size":int(native["size"])})
		check(plots==expected,"Original %s allocation must preserve size priority, row/column order and whole-footprint reservations"%example["name"])
		var used := {}
		for plot: Dictionary in plots:
			for dz in range(int(plot["size"])):
				for dx in range(int(plot["size"])):
					var cell := (int(plot["z"])+dz)*1024+int(plot["x"])+dx
					check(not used.has(cell),"Native fresh plots must never share an occupied quad")
					used[cell]=true
	var samples := 0
	for example: Dictionary in fixture["biome_cases"]:
		var config := PlotEnvironment.from_rows(example["rows"],fixture["configuration"])
		for sample: Array in example["samples"]:
			check(Biomes.scheme_at(config["biomes"],sample[0],sample[1])==int(sample[2]) and Biomes.biome_at(config["biomes"],config["configuration"],sample[0],sample[1])==int(sample[3]),"Source biome lookup must match native overlap, boundaries and the Weyworld index mapping")
			samples+=1
	check(Biomes.band(24,environment["configuration"])==0 and Biomes.band(25,environment["configuration"])==1 and Biomes.band(35,environment["configuration"])==1 and Biomes.band(36,environment["configuration"])==2,"Height bands must use the current source boundaries inclusively")
	var invalid := world.export_state()
	invalid["state"]["opening"]["definition"]["plot_environment"]["biomes"][0]["outer"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Invalid persisted biome geometry must reject before a query")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and restored.source_biome_at(161,123)==0 and world.query_copy().source_plot_band(161,123)==0,"Source plot environment must survive restore and detached query ownership")
	print("Original new plot allocation: %d cases, %d biome samples, %d failures"%[fixture["cases"].size(),samples,failures])
	quit(1 if failures else 0)
