extends Control
## Composes simulation sessions, infrastructure and presentation screens.

const Menu = preload("res://presentation/menu/main_menu.gd")
const CampaignMenu = preload("res://presentation/menu/campaign_menu.gd")
const CampaignContent = preload("res://infrastructure/campaign_content.gd")
const AdventureContent = preload("res://infrastructure/adventure_content.gd")
const Library = preload("res://presentation/library/asset_library.gd")
const Catalog = preload("res://infrastructure/asset_catalog.gd")
const Style = preload("res://presentation/ui/style.gd")
const Session = preload("res://application/game_session.gd")
const GameScreen = preload("res://presentation/world/game_screen.gd")
const Content = preload("res://infrastructure/game_content.gd")
const Store = preload("res://infrastructure/world_store.gd")
const ExampleLayout = preload("res://simulation/example_layout.gd")
const ExampleWorld = preload("res://presentation/world/example_world.gd")
var settings := preload("res://infrastructure/settings_store.gd").new()
var constants := preload("res://infrastructure/live_constants.gd").new()
var constants_status := ""
var lost_focus_pause := false
var previous_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var screen: Control
var catalog := Catalog.new()
var session: Node
var menu_message := ""
var example_layout: Dictionary = {}
var example_camera: Dictionary = {}
var home_session: Node
var adventure_progress: Dictionary = {}
var adventure_status := ""
var adventure_profile: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.make_theme()
	settings.read()
	adventure_profile=AdventureContent.read_profile()
	adventure_progress=adventure_profile["missions"].duplicate(true)
	if not FileAccess.file_exists(settings.path): settings.write()
	var campaign := preload("res://infrastructure/campaign_content.gd").homeworld()
	if not campaign.is_empty():
		constants.initialize(campaign["progression_rules"])
		var created := constants.ensure_file()
		if not created.get("ok",false): constants_status=created.get("message","")
	apply_preferences(true)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Control: scale_live_text.call_deferred(weakref(node)))
	show_menu()
	if "--library" in OS.get_cmdline_user_args():
		show_library()
	if "--play" in OS.get_cmdline_user_args():
		show_campaign()
	if "--sandbox" in OS.get_cmdline_user_args(): show_game(true)
	if "--example" in OS.get_cmdline_user_args():
		show_example()
	if "--campaign" in OS.get_cmdline_user_args(): show_campaign()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--campaign="): show_campaign(argument.trim_prefix("--campaign=").to_lower())
	if "--adventures" in OS.get_cmdline_user_args(): show_adventures()


func replace_screen(next: Control) -> void:
	if is_instance_valid(screen):
		if screen is ExampleWorld:
			example_camera = {"focus": screen.navigation.focus, "span": screen.navigation.span,
				"yaw": screen.navigation.yaw, "elevation": screen.navigation.elevation,
				"height": screen.navigation.pivot_height}
		remove_child(screen)
		screen.queue_free()
	screen = next
	add_child(screen)


func show_menu() -> void:
	leave_adventure()
	if is_instance_valid(session):
		session.set_process(false)
	var menu := Menu.new()
	menu.resume_enabled = is_instance_valid(session) or Store.new().exists()
	menu.status_message = menu_message
	menu.new_world_requested.connect(func() -> void: show_game(true))
	menu.campaign_requested.connect(show_campaigns)
	menu.adventures_requested.connect(show_adventures)
	menu.start_requested.connect(show_campaign)
	menu.continue_requested.connect(func() -> void: show_game(false))
	menu.example_requested.connect(show_example)
	menu.library_requested.connect(show_library)
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	replace_screen(menu)


func show_library(from_world: bool = false, from_example: bool = false) -> void:
	if is_instance_valid(session):
		session.set_process(false)
	if catalog.entries.is_empty():
		catalog.read_catalog()
	var library := Library.new()
	library.catalog = catalog
	library.back_label = "←  Example world" if from_example else ("←  World" if from_world else "←  Main menu")
	library.back_requested.connect(func() -> void:
		if from_example: show_example()
		elif from_world: show_game(false)
		else: show_menu())
	library.place_model_requested.connect(place_source_model)
	replace_screen(library)


func show_example() -> void:
	if is_instance_valid(session): session.set_process(false)
	if catalog.models.is_empty(): catalog.read_models()
	if example_layout.is_empty(): example_layout = ExampleLayout.new().build(catalog.models)
	var view := ExampleWorld.new()
	view.navigation.preferences=settings.values.duplicate(true)
	view.layout = example_layout.duplicate(true)
	view.resolve_model = catalog.model_data
	view.resolve_details = catalog.inspection_data
	view.resolve_building = catalog.building_data
	view.back_requested.connect(show_menu)
	view.library_requested.connect(func(id: String) -> void:
		show_library(false, true)
		if id.begins_with("object:"): screen.show_object(id.trim_prefix("object:"))
		else: screen.show_model(id))
	replace_screen(view)
	if not example_camera.is_empty():
		view.navigation.yaw = example_camera["yaw"]
		view.navigation.elevation = example_camera["elevation"]
		view.navigation.focus_on(example_camera["focus"], example_camera["span"], example_camera["height"])


func show_campaigns() -> void:
	if is_instance_valid(session): session.set_process(false)
	var menu := CampaignMenu.new()
	menu.maps = CampaignContent.maps()
	menu.back_requested.connect(show_menu)
	menu.start_requested.connect(show_campaign)
	replace_screen(menu)


func show_campaign(map_id: String = "homeworld") -> void:
	var definition := CampaignContent.map_definition(map_id)
	if definition.is_empty():
		menu_message = "This original map is unavailable."
		show_menu()
		return
	show_game(true, definition)


func record_adventure() -> void:
	if not is_instance_valid(session): return
	var state: Dictionary = session.presentation_snapshot()
	if not state.has("voyage") or state["voyage"]["phase"]!="won": return
	var random := RandomNumberGenerator.new()
	random.seed=int(state.get("world_seed",2026))
	var era := 1
	var needed := {}
	if is_instance_valid(home_session):
		var home: Dictionary = home_session.presentation_snapshot()
		era=int(home.get("progression",{}).get("age",1))
		needed=preload("res://simulation/voyage_rewards.gd").needed(home,AdventureContent.reward_rules())
	var updated := preload("res://simulation/voyage_rewards.gd").record(adventure_profile,state,AdventureContent.reward_rules(),random,era,needed)
	if updated==adventure_profile: return
	# Persist entitlements first. A failed Homeworld save can safely retry the
	# delta, because each Homeworld persists its redeemed cumulative quantities.
	if not AdventureContent.write_progress(updated):
		adventure_status="Could not save voyage rewards. Return again to retry."
		return
	adventure_profile=updated
	adventure_progress=updated["missions"].duplicate(true)
	if is_instance_valid(home_session): sync_adventure_rewards(home_session)
	if screen is GameScreen and is_instance_valid(screen.voyage_hud): screen.voyage_hud.show_rewards(updated["last_awards"])


func sync_adventure_rewards(target: Node) -> void:
	var result: Dictionary = target.receive_voyage_rewards(adventure_profile,AdventureContent.reward_rules())
	if result.get("count",0)>0:
		var saved: Dictionary = target.save_game()
		if not saved.get("ok",false): adventure_status="Stickers received; Homeworld could not be saved: "+saved.get("message","")


func leave_adventure() -> void:
	if not is_instance_valid(session): return
	session.finish_worker()
	if not session.presentation_snapshot().has("voyage"): return
	record_adventure()
	session.set_process(false)
	session.free()
	session=home_session
	home_session=null


func show_adventures() -> void:
	leave_adventure()
	if is_instance_valid(session): session.set_process(false)
	var menu := preload("res://presentation/menu/adventures_menu.gd").new()
	menu.missions=AdventureContent.missions()
	menu.progress=adventure_progress.duplicate(true)
	menu.status_message=adventure_status
	menu.back_requested.connect(show_menu)
	menu.start_requested.connect(show_adventure)
	replace_screen(menu)


func show_adventure(id: String, difficulty: int = 0) -> void:
	var definition := AdventureContent.definition(id,difficulty)
	if definition.is_empty(): return
	if is_instance_valid(session):
		session.finish_worker()
		record_adventure()
		if not session.presentation_snapshot().has("voyage"):
			session.set_process(false)
			home_session=session
			session=null
	show_game(true,definition)
	session.store.database_path=preload("res://infrastructure/save_paths.gd").directory().path_join("voyage.sqlite")


func show_game(fresh: bool = true, campaign: Dictionary = {}) -> void:
	if is_instance_valid(session): session.finish_worker()
	if catalog.models.is_empty():
		catalog.read_models()
	if not is_instance_valid(session):
		session = Session.new()
		session.threaded=true
		session.model_definitions = catalog.model_definitions()
		add_child(session)
		session.changed.connect(on_world_changed)
		if not fresh:
			var loaded: Dictionary = session.load_game()
			if not loaded.get("ok", false):
				menu_message = loaded.get("message", "Could not load the saved world.")
				session.free()
				session = null
				show_menu()
				return
	if fresh:
		if campaign.is_empty(): session.new_world()
		else:
			session.new_campaign(campaign)
			if not campaign.has("voyage"):
				var parsed := constants.read()
				var applied: Dictionary = session.apply_constants(parsed["changes"]) if parsed.get("ok",false) else parsed
				constants_status=applied.get("message","")
	if not session.presentation_snapshot().has("voyage"): sync_adventure_rewards(session)
	var view := GameScreen.new()
	view.settings_definitions=settings.definitions.duplicate(true)
	view.settings_values=settings.values.duplicate(true)
	view.save_directory=ProjectSettings.globalize_path(preload("res://infrastructure/save_paths.gd").directory())
	DirAccess.make_dir_recursive_absolute(view.save_directory)
	view.save_path=ProjectSettings.globalize_path(session.store.database_path)
	view.settings_status=settings.error if not settings.error.is_empty() else constants_status
	view.campaign_mode = session.presentation_snapshot().has("campaign")
	var campaign_definition := CampaignContent.for_state(session.presentation_snapshot()) if view.campaign_mode else {}
	if session.presentation_snapshot().has("voyage"):
		campaign_definition=AdventureContent.for_state(session.presentation_snapshot())
		view.voyage_definition=session.presentation_snapshot()["voyage"]["definition"].duplicate(true)
		view.power_assets=AdventureContent.power_assets(view.voyage_definition)
		view.voyage_return_requested.connect(show_adventures)
		view.voyage_retry_requested.connect(func() -> void: show_adventure(view.voyage_definition["id"],int(view.voyage_definition.get("difficulty",0))))
		view.voyage_next_requested.connect(func() -> void:
			var next_id: String = view.voyage_definition.get("next_id","")
			if not next_id.is_empty(): show_adventure(next_id,int(view.voyage_definition.get("difficulty",0))))
	if view.campaign_mode: view.campaign_cards = preload("res://infrastructure/campaign_content.gd").card_assets()
	if view.campaign_mode: view.hud_textures = preload("res://infrastructure/ui_content.gd").textures()
	if not campaign_definition.is_empty():
		if view.voyage_definition.is_empty(): view.power_assets = preload("res://infrastructure/progression_content.gd").power_assets(campaign_definition)
		view.world_view.bathymetry = campaign_definition["bathymetry"]
	view.landscape_texture = Content.new().landscape_texture()
	view.follower_assets = Content.new().follower_assets()
	if not view.voyage_definition.is_empty():
		view.world_view.enemy_assets["champion"]=catalog.actor_data("follower.group.bin:1675fbb3",{"idle":"champion01_stand_1","walking":"champion01_walk_1","attacking":"champion01_attack_ground_1_give","resting":"tired_sit_1_idle_1"})
		view.world_view.enemy_assets["wolf1"]=catalog.actor_data("wolf.group.bin:7ca0371d",{"idle":"default_stand_1","walking":"default_run_1","resting":"default_stand_1"})
	view.audio_assets = Content.new().audio_assets()
	view.sheep_assets = Content.new().animated_assets("sheep")
	view.scenery_assets = Content.new().scenery_assets()
	view.terrain_palette = Content.new().terrain_palette()
	view.resolve_model = catalog.model_data
	view.resolve_building = catalog.building_data
	view.resolve_unit = catalog.unit_data
	view.world_view.resolve_worker = catalog.worker_data
	view.inspect_action = session.inspect
	view.inspect_building = session.inspect_building
	view.building_info_labels = preload("res://infrastructure/building_info.gd").content().get("labels",{})
	view.resolve_building_info = preload("res://infrastructure/building_info.gd").record
	view.locate_edge = session.find_edge
	view.intent.connect(session.submit)
	view.menu_requested.connect(show_menu)
	view.models_requested.connect(func() -> void: show_library(true))
	view.save_requested.connect(func() -> void:
		var result: Dictionary = session.save_game()
		view.toast("World saved." if result.get("ok", false) else result.get("message", "Could not save.")))
	view.setting_changed.connect(change_setting)
	view.reset_settings_requested.connect(reset_settings)
	view.reload_constants_requested.connect(reload_constants)
	view.open_table_requested.connect(func(table: String) -> void:
		var result := constants.open_editor(table)
		view.menu_status(result.get("message","")))
	view.open_constants_requested.connect(func() -> void:
		var result := constants.open_editor()
		view.menu_status(result.get("message","")))
	view.save_path_requested.connect(func(path: String) -> void:
		var result: Dictionary = session.save_game(path)
		view.menu_status("Saved: "+path if result.get("ok",false) else result.get("message","Could not save."))
		if result.get("ok",false): view.save_path=path)
	view.load_path_requested.connect(func(path: String) -> void:
		load_world_path(path))
	view.pause_requested.connect(func() -> void:
		session.paused = not session.paused
		view.update_playback(session.paused, session.speed))
	view.speed_requested.connect(func() -> void:
		session.speed = 3.0 if session.speed == 1.0 else 1.0
		view.update_playback(session.paused, session.speed))
	replace_screen(view)
	apply_preferences()
	view.apply_snapshot(session.presentation_snapshot())
	view.update_playback(session.paused, session.speed)
	session.set_process(true)


func load_world_path(path: String) -> void:
	# Validate the incoming save in a separate session. Loading an island must
	# preserve the current Homeworld just like selecting it in Adventures.
	if is_instance_valid(session): session.finish_worker()
	var candidate := Session.new()
	candidate.threaded=true
	candidate.model_definitions=catalog.model_definitions()
	var result: Dictionary = candidate.load_game(path)
	if not result.get("ok",false):
		candidate.free()
		if screen is GameScreen: screen.menu_status(result.get("message","Could not load."))
		return
	var incoming_voyage: bool = candidate.presentation_snapshot().has("voyage")
	if is_instance_valid(session):
		var outgoing_voyage: bool = session.presentation_snapshot().has("voyage")
		if outgoing_voyage: record_adventure()
		if incoming_voyage and not outgoing_voyage:
			session.set_process(false)
			home_session=session
		else: session.free()
	if not incoming_voyage and is_instance_valid(home_session):
		home_session.free()
		home_session=null
	session=candidate
	add_child(session)
	session.changed.connect(on_world_changed)
	show_game(false)


func place_source_model(id: String) -> void:
	var model: Dictionary = catalog.model_data(id)
	if model.is_empty() or model["material_status"] != "source_texture":
		return
	show_game(not is_instance_valid(session))
	session.paused = false
	screen.update_playback(false, session.speed)
	screen.arm_model_placement(model["descriptor"])


func on_world_changed(snapshot: Dictionary, events: Array) -> void:
	if screen is GameScreen:
		screen.apply_snapshot(snapshot, events)
	if snapshot.has("voyage"):
		for event: Dictionary in events:
			if event["type"]=="victory": record_adventure()


func change_setting(key: String,value: Variant) -> void:
	var result := settings.change(key,value)
	apply_preferences(key=="display.fullscreen")
	if screen is GameScreen: screen.menu_status(result.get("message",""))


func reset_settings(prefix: String) -> void:
	var result := settings.reset(prefix)
	apply_preferences(prefix in ["","display","display.fullscreen"])
	if screen is GameScreen: screen.menu_status(result.get("message",""))


func reload_constants() -> void:
	var result := constants.read()
	if result.get("ok",false): result=session.apply_constants(result["changes"])
	constants_status=result.get("message","")
	if screen is GameScreen: screen.menu_status(constants_status)


func apply_preferences(apply_window_mode: bool = false) -> void:
	if settings.values.is_empty(): return
	var values: Dictionary = settings.values
	if is_instance_valid(session): session.speed=float(values["gameplay.speed"])
	Engine.max_fps=int(values["display.max_fps"])
	get_viewport().msaa_3d=int(values["display.msaa"])
	if DisplayServer.get_name()!="headless":
		if apply_window_mode:
			var mode := DisplayServer.window_get_mode()
			var full: bool=mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			if values["display.fullscreen"] and not full:
				previous_window_mode=mode
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			elif not values["display.fullscreen"] and full:
				DisplayServer.window_set_mode(previous_window_mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["display.vsync"] else DisplayServer.VSYNC_DISABLED)
	if theme!=null: theme.default_font_size=roundi(18*float(values["interface.text_scale"]))
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec",values["interface.tooltip_delay"])
	scale_text(self,true)
	if screen is GameScreen:
		screen.apply_preferences(values)
		screen.update_playback(session.paused,session.speed)


func _notification(what: int) -> void:
	if not is_instance_valid(session) or not settings.values.get("gameplay.pause_on_focus_loss",false): return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		lost_focus_pause=not session.paused
		if lost_focus_pause: session.paused=true
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN and lost_focus_pause:
		session.paused=false
		lost_focus_pause=false
	if screen is GameScreen: screen.update_playback(session.paused,session.speed)


func scale_live_text(reference: WeakRef) -> void:
	var node: Variant = reference.get_ref()
	if is_instance_valid(node): scale_text(node)


func scale_text(node: Node,recursive: bool = false) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	if node is Control:
		if not node.has_meta("base_text_size"): node.set_meta("base_text_size",node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size",roundi(int(node.get_meta("base_text_size"))*float(settings.values.get("interface.text_scale",1))))
	if recursive:
		for child: Node in node.get_children(): scale_text(child,true)
