extends SceneTree

const World = preload("res://simulation/world.gd")
const Plots = preload("res://simulation/source_plots.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_masks.json"))
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var samples := 0
	for example: Dictionary in fixture["cases"]:
		var world := World.new()
		world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
		# Controlled native-mask inputs, not a claimed tutorial playthrough.
		if example["removed_rock"]:
			world._state["progression"]["rock_taps"][str(123*1024+161)]=1
		for edit: Array in example["terrain_edits"]:
			world._state["terrain"][int(edit[1])*1024+int(edit[0])]=int(edit[2])-19
		var before := world.export_state()
		var expected: PackedByteArray=str(example["capacities"]).hex_decode()
		var index := 0
		var mismatches := 0
		var adapter_mismatches := 0
		var cache := {}
		var fields := func(x: int,z: int) -> Dictionary:
			var cell := z*1024+x
			if not cache.has(cell): cache[cell]=world._source_plot_field_at(x,z,7)
			return cache[cell]
		for z in range(int(fixture["bounds"][1]),int(fixture["bounds"][3])):
			for x in range(int(fixture["bounds"][0]),int(fixture["bounds"][2])):
				if world.source_plot_capacity(x,z)!=int(expected[index]): mismatches+=1
				if preload("res://simulation/source_plot_registry.gd").clear_capacity(fields,x,z)!=int(expected[index]): adapter_mismatches+=1
				index+=1
		check(mismatches==0,"Original native %s plot masks differ at %d coordinates"%[example["name"],mismatches])
		check(adapter_mismatches==0,"The live registry's %s terrain/scenery adapter differs from native capacity at %d coordinates"%[example["name"],adapter_mismatches])
		check(world.export_state()==before,"Plot queries must not alter state, schedules or RNG")
		var restored := World.new()
		check(restored.restore(before,RandomNumberGenerator.new()),"Native plot inputs must survive the existing plain-state restore")
		check(restored.source_plot_capacity(158,120)==world.source_plot_capacity(158,120) and world.query_copy().source_plot_capacity(159,121)==world.source_plot_capacity(159,121),"Restored and detached query owners must agree on clearing and edited corners")
		samples+=index
		if example["name"]=="cleared":
			check(world.source_plot_capacity(159,121)==3,"Rock clearing leaves the original three-quad patch; it must not invent a four-quad building plot")
			check(world.source_plot_capacity(158,120)<4,"A single low corner must block a larger source footprint")
		if example["name"]=="sculpted":
			check(world.source_plot_capacity(158,120)>=4,"Raising the low corner must make the newly flat source footprint available to the plot allocator")
	for query: Dictionary in fixture.get("queries",[]):
		check(Plots.intersects_query(Vector2(query["origin"][0],query["origin"][1]),int(query["size"]),Vector2(query["center"][0],query["center"][1]),float(query["radius"]))==query["intersects"],"Source radius queries must include the plot's registered half-size")
	var flat := PackedByteArray()
	flat.resize(40*40)
	flat.fill(1)
	var empty := func(_x: int,_z: int) -> bool: return false
	check(Plots.capacity(flat,40,4,4,empty)==16,"Clear masks must retain the native maximum size")
	check(Plots.capacity(flat,40,4,4,empty,3)==3,"A smaller house query must bound its scan")
	check(Plots.capacity(flat,40,38,38,empty)==1 and Plots.capacity(flat,40,39,39,empty)==0,"Map edges must leave all four corners inside the source field")
	flat[5*40+5]=2
	check(Plots.capacity(flat,40,4,4,empty)==0,"Checking only the plot origin must not miss a sloped quad")
	flat.fill(1)
	check(Plots.capacity(flat,40,4,4,func(x: int,z: int) -> bool: return x==6 and z==6)==2,"Objects inside an enlarged footprint must cap its clear size")
	print("Original native plot masks: %d samples, %d failures"%[samples,failures])
	quit(1 if failures else 0)
