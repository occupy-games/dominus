extends SceneTree

const World = preload("res://simulation/world.gd")
const Session = preload("res://application/game_session.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func definition() -> Dictionary:
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	data["tree_field"]=PackedByteArray()
	data["objects"]["tree"]=[{"x":12,"z":12,"value":1},{"x":14,"z":12,"value":1},{"x":24,"z":24,"value":1}]
	return data


func run() -> void:
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	session.new_campaign(definition())
	var world: RefCounted = session.world
	var build := {"type":"home","x":12,"z":12,"rank":1}
	var command := {"type":"tap_tree","cell":12*64+12}
	check(world.inspect(build).get("obstruction",{}).get("kind")=="tree","A tree must obstruct its building plot")
	check(not world.query_copy().inspect(build)["ok"],"Detached query owners must see trees without duplicating the forest")
	var before: Dictionary = world.export_state()
	world.step([build])
	check(world.snapshot(false)["homes"].is_empty() and world.snapshot(false)["belief"]==before["state"]["belief"],"Rejected tree-covered construction must not spend resources or hide the tree")
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=session.inspect
	screen.intent.connect(session.submit)
	root.add_child(screen)
	screen.apply_snapshot(session.presentation_snapshot())
	check(screen.world_view.progression_at(Vector2(12,12))==command,"Clicking the original tree must select its clearing command")
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	session.advance_elapsed(0.1)
	var snapshot: Dictionary = session.presentation_snapshot()
	screen.apply_snapshot(snapshot)
	check(not world.tree_at(12,12) and world.inspect(build)["ok"],"The UI click must clear the authoritative plot")
	check(snapshot["removed_trees"].has(str(12*64+12)) and session.scenery_snapshot.is_read_only(),"Clearing must publish its mutable mask while retaining the shared immutable forest")
	check(screen.world_view.progression_at(Vector2(12,12)).is_empty(),"The cleared tree must stop intercepting world clicks")
	before=world.export_state()
	check(not world.inspect(command)["ok"],"A cleared tree must not be collectable twice")
	world.step([build])
	check(world.snapshot(false)["homes"].size()==1 and world.tree_at(14,12) and world.tree_at(24,24),"Construction must preserve adjacent trees rather than consume timber")
	for tick in range(1500): world.step()
	var saved: Dictionary = world.export_state()
	saved["state"]["progression"]["max_rank"]=2
	check(world.restore(saved,RandomNumberGenerator.new()),"The completed abode fixture must restore")
	var upgrade := {"type":"upgrade_home","id":world.snapshot(false)["homes"][0]["id"]}
	check(world.inspect(upgrade).get("obstruction",{}).get("kind")=="tree","An expanded abode footprint must require clearing its newly occupied tree")
	world.step([{"type":"tap_tree","cell":12*64+14}])
	check(world.inspect(upgrade)["ok"],"Clearing the expanded footprint must permit the upgrade")
	saved=world.export_state()
	saved["state"]["progression"]["discovered"].append("Card_Spirituality")
	check(world.restore(saved,RandomNumberGenerator.new()),"The original tree-belief unlock must restore")
	var belief_before: int = world.snapshot(false)["belief"]
	world.step([{"type":"tap_tree","cell":24*64+24}])
	check(world.snapshot(false)["belief"]==belief_before+1,"Clearing a tree after the belief unlock must award its original map-object value")
	var restored := World.new()
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()) and not restored.tree_at(12,12) and not restored.tree_at(24,24),"Cleared trees must stay cleared after save/load")
	for tick in range(20): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Clearing must preserve deterministic continuation")
	var delayed := definition()
	delayed["progression_rules"]["vegetation"]["taps_to_clear"]=3
	var tapped := World.new()
	tapped.initialize({"campaign_data":delayed},RandomNumberGenerator.new())
	tapped.step([command,command])
	check(tapped.tree_at(12,12) and not tapped.inspect(build)["ok"],"Source configurations requiring repeated taps must retain the obstruction until the final tap")
	tapped.step([command])
	check(not tapped.tree_at(12,12),"The final configured tap must clear exactly once")
	delayed=definition()
	delayed["progression_rules"]["influence_enabled"]=true
	delayed["progression_rules"]["influence_areas"]=[{"unlock":"always","force":true,"x":1,"z":1,"radius":2}]
	tapped.initialize({"campaign_data":delayed},RandomNumberGenerator.new())
	check(not tapped.inspect(command)["ok"],"Tree clearing must respect the same god influence as construction")
	var old := session.world.export_state()
	old["state"].erase("removed_trees")
	old["state"].erase("tree_taps")
	old["state"].erase("vegetation_revision")
	check(restored.restore(old,RandomNumberGenerator.new()) and not restored.tree_at(12,12),"Legacy trees already hidden by a house must migrate as cleared")
	old=restored.export_state()
	old["state"]["homes"]=[]
	for agent: Dictionary in old["state"]["followers"]: agent["job"]=-1; agent["path"]=[]
	check(restored.restore(old,RandomNumberGenerator.new()) and not restored.tree_at(12,12),"Demolishing an old house must not resurrect its previously hidden tree")
	# Live threaded queries must publish the new mask at the same boundary.
	session.new_campaign(definition())
	session.threaded=true
	check(not session.inspect(build)["ok"],"Threaded preview must reject the same covered plot")
	session.submit(command)
	session.advance_threaded(0.1)
	session.finish_worker(false)
	check(session.inspect(build)["ok"] and session.presentation_snapshot()["removed_trees"].has(str(command["cell"])),"Threaded command, query and presentation must agree after clearing")
	screen.queue_free()
	session.queue_free()
	await process_frame
	print("Original tree clearing and building plots: %d failures"%failures)
	quit(1 if failures else 0)
