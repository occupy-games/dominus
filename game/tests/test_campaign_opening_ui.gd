extends SceneTree

const World = preload("res://simulation/world.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func run() -> void:
	var data := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := World.new()
	world.initialize({"campaign_data":data},RandomNumberGenerator.new())
	var assets := preload("res://infrastructure/game_content.gd").new().follower_assets(true)
	for role: String in ["drowning","hugging_give","hugging_take","worshipping","scared"]:
		check(assets["clips"].has(role) and not assets["clips"][role]["frames"].is_empty(),"The opening must load its actual original animation: "+role)
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.follower_assets=assets
	screen.scenery_assets=preload("res://infrastructure/game_content.gd").new().scenery_assets()
	check(screen.scenery_assets.get("rocks",{}).get("models",[]).size()==7,"Independent source campaign views must receive the original boulder meshes without relying on FrontEnd")
	screen.inspect_action=world.inspect
	screen.locate_edge=world.find_edge
	root.add_child(screen)
	var observations: Array = []
	screen.world_view.observer_changed.connect(func(command: Dictionary) -> void: observations.append(command))
	screen.world_view.orbiting=true
	screen.world_view.panning=true
	screen.apply_snapshot(world.snapshot())
	await process_frame
	await process_frame
	check(not observations.is_empty() and world.inspect(observations[0])["ok"],"Presentation must submit a plain, validated camera observation")
	var observation: Dictionary = screen.world_view.camera_observation()
	var projection: Array = observation["projection"]
	for point: Vector2 in [Vector2(163,53),Vector2(164,66),Vector2(157,121)]:
		var position: Vector3 = screen.world_view.world_position(point.x,point.y)
		var native: Vector2 = screen.world_view.camera.unproject_position(position)/root.get_visible_rect().size
		var simulated := Vector2(projection[0]*point.x+projection[1]*point.y+projection[2]*position.y+projection[3],projection[4]*point.x+projection[5]*point.y+projection[6]*position.y+projection[7])
		check(native.distance_to(simulated)<0.001,"Plain observation must reproduce the camera projection, including terrain height")
	var focus: Vector3 = screen.world_view.focus
	var zoom: float = screen.world_view.zoom
	screen.world_view.trackpad_pan(Vector2(40,40),false)
	screen.world_view.zoom_by(0.5)
	check(screen.world_view.focus==focus and screen.world_view.zoom==zoom,"Source tutorial locks must prevent trackpad camera and zoom input")
	check(not screen.world_view.orbiting and not screen.world_view.panning,"A source camera lock must cancel any gesture already in progress")
	check(screen.campaign_prompt.messages.has(2) and screen.campaign_prompt.messages.has(3),"The original rescue instructions must be present")
	check(screen.campaign_prompt.messages[3].mouse_filter==Control.MOUSE_FILTER_IGNORE,"A passive terrain hint must not prevent the drag it explains")
	for actor: Node3D in screen.world_view.actor_nodes.values():
		actor.animation_state="drowning"
		actor.apply_animation(0.4)
		check(actor.last_clip=="drowning","Drowning must sample the original clip rather than fall back to idle")
	# Original DesktopHigh influence expands over two seconds before this
	# rescue gesture reaches the starting area's outer bank.
	for tick in range(21): world.step()
	var rescue := {"type":"sculpt_drag","x":166,"z":58,"nx":0,"nz":-1,"layer":1,"distance":5,"dx":-3,"dz":-5,"radius":1}
	check(world.inspect(rescue)["ok"],"The rescue gesture must wait for native influence to reach the bank")
	world.step([rescue])
	for tick in range(60): world.step()
	screen.apply_snapshot(world.snapshot())
	await process_frame
	check(screen.campaign_prompt.messages.has(4),"The saved-followers message must follow the actual rescue timer")
	for viewport_size: Vector2i in [Vector2i(1000,680),Vector2i(1600,1000)]:
		root.size=viewport_size
		await process_frame
		for button: Button in screen.campaign_prompt.messages.values():
			check(root.get_visible_rect().encloses(button.get_global_rect()) and button.size.x>=400 and button.size.y<200,"Source tutorial text must stay readable and within resized viewports")
	var commands: Array = []
	screen.intent.connect(func(command: Dictionary) -> void: commands.append(command))
	screen.campaign_prompt.messages[4].pressed.emit()
	check(commands==[{"type":"campaign_ack","id":4}],"The source message must forward a command rather than mutate the world")
	world.step(commands)
	check(world.snapshot(false)["opening"]["phase"]=="trail","The same UI command must activate the authored trail")
	# The follower tooltip is original localized content; source handles remain
	# simulation-owned and the corresponding presentation is passive.
	world._state["opening"]["tips"]={"1":{"follower":world._state["followers"][0]["id"],"key":"LOC_TUT_210"}}
	screen.apply_snapshot(world.snapshot())
	check(screen.campaign_prompt.messages.has(-1) and screen.campaign_prompt.messages[-1].text==data["story"]["tip_text"]["LOC_TUT_210"] and screen.campaign_prompt.messages[-1].mouse_filter==Control.MOUSE_FILTER_IGNORE,"The camera tutorial must display its original follower hint without consuming terrain gestures")
	world._state["opening"]["camera_locked"]=false
	world._state["opening"]["zoom_locked"]=false
	screen.apply_snapshot(world.snapshot())
	screen.world_view.trackpad_pan(Vector2(40,40),false)
	screen.world_view.zoom_by(0.5)
	check(screen.world_view.focus!=focus and screen.world_view.zoom<zoom,"An unlocked tutorial must restore pan and zoom controls")
	# Detached UI fixture: group-local source IDs must remain separate from Trail.
	var promised_ui := world.snapshot()
	promised_ui["opening"]["tips"]={}
	promised_ui["opening"]["messages"]=[{"id":1002,"callback":{"builtin":"nextPromisedLandStep"},"anchor":{"kind":"rock","x":161,"z":123}}]
	screen.apply_snapshot(promised_ui)
	check(screen.campaign_prompt.messages.has(1002) and not screen.campaign_prompt.messages.has(4),"Promised Land's namespaced explanations must replace the correct source controls")
	check(screen.campaign_prompt.messages[1002].text==data["story"]["messages"]["1002"]["text"] and screen.campaign_prompt.current[1002]["pos3d"]=={"1":161,"2":123},"The original rock explanation must use its detached object anchor and localization")
	check(root.get_visible_rect().encloses(screen.campaign_prompt.messages[1002].get_global_rect()),"An offscreen source object must not put its explanation outside the viewport")
	commands.clear()
	screen.campaign_prompt.messages[1002].pressed.emit()
	check(commands==[{"type":"campaign_ack","id":1002}] and not world.inspect(commands[0])["ok"],"A namespaced source explanation must forward intent without mutating the real world's different tutorial")
	var source_cell := 123*1024+161
	for point: Vector2 in [Vector2(160,122),Vector2(161,122),Vector2(160,123),Vector2(161,123)]:
		check(screen.world_view.progression_at(point)=={"type":"tap_object","cell":source_cell},"All source rock parts must pick the same authored object, including zero-density cells")
	var rock_snapshot := world.snapshot()
	check(rock_snapshot["authored_rocks"].is_read_only() and rock_snapshot["authored_rocks"][0].is_read_only(),"Static source placement descriptors must be shared immutable data")
	rock_snapshot["source_rock_visibility"][0]=0
	check(world.snapshot(false)["source_rock_visibility"][0]==1,"Mutable visibility masks must be detached from the authoritative query cache")
	screen.world_view.set_process(false)
	var rocks: Node3D = screen.world_view.rocks
	rocks.update(world.snapshot(),Rect2i(156,118,12,12))
	while not rocks.pending.is_empty(): await process_frame
	check(rocks.authored_rocks.has(source_cell) and rocks.templates.has(5),"The original sixth boulder must participate in the independent source scenery batches")
	var tile_key := Vector2i(2,1)
	check(rocks.index[tile_key].count(source_cell)==1 and not rocks.index[tile_key].has(123*1024+160),"An authored rock must render once rather than one rock per occupied packed byte")
	var instances_before := 0
	for batch: MultiMeshInstance3D in rocks.tiles[tile_key].get_children(): instances_before+=batch.multimesh.instance_count
	var removed_snapshot := world.snapshot()
	removed_snapshot["source_rock_visibility"][0]=0
	removed_snapshot["progression"]["rock_revision"]+=1
	screen.apply_snapshot(removed_snapshot)
	check(screen.world_view.progression_at(Vector2(161,123)).is_empty(),"A removed authored rock must not expose a phantom packed-cell click target")
	rocks.update(removed_snapshot,Rect2i(156,118,12,12))
	while not rocks.pending.is_empty(): await process_frame
	var instances_after := 0
	for batch: MultiMeshInstance3D in rocks.tiles[tile_key].get_children(): instances_after+=batch.multimesh.instance_count
	check(instances_after==instances_before-1,"Detached source visibility must remove exactly one complete boulder from its rendering batch")
	var catalog := preload("res://infrastructure/asset_catalog.gd").new()
	catalog.read_models()
	screen.world_view.resolve_unit=catalog.unit_data
	var chest_snapshot := world.snapshot(false)
	chest_snapshot["progression"]["chests"]=[{"id":"reward:5","type":"treasure1","x":177,"z":147,"height":1.0,"rotation":180.0,"card":"Sticker_Tools_1","opened":false,"opening":false,"native":true,"exposed":true}]
	screen.world_view.state=chest_snapshot
	screen.world_view.terrain_region=Rect2i(172,142,10,10)
	screen.world_view.update_progression()
	check(screen.world_view.progression_nodes.has("chest:reward:5"),"The source first chest must render with its recovered model")
	check(screen.world_view.progression_at(Vector2(177,147))=={"type":"open_chest","id":"reward:5"},"The exposed source chest must offer its ordinary command")
	var chest_actor: Node3D=screen.world_view.progression_nodes["chest:reward:5"]
	chest_actor.apply_animation(0.2)
	check(chest_actor.last_clip=="chest_freed","The source exposure state must select the original freed animation")
	chest_snapshot["progression"]["chests"][0]["opening"]=true
	screen.world_view.update_progression()
	chest_actor.apply_animation(0.2)
	check(chest_actor.last_clip=="chest_open" and not chest_actor.looped and screen.world_view.progression_at(Vector2(177,147)).get("type")!="open_chest","The native opening must play its source animation once and reject repeat picking")
	chest_snapshot["progression"]["chests"][0]["opened"]=true
	screen.world_view.update_progression()
	check(screen.world_view.progression_nodes.has("chest:reward:5"),"The granted source chest must remain until its native disappearance delay")
	chest_snapshot["progression"]["chests"]=[]
	screen.world_view.update_progression()
	check(not screen.world_view.progression_nodes.has("chest:reward:5"),"The native removal snapshot must remove the complete chest actor")
	# Isolated Timeline UI fixture. The complete played trail is verified by
	# test_promised_land; these commands exercise the normal HUD and drag route.
	var opening: Dictionary=world._state["opening"]
	var level_card: String=data["story"]["growth_population_card"]["id"]
	opening["level_card"]=level_card
	opening["scheduled"]=[]
	opening["promised_step"]=11
	opening["globals"]["onStartPlayTriggered"]=true
	preload("res://simulation/progression.gd").discover(world._state["progression"],level_card)
	preload("res://simulation/progression.gd").reward(world._state,"Sticker_Tools_1")
	var tutorial := preload("res://simulation/campaign_opening.gd").new()
	tutorial.configure(world,world._state,[])
	tutorial.set_timeline_step(0)
	screen.apply_snapshot(world.snapshot())
	commands.clear()
	screen.original_hud.collection_button.pressed.emit()
	check(commands==[{"type":"campaign_timeline_open"}] and not screen.progression_panel.visible,"The original corner button must request the authoritative Timeline opening")
	var opened: Array=world.step(commands)
	screen.apply_snapshot(world.snapshot(),opened)
	check(screen.progression_panel.visible and screen.progression_panel.selected==level_card and screen.campaign_prompt.messages.has(2003),"The source open command must display the card and original explanation")
	commands.clear()
	screen.progression_panel.close_button.pressed.emit()
	check(commands.is_empty() and screen.progression_panel.visible and screen.progression_panel.close_button.disabled and not screen.progression_panel.resource_slots["Sticker_Tools_1"].resource_drag_enabled and not screen.progression_panel.detail_card.accept_resource.call("Sticker_Tools_1")["ok"],"The actual close button, resource drag and drop preview must respect the source explanation lock")
	for id in [2003,2004,2005]:
		commands.clear()
		screen.campaign_prompt.messages[id].pressed.emit()
		var updates: Array=world.step(commands)
		screen.apply_snapshot(world.snapshot(),updates)
	await process_frame
	screen.campaign_prompt.layout_messages()
	check(screen.campaign_prompt.z_index>screen.progression_panel.z_index and screen.progression_panel.resource_slots["Sticker_Tools_1"].resource_drag_enabled and screen.progression_panel.detail_card.accept_resource.call("Sticker_Tools_1")["ok"],"The source explanations must stay above the Timeline and enable the actual typed drop")
	var source_tip: Control=screen.campaign_prompt.messages[2007]
	var resource_target: Rect2=screen.tutorial_target(data["story"]["messages"]["2007"])
	check(resource_target.has_area() and root.get_visible_rect().encloses(source_tip.get_global_rect()) and source_tip.mouse_filter==Control.MOUSE_FILTER_IGNORE,"The original sticker hint must anchor to its resource tray and leave the drag target accessible")
	commands.clear()
	screen.progression_panel.detail_card.assign_resource.call("Sticker_Tools_1")
	check(commands==[{"type":"research_card","card":level_card,"sticker":"Sticker_Tools_1"}],"The real card drop must submit its typed assignment command")
	var assigned: Array=world.step(commands)
	screen.apply_snapshot(world.snapshot(),assigned)
	check(screen.progression_panel.visible and screen.campaign_prompt.messages.has(2008),"Card completion must preserve the source Timeline until its exit is requested")
	commands.clear()
	screen.progression_panel.close_button.pressed.emit()
	check(commands==[{"type":"campaign_timeline_close"}] and screen.progression_panel.visible,"The unlocked source exit must request a command before hiding")
	var closed: Array=world.step(commands)
	screen.apply_snapshot(world.snapshot(),closed)
	check(not screen.progression_panel.visible and opening["timeline_step"]==4,"The accepted original exit must close presentation and return to Homeworld")
	# Detached render fixture for the completed but unactivated source Beacon.
	var beacon := world.snapshot()
	beacon["opening"]["phase"]="shrine"
	beacon["opening"]["shrine_step"]=3
	var source_site: Dictionary=beacon["progression"]["shrines"].filter(func(site: Dictionary) -> bool: return site["id"]==beacon["opening"]["definition"]["first_shrine_id"])[0]
	source_site["started"]=true
	source_site["repaired"]=true
	beacon["opening"]["shrine_claims"]=[source_site["id"]]
	screen.world_view.apply_campaign_camera({"action":"SetCamera","args":[source_site["x"],source_site["z"]]})
	screen.apply_snapshot(beacon)
	var beacon_card: TextureButton=screen.shrine_rewards.get(source_site["id"],{}).get("button")
	check(is_instance_valid(beacon_card) and beacon_card.visible and beacon_card.source["id"]=="Card_Expansion","The pending Beacon must display its original card above the authored site")
	commands.clear()
	beacon_card.pressed.emit()
	check(commands==[{"type":"campaign_activate_shrine","id":source_site["id"]}],"Clicking the Beacon card must submit the authoritative activation command")
	source_site["complete"]=true
	beacon["opening"]["shrine_claims"]=[]
	screen.apply_snapshot(beacon)
	check(not screen.shrine_rewards.has(source_site["id"]),"The activated Beacon must remove its pending card")
	var belief := world.snapshot()
	var belief_card: String=data["story"]["shrine_population_card"]["id"]
	belief["progression"]["discovered"].append(belief_card)
	belief["opening"]["phase"]="belief"
	belief["opening"]["belief_step"]=0
	belief["opening"]["messages"]=[{"id":4007,"callback":null,"visible_tick":belief["tick"]+300}]
	screen.apply_snapshot(belief)
	check(not screen.campaign_prompt.messages.has(4007),"The original population-card hint must wait for its authored delay")
	belief["tick"]+=300
	screen.apply_snapshot(belief)
	check(screen.campaign_prompt.messages.has(4007),"The original population-card hint must appear at its authored tick")
	commands.clear()
	screen.original_hud.card_nodes[belief_card].pressed.emit()
	check(commands==[{"type":"campaign_show_level_card"}],"The source Power of Prayer portrait must request its authoritative card action")
	belief["opening"]["belief_step"]=1
	belief["opening"]["messages"]=[{"id":4001,"callback":null}]
	screen.apply_snapshot(belief,[{"type":"campaign_show_card","card":belief_card}])
	check(screen.progression_panel.visible and screen.progression_panel.selected==belief_card and screen.campaign_prompt.messages.has(4001),"The Power of Prayer action must show its original card and explanation")
	commands.clear()
	screen.progression_panel.close_button.pressed.emit()
	check(commands==[{"type":"campaign_dismiss_level_card"}],"Closing Power of Prayer must submit the source dismissal command")
	belief["opening"]["belief_step"]=3
	belief["opening"]["belief_hud_hidden"]=false
	belief["belief"]=580
	belief["opening"]["messages"]=[{"id":4004,"callback":{"builtin":"nextBeliefStep"}}]
	screen.apply_snapshot(belief)
	check(screen.original_hud.belief.visible and screen.original_hud.belief.text=="580" and screen.tutorial_target(data["story"]["messages"]["4004"]).has_area(),"The source counter explanation must point to the actual visible belief balance")
	commands.clear()
	screen.campaign_prompt.messages[4004].pressed.emit()
	check(commands==[{"type":"campaign_ack","id":4004}],"The source counter hint must advance through an ordinary acknowledgement command")
	var discovery := world.snapshot()
	var pit_id: String=data["story"]["discovery_site_id"]
	var pit: Dictionary=discovery["progression"]["shrines"].filter(func(site: Dictionary) -> bool: return site["id"]==pit_id)[0]
	discovery["opening"]["phase"]="discovery"
	discovery["opening"]["discovery_step"]=2
	discovery["opening"]["pit_step"]=0
	discovery["opening"]["messages"]=[]
	pit["started"]=true
	pit["repaired"]=true
	discovery["opening"]["shrine_claims"]=[pit_id]
	screen.world_view.apply_campaign_camera({"action":"SetCamera","args":[pit["x"],pit["z"]]})
	screen.apply_snapshot(discovery)
	var pit_card: TextureButton=screen.shrine_rewards.get(pit_id,{}).get("button")
	check(is_instance_valid(pit_card) and pit_card.visible and pit_card.source["id"]=="Card_PitOfSacrifice","The completed Pit must display its own original card")
	commands.clear()
	pit_card.pressed.emit()
	check(commands==[{"type":"campaign_activate_shrine","id":pit_id}],"The Pit portrait must submit its own source site ID")
	pit["complete"]=true
	discovery["opening"]["shrine_claims"]=[]
	discovery["opening"]["pit_card_open"]=true
	discovery["opening"]["messages"]=[{"id":5101,"callback":null}]
	discovery["progression"]["discovered"].append(pit["card"])
	discovery["progression"]["completed"].append(pit["card"])
	screen.apply_snapshot(discovery,[{"type":"campaign_show_card","card":pit["card"]}])
	check(not screen.shrine_rewards.has(pit_id) and screen.progression_panel.visible and screen.progression_panel.selected==pit["card"] and screen.campaign_prompt.messages.has(5101),"The Pit reward must show its own card and original explanation")
	commands.clear()
	screen.progression_panel.close_button.pressed.emit()
	check(commands==[{"type":"campaign_dismiss_level_card"}],"Closing the Pit card must forward the original dismissal")
	screen.free()
	await process_frame
	print("Source opening prompts and original animation roles: %d failures"%failures)
	quit(1 if failures else 0)
