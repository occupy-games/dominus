extends SceneTree

const World = preload("res://simulation/world.gd")
const Work = preload("res://simulation/construction_work.gd")
const Session = preload("res://application/game_session.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_construction.json"))
	for example: Dictionary in fixture["cases"]:
		var result := Work.advance(float(example["progress"]),float(example["delta"]),int(example["count"]),int(example["contributors"]),float(example["skill_sum"]),float(example["exponent"]),float(example["rate"]))
		check(absf(result-float(example["result"]))<0.000001,"Construction work must match the captured native count/skill arithmetic")
	var definition := preload("res://tests/fixtures/campaign_economy.gd").definition()
	definition["followers"]=[{"x":11,"z":12},{"x":11,"z":13},{"x":14,"z":12},{"x":14,"z":13}]
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	check(is_equal_approx(world.house_spec(1)["new_builder_contribution"],0.5),"The older source house table must supply its actual exponent")
	var changes := [{"category":"house","family":0,"rank":1,"field":"build_ticks","value":100},
		{"category":"house","family":0,"rank":1,"field":"build_capacity","value":4}]
	check(world.reconfigure(changes)["ok"],"A multi-builder unit must configure through ordinary live balance")
	world.step([{"type":"home","x":12,"z":12,"rank":1}])
	for tick in range(300):
		world.step()
		if world._state["followers"].all(func(agent: Dictionary) -> bool: return agent["state"]=="building"): break
	check(world._state["homes"].size()==1 and world._state["followers"].all(func(agent: Dictionary) -> bool: return agent["state"]=="building"),"All four reachable builders must retain their building state at their work positions")
	var home: Dictionary=world._state["homes"][0]
	var baseline := float(home["progress"])+float(home.get("work_accumulator",0))
	for tick in range(10): world.step()
	check(absf(float(home["progress"])+float(home["work_accumulator"])-baseline-20)<0.00001,"Four original exponent-0.5 builders must perform twice one builder's work, not four times")
	var saved := world.export_state()
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"Part-built fractional cooperative work must restore")
	for tick in range(20): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Fractional work and builder jobs must continue exactly after save/load")
	var reversed := world.export_state()
	reversed["state"]["followers"].reverse()
	check(restored.restore(reversed,RandomNumberGenerator.new()),"Follower ordering is not a construction rule")
	for tick in range(20): world.step(); restored.step()
	check(world._state["homes"]==restored._state["homes"],"Cooperative work must not depend on which follower updates first")
	check(world.reconfigure([{"category":"follower","race":"Brown Head","field":"JobSkill","value":2}])["ok"],"The original job-skill column must remain live")
	baseline=float(home["progress"])+float(home["work_accumulator"])
	for tick in range(10): world.step()
	check(absf(float(home["progress"])+float(home["work_accumulator"])-baseline-40)<0.00001,"The actual construction tick must include average worker job skill")
	# Content migration adds only the absent source field, preserving saved CSV
	# durations, capacities, progress and fractional work.
	var old := world.export_state()
	old["state"]["progression"]["rules"]["version"]=6
	for house: Dictionary in old["state"]["progression"]["rules"]["houses"]: house.erase("new_builder_contribution")
	for house: Dictionary in old["state"]["homes"]: house.erase("new_builder_contribution")
	check(restored.restore(old,RandomNumberGenerator.new()),"Existing version-six saves must remain readable")
	restored.migrate_progression(definition["progression_rules"],definition["rock_field"])
	var migrated: Dictionary=restored._state["homes"][0]
	check(migrated["new_builder_contribution"]==0.5 and migrated["progress"]==home["progress"] and migrated["build_ticks"]==1000 and migrated["build_capacity"]==4 and migrated["work_accumulator"]==home["work_accumulator"],"Adding original builder contribution must preserve the player's existing unit balance and partial work")
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	# The application resolves the real map's full-size content on load. Expand
	# this controlled flat save-schema fixture to that map size, so its source
	# chest coordinates remain in bounds; this is not a campaign playthrough.
	var application_save := old.duplicate(true)
	application_save["state"]["width"]=1024
	for field: String in ["terrain","rocks","rock_heights"]:
		var values := PackedByteArray()
		values.resize(1024*1024)
		values.fill(4 if field=="terrain" else 0)
		application_save["state"][field]=values
	check(session.world.restore(application_save,RandomNumberGenerator.new()),"The application migration fixture must restore")
	var path := "res://../build/test-native-construction.sqlite"
	check(session.save_game(path).get("ok",false) and session.load_game(path).get("ok",false),"The actual save/load flow must upgrade version-six construction")
	check(session.world._state["progression"]["rules"]["version"]==preload("res://simulation/progression.gd").RULES_VERSION and session.world._state["homes"][0]["new_builder_contribution"]==0.5 and session.world._state["homes"][0]["work_accumulator"]==home["work_accumulator"],"SQLite/application migration must retain fractional work and supply the missing source exponent")
	session.queue_free()
	var invalid := world.export_state()
	invalid["state"]["homes"][0]["new_builder_contribution"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Invalid saved builder exponents must reject")
	invalid=world.export_state()
	invalid["state"]["progression"]["rules"]["houses"][0]["new_builder_contribution"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Invalid future building rules must reject before construction can use them")
	var before := world.export_state()
	check(not world.reconfigure([{"category":"house","family":0,"rank":1,"field":"new_builder_contribution","value":9}])["ok"] and world.export_state()==before,"An invalid reload must not partially change live construction")
	check(world.reconfigure([{"category":"runtime","key":"build_rate","value":1000},{"category":"house","family":0,"rank":1,"field":"new_builder_contribution","value":8},{"category":"follower","race":"Brown Head","field":"JobSkill","value":1000000}])["ok"],"Valid large CSV rates must remain safe to apply")
	world.step()
	check(home["progress"]==home["build_ticks"] and world._state["followers"].all(func(agent: Dictionary) -> bool: return agent["job"]==-1),"Completion must release the entire builder team at the same boundary")
	await process_frame
	print("Original cooperative construction: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
