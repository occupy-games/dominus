extends SceneTree

const World = preload("res://simulation/world.gd")
const Rocks = preload("res://simulation/authored_rocks.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(definition.get("source_trees",[]).size()==2937 and definition["story"].get("rock_objects",[]).size()==1266,"The complete initial map must use the original kernel's object counts rather than every nonzero density cell")
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	var state: Dictionary=world._state
	check(state["trees"].size()==2937 and Rocks.entries(state).size()==1266,"Simulation must own the recovered initial placements")
	check(state["trees"].filter(func(tree: Dictionary) -> bool: return str(tree["model_id"]).begins_with("godseedtrees.group.bin:")).size()==41,"All authored Godseed trees must retain their original separate model package")
	check(world.height_at(129,78)==0 and world.tree_at(129,78),"A source tree on a sampled dry coast must survive even when the integer root cell is water")
	check(not world.tree_at(160,123),"Packed density alone must not invent a tree in the first-house plot")
	var rock := Rocks.at(state,122*1024+160)
	check(rock.get("model_name")=="boulder6" and rock.get("cell")==123*1024+161,"Native source coordinates and model type must identify the first tutorial rock")
	var before := world.snapshot(false)
	var visibility: PackedByteArray=before["source_rock_visibility"]
	visibility[0]=0
	check(world.snapshot(false)["source_rock_visibility"][0]==1,"A mutable rendering mask must not mutate simulation's visibility cache")
	check(before["authored_rocks"].is_read_only() and before["source_rock_cells"].is_read_only(),"Large static placement/index tables must remain shared immutable data")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Native fractional placements must restore without scene or asset services")
	for tick in range(20): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Source positions, ownership masks and RNG must continue identically after restoration")
	var invalid := world.export_state()
	invalid["state"]["trees"][0]["source_y"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Invalid native tree transforms must reject before restoration")
	invalid=world.export_state()
	invalid["state"]["opening"]["definition"]["rock_objects"][0]["source_y"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Invalid native rock transforms must reject before restoration")
	print("Original native initial scenery and immutable placement data: %d failures"%failures)
	quit(1 if failures else 0)
