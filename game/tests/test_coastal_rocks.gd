extends SceneTree
const World=preload("res://simulation/world.gd")
const Content=preload("res://infrastructure/campaign_content.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message); failures+=1
func run() -> void:
	var definition := Content.homeworld()
	var density := FileAccess.get_file_as_bytes("res://assets/original/"+str(definition["fields"]["rock"]["path"]))
	var water_cell := -1
	var dry_cell := -1
	for cell in range(definition["rock_field"].size()):
		if density[cell]>0 and definition["terrain"][cell]==0 and water_cell<0: water_cell=cell
		if definition["rock_field"][cell]>0 and definition["terrain"][cell]>0 and dry_cell<0: dry_cell=cell
		if water_cell>=0 and dry_cell>=0: break
	check(water_cell>=0 and dry_cell>=0,"Regression must exercise original underwater and dry source records")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	var state := world.snapshot(false)
	check(state["rocks"][water_cell]==0 and state["rocks"][dry_cell]>0,"Keep existing dry-land rocks but never seed new rocks under the sea")
	var exported := world.export_state()
	exported["state"]["progression"]["rules"]["influence_enabled"]=false
	exported["state"]["progression"]["influence_enabled"]=false
	# Raise an actual source-water rock cell through the normal geometry command.
	check(world.restore(exported,RandomNumberGenerator.new()),"Restore fixture without influence restriction")
	world.step([{"type":"raise","x":water_cell%1024,"z":water_cell/1024,"radius":0}])
	state=world.snapshot(false)
	check(state["terrain"][water_cell]==1 and state["rocks"][water_cell]==0,"Raising seabed into land must leave a bare terrace")
	check(not world.inspect({"type":"tap_object","cell":water_cell})["ok"],"New coast must not contain an invisible collectible rock")
	check(state["rock_heights"][dry_cell]==definition["terrain"][dry_cell],"Existing rocks must retain their original layer")
	var old := world.export_state()
	old["state"].erase("rock_heights")
	old["state"]["rocks"][water_cell]=density[water_cell]
	check(world.restore(old,RandomNumberGenerator.new()),"Read legacy state")
	world.migrate_rocks(definition["terrain"])
	check(world.snapshot(false)["rocks"][water_cell]==0,"Legacy raised coast must also be cleared of erroneous underwater records")
	print("Bare coast and anchored rocks: %d failures" % failures)
	quit(1 if failures else 0)
