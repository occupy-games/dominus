extends SceneTree

const Resize = preload("res://simulation/source_plot_resize.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/campaign/plot-resize-rules.json"))
	var rules := preload("res://infrastructure/plot_resize.gd").load_rules(metadata["executable_sha256"])
	check(Resize.valid_rules(rules),"The original resize branch tables must load with verified provenance")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_plot_resize.json"))
	for example: Dictionary in fixture["cases"]:
		var plots: Array=example.get("plots",[{"id":0,"x":160,"z":120,"size":4,"claimed":false}]).duplicate(true)
		var owners := {}
		for plot: Dictionary in plots:
			plot.merge({"height":6.0,"origin_byte":0,"biome_allowed":true,"stored_x":0,"stored_z":0})
			for z in range(int(plot["z"]),int(plot["z"])+int(plot["size"])):
				for x in range(int(plot["x"]),int(plot["x"])+int(plot["size"])): owners[z*1024+x]=plot
		var masks := {}
		for field: String in ["nonflat","scenery","blocked"]:
			masks[field]={}
			for point: Array in example.get(field,[]): masks[field][int(point[1])*1024+int(point[0])]=true
		var cell_at := func(x: int,z: int) -> Dictionary:
			var cell := z*1024+x
			return {"flat":not masks["nonflat"].has(cell),"scenery":masks["scenery"].has(cell),"blocked":masks["blocked"].has(cell),
				"owner":owners.get(cell,{}),"map_byte":0,"blight":0.0}
		var plot: Dictionary=plots[int(example.get("target",0))]
		var special := -1 if example.get("selected")==null else int(example["selected"])
		var result := Resize.layout_step(plot,cell_at,rules,int(example.get("minimum",2)),int(example.get("maximum",8)),special)
		var expected: Dictionary=example["expected"]["plots"][0]
		check(int(result["size"])==int(expected["size"]) and float(result["x"])==float(expected["x"]) and float(result["z"])==float(expected["z"]) and result["claimed"]==expected["claimed"],"Complete native %s layout iteration must match: expected %s, got %s"%[example["name"],expected,result])
		var revisit := Resize.revisit(plot,result,cell_at,[],special)
		var expected_queue: Array=example["expected"]["revisit"].map(func(id: Variant) -> int: return int(id))
		check(revisit==expected_queue,"Native %s neighbor revisit order must match: %s vs %s"%[example["name"],revisit,expected_queue])
		if example["name"]=="neighbor_158_120_False":
			check(Resize.revisit(plot,result,cell_at,[1.0],special)==[1,0],"JSON-restored pending identities must still deduplicate neighbor revisits")
		Resize.apply_layout(plots,owners,int(example.get("target",0)),result)
		var ownership := {}
		for cell: int in owners: ownership[str(cell)]=float(owners[cell]["id"])
		check(ownership==example["expected"]["owners"],"Original %s whole-footprint registration and neighboring ownership must match"%example["name"])
	var invalid := rules.duplicate(true)
	invalid["repair"][0]=255
	check(not Resize.valid_rules(invalid),"Malformed source action codes must reject")
	invalid=rules.duplicate(true)
	invalid["growth"].pop_back()
	check(not Resize.valid_rules(invalid),"Truncated source decision tables must reject")
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := preload("res://simulation/world.gd").new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	var restored := preload("res://simulation/world.gd").new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Injected source resize rules must survive campaign persistence")
	check(restored._state["opening"]["definition"]["plot_resize_rules"]==rules and restored._state["opening"]["definition"]["plot_resize_rules"]["growth"].is_read_only(),"Source decisions must remain immutable in restored snapshots")
	var saved := world.export_state()
	saved["state"]["opening"]["definition"]["plot_resize_rules"]["repair"][0]=255
	check(not restored.restore(saved,RandomNumberGenerator.new()),"Corrupted saved plot decisions must reject before changing the campaign")
	print("Original plot resize: %d native layout cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
