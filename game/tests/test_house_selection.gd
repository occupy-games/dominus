extends SceneTree

const Houses = preload("res://simulation/source_houses.gd")
const Gates = preload("res://simulation/source_unlocks.gd")
const World = preload("res://simulation/world.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_house_selection.json"))
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var rows: Array=definition["story"]["house_selection"]
	check(Houses.valid(rows),"Injected building choices must preserve all source fields and native row order")
	var cases := 0
	for profile: Dictionary in fixture["profiles"]:
		var unlocked := func(key: String) -> bool: return key in profile["unlocks"]
		var limits: Dictionary=profile["limits"].duplicate(true)
		for key: String in ["minimum","maximum","biomes"]: limits[key]=int(limits[key])
		for band in range(3): limits["sizes"][band]=[int(limits["sizes"][band][0]),int(limits["sizes"][band][1])]
		check(Houses.plot_limits(rows,unlocked)==limits,"Original %s plot availability must distinguish production biomes from abode sizes"%profile["name"])
		for sample: Array in profile["samples"]:
			var biome := 0
			for index in range(1,4):
				if maxi(0,int(sample[2]))==int(fixture["configuration"]["biome%dIndex"%index]): biome=index; break
			var choice := Houses.choose(rows,int(sample[0]),int(sample[1]),biome,unlocked,int(sample[3]),profile.get("ignore_unlocks",false),profile.get("biome_locked",true))
			var index := int(choice.get("index",0))
			check(index==int(sample[4]),"Original %s choice must match size, height, biome, unlock and production filters for %s"%[profile["name"],sample])
			cases+=1
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	check(world.source_house_for_plot(158,120,4).is_empty() and world.source_plot_limits()["maximum"]==0,"Source abodes must stay locked before the tutorial's plot-claim unlock")
	var saved := world.export_state()
	saved["state"]["progression"]["script_unlocks"]={"PlotsAppearClaim":true}
	check(world.restore(saved,RandomNumberGenerator.new()),"The source script plot-claim unlock must restore")
	var choice := world.source_house_for_plot(158,120,4)
	check(choice.get("id")=="AbodeType_0_Rank_1" and world.source_plot_limits()["sizes"]==[[4,4],[10000,0],[10000,0]],"The original plot-claim key must release the first tent's size limits and choice")
	choice["size"]=16
	check(world.query_copy().source_house_for_plot(158,120,4).get("size")==4,"Source house selection must return detached data to queries")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and restored.source_house_for_plot(158,120,4)==world.source_house_for_plot(158,120,4),"Source building selection must continue exactly across save/load")
	saved=world.export_state()
	saved["state"]["progression"]["script_unlocks"]["PlotsAppearClaim"]=false
	check(restored.restore(saved,RandomNumberGenerator.new()) and restored.source_house_for_plot(158,120,4).is_empty(),"An explicitly locked tutorial key must not release a dependent building unlock")
	saved=world.export_state()
	saved["state"]["opening"]["definition"]["house_selection"][18]["size"]=NAN
	check(not World.new().restore(saved,RandomNumberGenerator.new()),"Malformed persisted house choice data must reject before selection")
	# These direct fixtures distinguish rank-independent native size/order ties.
	var equal: Array=rows.duplicate(true)
	equal[19]["order"]=equal[18]["order"]
	var all_enabled := func(_key: String) -> bool: return true
	check(Houses.choose(equal,4,0,0,all_enabled).get("id")=="AbodeType_4_Rank_1","Greater source order must win an equal-size choice")
	var first: Dictionary=rows[18].duplicate(true)
	var second: Dictionary=first.duplicate(true)
	second["index"]=19
	second["id"]="controlled_equal_order"
	check(Houses.choose([first,second],4,0,0,all_enabled).get("index")==18,"Exact native ties must preserve earlier table order")
	var state: Dictionary=world.export_state()["state"]["progression"]
	check(Gates.enabled(state,"PlotsAppear"),"Source unlock conditions must see the tutorial's explicitly enabled script key")
	print("Original building selection: %d native cases, %d failures"%[cases,failures])
	quit(1 if failures else 0)
