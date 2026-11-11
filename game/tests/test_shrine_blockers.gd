extends "res://tests/test_shrine_priority.gd"

var commands: Array=[]


func covering_click(view: Node3D,mesh: MeshInstance3D,transform: Transform3D,yaws: Array=[0.55,1.57,3.14,4.71]) -> Vector2:
	var bounds := mesh.mesh.get_aabb()
	for yaw: float in yaws:
		view.yaw=yaw
		view.update_camera(false)
		for x: float in [0.25,0.5,0.75]:
			for z: float in [0.25,0.5,0.75]:
				for height: float in [0.3,0.5,0.7,0.9]:
					var point := transform*(bounds.position+bounds.size*Vector3(x,height,z))
					var screen: Vector2=view.camera.unproject_position(point)
					if view.temple_at(view.pick(screen))=="1012": return screen
	return Vector2.INF


func click(view: Node3D,position: Vector2,repeated: bool=false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=position
	event.double_click=repeated
	view._unhandled_input(event)


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
	screen.scenery_assets=preload("res://infrastructure/game_content.gd").new().scenery_assets()
	screen.intent.connect(func(command: Dictionary) -> void: commands.append(command.duplicate(true)); world.queue_command(command))
	root.add_child(screen); screen.set_process(false)
	screen.apply_snapshot(world.snapshot(false))
	var view := screen.world_view
	view.focus=view.world_position(18,18)
	view.zoom=10
	var house_node: Node3D=view.home_nodes[house]
	var mesh: MeshInstance3D=house_node.get_node_or_null("Building/Complete")
	if mesh==null:
		for child: Node in house_node.get_children():
			if child is MeshInstance3D and child.visible and not "shadow" in str(child.get_meta("role","")):
				mesh=child
				break
	check(mesh!=null,"The overlap regression needs the visible original house mesh")
	var house_click := covering_click(view,mesh,mesh.global_transform) if mesh!=null else Vector2.INF
	check(house_click!=Vector2.INF,"Clicking a house above the shrine must exercise the offset between its mesh and terrain")
	if house_click!=Vector2.INF:
		click(view,house_click)
		check(screen.selected_building_kind=="home" and screen.selected_home==house and not screen.building_panel.popup.visible,"A projected roof click must select the house instead of the shrine")
	check(screen.world_view.temple_at(Vector2(17,18)).is_empty(),"A covering house must intercept the shrine's overlapping hotspot")
	screen.on_action(Vector2i(17,18),Vector2(17,18))
	check(screen.selected_building_kind=="home" and screen.selected_home==house and not screen.building_panel.popup.visible,"Clicking the covering house must select that house, never the shrine underneath")
	if house_click!=Vector2.INF:
		commands=[]
		screen.select_power("GodPower_Beautify")
		click(view,house_click)
		var ground := view.pick(house_click)
		check(commands.size()==1 and commands[0].get("x")==ground.x and commands[0].get("z")==ground.y,"Terrain powers must keep the original ground projection")
	commands=[]
	screen.building_panel.popup.show()
	screen.select_power("GodPower_FingerOfGod")
	check(not screen.building_panel.popup.visible,"Arming a clearing power must dismiss building inspection so it can reach the map")
	if house_click!=Vector2.INF: click(view,house_click)
	else: screen.on_action(Vector2i(17,18),Vector2(16.6,18))
	check(commands.size()==1 and commands[0].get("power")=="GodPower_FingerOfGod" and commands[0].get("home_id")==house,"The original clearing power must target the clicked house")
	world.step()
	check(world._state["homes"].is_empty() and world._state["progression"]["shrines"].size()==1,"Finger of God must remove the covering house and preserve the shrine")
	var tree_data := definition(); tree_data["automatic_settlement"]=false
	tree_data["tree_field"][18*64+18]=1
	var distant_tree_cell := 24*64+18
	tree_data["tree_field"][distant_tree_cell]=1
	tree_data["progression_rules"]["vegetation"]["taps_to_clear"]=2
	var wooded := create(tree_data)
	screen.inspect_action=wooded.inspect; screen.inspect_building=wooded.inspect_building
	screen.intent.disconnect(screen.intent.get_connections()[0]["callable"])
	screen.intent.connect(func(command: Dictionary) -> void: commands.append(command.duplicate(true)); wooded.queue_command(command))
	# Switch the fixture's static scenery index as a fresh campaign would.
	view.trees.initialized=false
	screen.choose_tool("sculpt"); screen.apply_snapshot(wooded.snapshot()); commands=[]
	view.trees.build_tile(Vector2i.ZERO)
	var tree_cell := 18*64+18
	var tree: Dictionary=view.tree_index[tree_cell]
	var tree_mesh: MeshInstance3D=view.trees.templates[view.trees.tree_variant(tree)]
	var transform := Transform3D(Basis.from_scale(Vector3.ONE*0.003),view.trees.tree_position(tree,tree_cell))
	var canopy_click := covering_click(view,tree_mesh,transform)
	check(canopy_click!=Vector2.INF,"The original canopy must project onto the shrine hotspot outside the tree's ground cell")
	check(screen.world_view.temple_at(Vector2(18,18)).is_empty(),"A covering tree must prevent shrine selection")
	if canopy_click!=Vector2.INF:
		click(view,canopy_click)
		var base: Vector2=view.camera.unproject_position(view.world_position(18,18))
		click(view,base,true)
	check(commands.size()==2 and commands.all(func(command: Dictionary) -> bool: return command.get("type")=="tap_tree" and command.get("cell")==tree_cell),"Both taps must target the tree without digging or opening the shrine")
	wooded.step()
	check(not wooded.tree_at(18,18),"Two accepted taps must clear the tree")
	screen.apply_snapshot(wooded.snapshot())
	if not wooded.tree_at(18,18): check(screen.world_view.temple_at(Vector2(18,18))=="1012","Clearing the last tree must expose ordinary shrine inspection")
	# At a shallow angle a canopy can cover the shrine even when its trunk
	# stands outside the shrine's footprint.
	var distant: Dictionary=view.tree_index[distant_tree_cell]
	var distant_mesh: MeshInstance3D=view.trees.templates[view.trees.tree_variant(distant)]
	var distant_transform := Transform3D(Basis.from_scale(Vector3.ONE*0.003),view.trees.tree_position(distant,distant_tree_cell))
	view.elevation=0.2
	var distant_click := covering_click(view,distant_mesh,distant_transform,[0.0])
	check(distant_click!=Vector2.INF,"The outside tree must project onto the shrine's hotspot")
	screen.building_panel.popup.show()
	commands=[]
	if distant_click!=Vector2.INF:
		click(view,distant_click)
		click(view,distant_click,true)
	check(not screen.building_panel.popup.visible,"A covering-tree click on the map must dismiss stale shrine inspection")
	check(commands.size()==2 and commands.all(func(command: Dictionary) -> bool: return command.get("type")=="tap_tree" and command.get("cell")==distant_tree_cell),"A canopy covering the shrine must receive both taps even when its trunk is outside the shrine footprint")
	wooded.step()
	check(not wooded.tree_at(18,24),"Both canopy taps must clear the outside tree")
	screen.apply_snapshot(wooded.snapshot())
	commands=[]
	if distant_click!=Vector2.INF: click(view,distant_click,true)
	check(commands.is_empty() and screen.selected_building_kind=="temple" and screen.selected_home=="1012" and screen.building_panel.popup.visible,"Clicking the exposed shrine again must inspect it without digging")
	var buried := tree_data.duplicate(true)
	buried["tree_field"].fill(0); buried["terrain"][18*64+18]=5
	var covered := create(buried)
	screen.apply_snapshot(covered.snapshot(false))
	check(screen.world_view.temple_at(Vector2(18,18)).is_empty() and screen.world_view.progression_at(Vector2(18,18)).is_empty(),"Buried terrain must reach the terrain gesture instead of an invisible shrine click target")
	screen.queue_free(); await process_frame; await process_frame
	print("Shrine blockers, covering-object selection and original clearing power: %d failures"%failures)
	quit(1 if failures else 0)
