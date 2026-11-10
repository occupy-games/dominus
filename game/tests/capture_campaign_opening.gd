extends SceneTree

const Content = preload("res://infrastructure/campaign_opening_content.gd")
const World = preload("res://simulation/world.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
var preview := SubViewport.new()


func _initialize() -> void:
	create_timer(45).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func capture(name: String) -> void:
	for frame in range(12): await process_frame
	preview.get_texture().get_image().save_png("res://../build/screenshots/"+name+".png")
	print("Captured ",name)


func run() -> void:
	preview.size=Vector2i(1200,800)
	preview.own_world_3d=true
	preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(preview)
	var definition := Content.definition()
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
	var assets := preload("res://infrastructure/game_content.gd").new()
	var catalog := preload("res://infrastructure/asset_catalog.gd").new()
	catalog.read_models()
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.follower_assets=assets.follower_assets(true)
	for role: String in ["drowning","hugging_give","hugging_take","worshipping"]:
		if not screen.follower_assets["clips"].has(role): push_error("Missing source opening clip: "+role); quit(1); return
	screen.sheep_assets=assets.animated_assets("sheep")
	screen.scenery_assets=assets.scenery_assets()
	screen.terrain_palette=assets.terrain_palette()
	screen.resolve_model=catalog.model_data
	screen.resolve_building=catalog.building_data
	screen.resolve_unit=catalog.unit_data
	screen.world_view.bathymetry=definition["bathymetry"]
	screen.inspect_action=world.inspect
	screen.locate_edge=world.find_edge
	screen.intent.connect(func(command: Dictionary) -> void:
		var emitted := world.step([command])
		screen.apply_snapshot(world.snapshot(),emitted))
	preview.add_child(screen)
	screen.apply_snapshot(world.snapshot())
	screen.world_view.zoom=16
	screen.world_view.update_camera()
	await capture("homeworld6-original-rescue")
	var events := world.step([{"type":"sculpt_drag","x":166,"z":58,"nx":0,"nz":-1,"layer":1,"distance":5,"dx":-3,"dz":-5,"radius":1}])
	screen.apply_snapshot(world.snapshot(),events)
	await capture("homeworld6-original-embrace")
	screen.world_view.zoom=4
	screen.world_view.focus=screen.world_view.world_position(163,53)
	screen.world_view.update_camera()
	await capture("homeworld6-original-embrace-detail")
	screen.world_view.zoom=16
	screen.world_view.update_camera()
	for tick in range(60): world.step()
	screen.apply_snapshot(world.snapshot())
	await capture("homeworld6-original-worship")
	screen.campaign_prompt.messages[4].pressed.emit()
	for tick in range(200): world.step()
	screen.apply_snapshot(world.snapshot())
	screen.world_view.focus=screen.world_view.world_position(165,64)
	screen.world_view.update_camera()
	await capture("homeworld6-original-first-obstacle")
	var player := preload("res://simulation/campaign_opening_player.gd").new()
	for tick in range(5000):
		if world._state["opening"]["phase"]=="promised_land": break
		world.step(player.commands(world))
	if world._state["opening"]["phase"]!="promised_land" or not world._state["opening"]["error"].is_empty():
		push_error("The source rock capture must follow the playable trail")
		quit(1)
		return
	for tick in range(70): world.step()
	screen.apply_snapshot(world.snapshot())
	screen.world_view.zoom=12
	screen.world_view.focus=screen.world_view.world_position(161,123)
	screen.world_view.update_camera()
	await capture("homeworld6-original-authored-rock")
	screen.free()
	print("Authored source opening presentation captured")
	quit()
