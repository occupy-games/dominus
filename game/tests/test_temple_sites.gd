extends SceneTree

const World = preload("res://simulation/world.gd")
const Temples = preload("res://simulation/temple_rules.gd")
const Content = preload("res://infrastructure/temple_sites.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	root.size=Vector2i(1000,760)
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(not opening.is_empty(),"Original Homeworld6 definitions must remain loadable")
	if opening.is_empty(): quit(1); return
	var sites := Content.sites("initialworldsetup6",opening["story"]["source_sha256"])
	check(sites.size()==27 and opening["progression_rules"]["shrines"]==sites,"Homeworld6 must own all 27 authored site records without translating them")
	var beacon: Dictionary={}
	for site: Dictionary in sites:
		if site["id"]=="1012": beacon=site.duplicate(true)
	check(beacon.get("model_id")=="shrineexpansion.group.bin:dff1563f" and beacon.get("x")==165 and beacon.get("z")==144,"The first beacon must use its original model and coordinates")
	check(Content.sites("initialworldsetup6","wrong-hash").is_empty(),"Mismatched temple provenance must reject")
	check(Content.sites("initialworldsetup3",opening["story"]["source_sha256"]).is_empty(),"Unresolved duplicate source IDs must not be silently renamed")
	var legacy := preload("res://infrastructure/campaign_content.gd").homeworld()
	for site: Dictionary in legacy["progression_rules"]["shrines"]:
		if site["card"]=="Card_Expansion":
			check(site["model_id"]=="shrineexpansion.group.bin:dff1563f","Compatibility beacons must not use God Power shrine artwork")
			var art := preload("res://infrastructure/building_info.gd").record({"entity":"temple","site_type":site["type"],"reward_card":site["card"]})
			check(art.get("title")=="Beacon" and art.has("texture"),"Legacy beacon records must resolve their original info artwork too")
	var definition := preload("res://tests/fixtures/campaign_economy.gd").definition()
	definition["followers"]=[{"x":14,"z":16},{"x":15,"z":16},{"x":14,"z":17},{"x":15,"z":17}]
	definition["terrain"].fill(1)
	beacon.merge({"x":18,"z":18,"food_cost":3,"ore_cost":2,"build_ticks":20},true)
	definition["progression_rules"]["shrines"]=[beacon]
	definition["progression_rules"]["source_unlocks"]["TempleTestExpansion"]=["TEMPLE_COMPLETE_1012"]
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed=1012
	world.initialize({"campaign_data":definition},rng)
	var stored := world.export_state()
	stored["state"]["belief"]=0
	stored["state"]["home_cost"]=25
	stored["state"]["wheat"]=3
	stored["state"]["ore"]=1
	check(world.restore(stored,RandomNumberGenerator.new()),"Controlled temple repair state must restore")
	var command := {"type":"repair_shrine","id":"1012"}
	var inspected := world.inspect(command)
	check(not inspected["ok"] and inspected.get("missing",{})=={"ore":1},"A temple must check its authored ore cost before assigning workers")
	var screen := preload("res://presentation/world/game_screen.gd").new()
	screen.campaign_mode=true
	screen.terrain_palette=preload("res://infrastructure/game_content.gd").new().terrain_palette()
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.inspect_action=world.inspect
	screen.inspect_building=world.inspect_building
	screen.resolve_building_info=preload("res://infrastructure/building_info.gd").record
	screen.building_info_labels=preload("res://infrastructure/building_info.gd").content()["labels"]
	var catalog := preload("res://infrastructure/asset_catalog.gd").new()
	catalog.read_models()
	screen.resolve_building=catalog.building_data
	var commands: Array=[]
	screen.intent.connect(func(value: Dictionary) -> void: commands.append(value))
	root.add_child(screen)
	screen.apply_snapshot(world.snapshot(false))
	var anchor: Vector3=screen.world_view.progression_nodes["shrine:1012"].position
	check(anchor==screen.world_view.world_position(18,18),"The authored beacon center must be its displayed and selected map anchor")
	var site_view: Node3D=screen.world_view.progression_nodes["shrine:1012"]
	var map_region: Rect2i=screen.world_view.terrain_region
	screen.world_view.terrain_region=Rect2i(0,0,2,2)
	screen.world_view.update_progression()
	check(not site_view.visible and screen.world_view.temple_at(Vector2(18,18)).is_empty(),"A streamed-out temple must leave both drawing and picking")
	screen.world_view.terrain_region=map_region
	screen.world_view.update_progression()
	check(site_view.visible and screen.world_view.temple_at(Vector2(18,18))=="1012","Returning to the temple region must restore drawing and picking together")
	var site_snapshot: Dictionary=screen.world_view.state.duplicate(true)
	screen.world_view.state["progression"]["shrines"][0]["complete"]=true
	screen.world_view.update_progression()
	check(site_view.revealed_parts==site_view.maximum_part(),"An already completed standalone site must display the whole recovered temple")
	screen.world_view.state=site_snapshot
	screen.world_view.update_progression()
	check(site_view.revealed_parts==1,"Restoring an unstarted site must restore its ruin components")
	screen.world_view.state["progression"]["shrines"][0]["model_id"]="unrecovered-site"
	screen.world_view.update_progression()
	check(not screen.world_view.progression_nodes.has("shrine:1012") and screen.world_view.temple_at(Vector2(18,18)).is_empty(),"Unavailable site models must leave neither stale artwork nor an invisible selection target")
	screen.apply_snapshot(world.snapshot(false))
	screen.world_view.state["progression"]["shrines"]=[]
	screen.world_view.update_progression()
	check(not screen.world_view.progression_nodes.has("shrine:1012"),"Loading a world without a prior temple must remove that temple from the map")
	screen.apply_snapshot(world.snapshot(false))
	var before := world.export_state()
	screen.on_action(Vector2i(18,18),Vector2(18,18))
	check(commands.is_empty() and world.export_state()==before,"Selecting a temple must inspect it without spending resources or starting repair")
	check(screen.selected_building_kind=="temple" and screen.selected_home=="1012" and screen.building_panel.popup.visible,"The dormant authored site must open its temple details")
	check(screen.building_panel.title.text=="Beacon" and screen.building_panel.picture.texture!=null,"Temple inspection must resolve its original title and illustration")
	var missing_art := preload("res://infrastructure/building_info.gd").record({"entity":"temple","site_type":"unrecovered","title_key":"LOC_TemplePos_Title_Beacon"})
	check(missing_art.get("title")=="Beacon" and not missing_art.has("texture"),"A localized site without recovered artwork must not borrow another temple illustration")
	check(screen.building_panel.repair_button.disabled and screen.building_panel.row_values["LOC_ROWNAME_HOME_ORE_CONSUMPTION"].text=="1 / 2","Missing temple resources must be visible and disable the builder action")
	if "--capture-temple-inspection" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/temple-inspection.png")
	var detached := world.inspect_building("1012","temple")
	detached["food_cost"]=999
	check(world.inspect_building("1012","temple")["food_cost"]==3,"Temple inspection must remain detached from authoritative site costs")
	stored=world.export_state()
	stored["state"]["ore"]=2
	check(world.restore(stored,RandomNumberGenerator.new()),"Temple resources must restore independently of belief")
	inspected=world.inspect(command)
	check(inspected["ok"] and inspected["cost"]==0,"Temple repair must not charge the separate house belief cost")
	screen.apply_snapshot(world.snapshot(false))
	check(not screen.building_panel.repair_button.disabled,"An affordable reachable temple must enable its builder action")
	screen.building_panel.repair_button.pressed.emit()
	check(commands==[command],"Only the explicit builder action may request temple repair")
	world.step([command])
	var state := world.snapshot(false)
	screen.apply_snapshot(state)
	check(screen.world_view.home_nodes[state["homes"][0]["id"]].position==anchor,"Starting repair must not shift the original temple center or elevation")
	check(screen.world_view.home_nodes[state["homes"][0]["id"]].revealed_parts>=1,"Starting repair must retain the recovered ruin components")
	check(screen.building_panel.stats["started"] and not screen.building_panel.repair_button.get_parent().visible,"An active temple repair must keep live inspection and hide repeat payment")
	check(int(state.get("wheat",0))==0 and int(state.get("ore",0))==0 and state["belief"]==0,"Authored repair resources must be charged exactly once")
	check(state["homes"].size()==1 and state["homes"][0]["build_capacity"]==2 and state["homes"][0]["model_id"]==beacon["model_id"],"Repair must retain the original builder cap and assembled beacon")
	check(not world.inspect(command)["ok"] and not Unlocks.enabled(state["progression"],"TempleTestExpansion"),"An active repair cannot restart or unlock land early")
	var codec := preload("res://infrastructure/world_store.gd").new()
	stored=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(world.export_state()))))
	var resumed := World.new()
	check(resumed.restore(stored,RandomNumberGenerator.new()),"Active temple work must survive real save restoration")
	for i in range(200): world.step(); resumed.step()
	state=world.snapshot(false)
	screen.apply_snapshot(state)
	var repaired: Node3D=screen.world_view.home_nodes[state["homes"][0]["id"]]
	check(repaired.position==anchor and not repaired.visible,"The repaired temple must stay anchored when its completed components are batched")
	var instances := 0
	for batch: MultiMeshInstance3D in screen.world_view.building_batches.get_children(): instances+=batch.multimesh.instance_count
	var components := 0
	for component: Dictionary in repaired.components:
		if component["node"].visible: components+=1
	check(instances==components and components>0,"A repaired temple must retain every recovered completed component exactly once on the map")
	if "--capture-temple-sites" in OS.get_cmdline_user_args():
		screen.building_panel.popup.hide()
		screen.world_view.zoom=14
		screen.world_view.update_camera(false)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/temple-completed.png")
		screen.building_panel.popup.show()
	var builds: int=screen.world_view.building_batches.builds
	var changed := state.duplicate(true)
	changed["progression"]["shrines"][0]["source_height"]=22
	screen.world_view.apply_snapshot(changed)
	check(is_equal_approx(screen.world_view.home_nodes[state["homes"][0]["id"]].position.y,3*preload("res://presentation/world/terrain_view.gd").STEP),"Restored site elevation must reach the completed temple anchor")
	check(screen.world_view.building_batches.builds==builds+1,"Restored site elevation must update the completed instance transforms")
	changed=state.duplicate(true)
	changed["homes"][0]["model_id"]="unrecovered-temple"
	screen.world_view.apply_snapshot(changed)
	check(screen.world_view.home_nodes[state["homes"][0]["id"]].get_child_count()==0,"An unresolved saved temple must not be presented as a tent")
	screen.apply_snapshot(state)
	check(screen.building_panel.stats["complete"] and screen.building_panel.row_values["LOC_ROWNAME_SHRINE_BUILDING"].text=="Repaired","Temple details must follow one-time completion")
	check(Temples.completed(state["progression"],"1012") and Unlocks.enabled(state["progression"],"TempleTestExpansion"),"Completed site IDs must satisfy the original TEMPLE_COMPLETE unlock conditions")
	check(world.export_state()==resumed.export_state(),"Temple work, payment and completion must continue identically after restoration")
	check(not Temples.complete(state["progression"],"1012"),"Repeated completion cannot grant a second reward")
	for overrides: Dictionary in [{"model_id":""},{"build_ticks":0},{"complete":true}]:
		var unavailable := before.duplicate(true)
		unavailable["state"]["ore"]=2
		unavailable["state"]["progression"]["shrines"][0].merge(overrides,true)
		var blocked := World.new()
		check(blocked.restore(unavailable,RandomNumberGenerator.new()),"An unavailable site descriptor must remain readable for inspection")
		var unchanged := blocked.export_state()
		check(not blocked.inspect(command)["ok"],"Missing temple content, inert sites and completed sites cannot start repairs")
		blocked.step([command])
		check(blocked._state["homes"].is_empty() and blocked._state["ore"]==unchanged["state"]["ore"] and blocked._state["wheat"]==unchanged["state"]["wheat"],"Rejected site repairs cannot create a substitute building or spend resources")
	stored=world.export_state()
	stored["state"]["progression"]["rules"]["version"]=7
	stored["state"]["homes"][0]["model_id"]="shrinegodpower.group.bin:dff1563f"
	stored["state"]["homes"][0]["build_capacity"]=1
	check(world.restore(stored,RandomNumberGenerator.new()),"A prior temple save must remain readable")
	world.migrate_progression(definition["progression_rules"],definition["rock_field"])
	state=world.snapshot(false)
	check(state["homes"][0]["model_id"]==beacon["model_id"] and state["homes"][0]["build_capacity"]==2,"Existing temple jobs must receive corrected source models and worker caps")
	check(state["homes"][0]["build_ticks"]==20 and Temples.completed(state["progression"],"1012") and int(state.get("ore",0))==0,"Migration must preserve edited repair time, completion and previous payment")
	screen.building_panel.popup.hide()
	screen.is_paused=true
	screen.on_action(Vector2i(18,18),Vector2(18,18))
	check(screen.building_panel.popup.visible and screen.selected_building_kind=="temple" and commands.size()==1,"Completed temple sites must remain inspectable while paused")
	screen.free()
	if "--capture-temple-sites" in OS.get_cmdline_user_args():
		root.size=Vector2i(1000,760)
		var view := preload("res://presentation/world/world_view.gd").new()
		view.resolve_building=catalog.building_data
		view.terrain.colors=preload("res://infrastructure/game_content.gd").new().terrain_palette()
		root.add_child(view)
		view.set_process(false)
		state["homes"]=[]
		state["followers"]=[]
		state["progression"]["shrines"][0]["started"]=false
		view.apply_snapshot(state)
		view.zoom=14
		view.update_camera(false)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../build/temple-sites.png")
		check(view.progression_nodes.has("shrine:1012"),"The recovered beacon site must be visible on the map")
		view.queue_free()
		await process_frame
	print("Original temple sites, repair costs, completion gates and save continuation: %d failures"%failures)
	quit(1 if failures else 0)
