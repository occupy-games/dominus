extends "res://tests/test_shrine_priority.gd"

var commands: Array=[]


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	var data := definition()
	data["automatic_settlement"]=false
	var beacon: Dictionary=data["progression_rules"]["shrines"][0].duplicate(true)
	data["progression_rules"]["shrines"]=[]
	data["progression_rules"]["chests"]=[{"id":"finger","type":"treasure1","x":14,"z":14,"source_height":4,"depth":0,"rotation":0,"card":"Card_Adv_FingerOfGod_1"}]
	var world := create(data)
	world.step([{"type":"home","x":17,"z":18,"rank":1},{"type":"open_chest","id":"finger"}])
	for tick in range(250): world.step()
	check(world._state["homes"].size()==1,"The old-layout regression needs an ordinary real house")
	if world._state["homes"].size()!=1: quit(1); return
	var house := int(world._state["homes"][0]["id"])
	var saved: Dictionary=world.export_state()
	var placed: Dictionary=beacon.duplicate(true); placed["started"]=false; placed["complete"]=false
	saved["state"]["progression"]["shrines"]=[placed]
	saved["state"]["progression"]["rules"]["shrines"]=[beacon]
	check(world.restore(saved,RandomNumberGenerator.new()),"An existing house overlapping the older shrine reservation must load")
	var screen := preload("res://presentation/world/game_screen.gd").new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=world.inspect; screen.inspect_building=world.inspect_building
	screen.resolve_building_info=preload("res://infrastructure/building_info.gd").record
	screen.building_info_labels=preload("res://infrastructure/building_info.gd").content()["labels"]
	var catalog := preload("res://infrastructure/asset_catalog.gd").new(); catalog.read_models()
	screen.resolve_building=catalog.building_data
	screen.intent.connect(func(command: Dictionary) -> void: commands.append(command.duplicate(true)); world.queue_command(command))
	root.add_child(screen); screen.set_process(false)
	screen.apply_snapshot(world.snapshot(false))
	check(screen.world_view.temple_at(Vector2(17,18)).is_empty(),"A covering house must intercept the shrine's overlapping hotspot")
	screen.on_action(Vector2i(17,18),Vector2(17,18))
	check(screen.selected_building_kind=="home" and screen.selected_home==house and not screen.building_panel.popup.visible,"Clicking the covering house must select that house, never the shrine underneath")
	commands=[]
	screen.building_panel.popup.show()
	screen.select_power("GodPower_FingerOfGod")
	check(not screen.building_panel.popup.visible,"Arming a clearing power must dismiss building inspection so it can reach the map")
	screen.on_action(Vector2i(17,18),Vector2(16.6,18))
	check(commands.size()==1 and commands[0].get("power")=="GodPower_FingerOfGod" and commands[0].get("home_id")==house,"The original clearing power must target the covering house even on its left edge")
	world.step()
	check(world._state["homes"].is_empty() and world._state["progression"]["shrines"].size()==1,"Finger of God must remove the covering house and preserve the shrine")
	var tree_data := definition(); tree_data["automatic_settlement"]=false
	tree_data["tree_field"][18*64+18]=1
	var wooded := create(tree_data)
	screen.inspect_action=wooded.inspect; screen.inspect_building=wooded.inspect_building
	screen.intent.disconnect(screen.intent.get_connections()[0]["callable"])
	screen.intent.connect(func(command: Dictionary) -> void: commands.append(command.duplicate(true)); wooded.queue_command(command))
	screen.choose_tool("sculpt"); screen.apply_snapshot(wooded.snapshot()); commands=[]
	check(screen.world_view.temple_at(Vector2(18,18)).is_empty(),"A covering tree must prevent shrine selection")
	screen.on_action(Vector2i(18,18),Vector2(18,18))
	check(commands.size()==1 and commands[0].get("type")=="tap_tree","Clicking above the shrine must clear the actual tree")
	wooded.step()
	screen.apply_snapshot(wooded.snapshot())
	if not wooded.tree_at(18,18): check(screen.world_view.temple_at(Vector2(18,18))=="1012","Clearing the last tree must expose ordinary shrine inspection")
	var buried := tree_data.duplicate(true)
	buried["tree_field"].fill(0); buried["terrain"][18*64+18]=5
	var covered := create(buried)
	screen.apply_snapshot(covered.snapshot(false))
	check(screen.world_view.temple_at(Vector2(18,18)).is_empty() and screen.world_view.progression_at(Vector2(18,18)).is_empty(),"Buried terrain must reach the terrain gesture instead of an invisible shrine click target")
	screen.queue_free(); await process_frame; await process_frame
	print("Shrine blockers, covering-object selection and original clearing power: %d failures"%failures)
	quit(1 if failures else 0)
