extends SceneTree

const Screen = preload("res://presentation/world/game_screen.gd")
const World = preload("res://simulation/world.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func visible_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Control and not node.is_visible_in_tree(): return result
	if node is Label or node is Button: result.append(node.text)
	for child: Node in node.get_children(): result.append_array(visible_text(child))
	return result


func run() -> void:
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	world.initialize({},rng)
	var state := world.snapshot()
	state["campaign"] = {"cards":[]}
	var rules: Dictionary = preload("res://infrastructure/campaign_content.gd").homeworld()["progression_rules"]
	state["progression"]={"rules":rules,"discovered":[],"completed":[],"inventory":{"Card_Textile_1":1},"revision":0,"powers":[],"chests":[],"shrines":[],"rock_revision":0,"rock_taps":{},"totem":{},"totem_capacity":4}
	state["currency_metrics"]={"followers":{"amount":683,"next":800,"progress":33.0/150},"wheat":{"amount":0,"next":2,"progress":0},"ore":{"amount":0,"next":2,"progress":0}}
	state["tribe_happiness"]={"player":0.2,"astari":0.3}
	var screen := Screen.new()
	screen.campaign_mode = true
	screen.hud_textures = preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards = preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=func(_command: Dictionary) -> Dictionary: return {"ok":true}
	root.add_child(screen)
	screen.apply_snapshot(state)
	await process_frame
	screen.toggle_menu()
	for viewport_size: Vector2i in [Vector2i(1000,680),Vector2i(1600,1000),Vector2i(1200,800)]:
		root.size = viewport_size
		await process_frame
		check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(screen.pause_panel.get_global_rect()),"Settings panel must remain entirely inside the viewport after resizing")
	screen.toggle_menu()
	check(visible_text(screen) == ["683","800","0","2","0","2",str(state["belief"]),"0"],"Campaign HUD must show followers, wheat, ore, belief and gems without prototype instructions")
	check(not screen.goal_panel.is_visible_in_tree() and not screen.layer_choice.is_visible_in_tree(),"Development controls must stay outside the campaign HUD")
	for texture: Variant in screen.hud_textures.values():
		check(texture is AtlasTexture and texture.atlas.resource_path.begins_with("res://assets/"),"HUD sprites must use recovered source atlases")
	for id: String in screen.original_hud.card_nodes:
		check(not screen.original_hud.card_nodes[id].visible,"Locked cards must stay hidden")
	while state["followers"].size() < 10: state["followers"].append(state["followers"][0].duplicate(true))
	state["progression"]["discovered"].append("Card_MaxRank_2")
	screen.original_hud.apply_snapshot(state)
	check(screen.original_hud.card_nodes["Card_MaxRank_2"].visible,"Tents card must appear at the source population threshold")
	var claimed: Array = []
	screen.intent.connect(func(command: Dictionary) -> void: claimed.append(command))
	screen.original_hud.card_nodes["Card_MaxRank_2"].pressed.emit()
	check(screen.progression_panel.visible and screen.progression_panel.selected=="Card_MaxRank_2","Source card button must open the card and its actual requirements")
	check(screen.progression_panel.confirm_button==null,"Resource advances must use assignment on their portrait rather than a separate completion button")
	screen.progression_panel.detail_card._drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Textile_1"})
	check(claimed == [{"type":"research_card","card":"Card_MaxRank_2","sticker":"Sticker_Textile_1"}],"Dropping a source resource on its card must submit a simulation assignment")
	check(preload("res://presentation/ui/style.gd").source_font().get_font_name()=="Roboto Condensed","The shared UI and world-label font must be Roboto Condensed")
	var hud: Control = screen.original_hud
	check(hud.bar.get_global_rect().encloses(hud.population.get_global_rect()) and hud.belief_bar.get_global_rect().encloses(hud.belief.get_global_rect()), "Counter text boxes must fit inside the pill interiors")
	var follower_gap: float = hud.bar.get_global_rect().position.x - hud.follower_icon.get_global_rect().end.x
	var belief_gap: float = hud.belief_bar.get_global_rect().position.x - hud.belief_icon.get_global_rect().end.x
	check(is_equal_approx(follower_gap, belief_gap), "Follower and belief icons must have the same gap before their pills")
	check(hud.follower_icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and is_equal_approx(hud.follower_icon.size.aspect(), 40.0 / 33.0), "Follower pawn must retain its authored aspect ratio")
	for button: Control in [hud.collection_button, hud.settings_button, hud.sculpt_button,hud.gems_button]:
		check(button.size==Vector2(56,56),"All four corner circles must use the smaller matched size")
		check(is_equal_approx(button.self_modulate.a,0.65),"All four circle backgrounds must remain semi-transparent")
	check(is_equal_approx(hud.happiness_gauge.modulate.a,0.65),"The happiness gauge and tribe markers must remain semi-transparent")
	check(hud.happiness_gauge.player.position.y>hud.happiness_gauge.astari.position.y,"The gauge must independently position player and Astari happiness")
	check(is_equal_approx(hud.bar.value,33.0/150),"Population fill must show progress since the previous milestone")
	check(hud.bar.size.x==hud.belief_bar.size.x*2 and hud.bar.size.x==hud.gems_bar.size.x*2,"Belief and diamond pills must be half the resource slider width")
	for pair: Array in [[hud.belief_icon,hud.belief_bar,hud.sculpt_button],[hud.gems_icon,hud.gems_bar,hud.gems_button]]:
		var group_center: float = (pair[0].get_global_rect().position.x+pair[1].get_global_rect().end.x)/2
		check(is_equal_approx(group_center,pair[2].get_global_rect().get_center().x),"Each icon and short pill must be centered above its circle")
	for viewport_size: Vector2i in [Vector2i(640,480),Vector2i(1000,680),Vector2i(1600,1000)]:
		root.size=viewport_size
		await process_frame
		for item: Control in [hud.collection_button,hud.settings_button,hud.sculpt_button,hud.gems_button,hud.gems_bar,hud.happiness_gauge]:
			check(root.get_visible_rect().encloses(item.get_global_rect()),"Corner HUD must stay within resized viewports")
	check(Rect2(Vector2(6,6),Vector2(44,44)).encloses(hud.sculpt_hand.get_rect()), "The hand must sit fully inside the circle's rim")
	for id: String in ["Card_MaxRank_2", "Card_DoubleClick", "Card_AbodeType_2"]:
		var source: Dictionary = screen.campaign_cards[id]
		var portrait: Texture2D = source["resolve_texture"].call(source,true)
		check(portrait is AtlasTexture and portrait.atlas.resource_path.begins_with("res://assets/extracted/Scaleform/") and portrait.region == Rect2(0,61,256,390), "Opening cards must use the exact 2.4 portrait illustration crop")
		check(not str(source["description"]).is_empty() and str(source["text_source"]).begins_with("received/godussteamrel/balance.datz:"), "Card explanations must come from the recovered 2.4 localization")
	var original_belief: int = state["belief"]
	state["belief"] = 123456789012
	hud.apply_snapshot(state)
	check(font_width(hud.belief) <= hud.belief.size.x, "Large belief amounts must fit without spilling out of the pill")
	hud.belief.add_theme_font_size_override("font_size", 40)
	check(font_width(hud.belief) <= hud.belief.size.x and hud.belief.get_theme_font_size("font_size") <= 16, "Text-size preference changes must preserve counter fit while paused")
	state["belief"] = original_belief
	var home := {"id":100,"x":20,"z":20,"span":2,"progress":0,"build_ticks":20,"stored":0,"stalled":false}
	state["homes"] = [home]
	screen.world_view.apply_snapshot(state)
	check(screen.world_view.home_badges[100]["source_sprite"] == "GFX_Pawn_Worker.png", "Building activity must show the original blue hammer pawn")
	check(screen.world_view.badge_layer.z_index < screen.progression_panel.z_index, "World house sprites must render behind card and settings popups")
	home["progress"] = 20
	home["stored"] = 5
	screen.world_view.apply_snapshot(state)
	check(screen.world_view.home_badges[100]["source_sprite"] == "GFX_IWIcon_Belief.png", "Collectable belief must show the original belief badge")
	state["homes"] = []
	screen.world_view.apply_snapshot(state)
	check(screen.world_view.home_badges.is_empty(), "Removed houses must not leave floating badges")
	check(screen.progression_panel.tabs.get_tab_count()==2,"Cards must have independent advances and quantified resources galleries")
	screen.progression_panel.open_card("Card_Textile_1")
	check(screen.progression_panel.tabs.current_tab==1 and screen.progression_panel.confirm_button==null,"A component must open its quantity and usage details in Resources")
	screen.original_hud.sculpt_requested.emit()
	check(screen.powers_panel.visible and not screen.progression_panel.visible and screen.powers_panel.mode=="powers","Bottom-left must show a separate explanatory powers gallery")
	screen.powers_panel.open_card("Card_GodPower_TotemActivate")
	check("Capacity: 4" in visible_text(screen.powers_panel),"Power details must explain its capacity and cost")
	screen.powers_panel.open_card("Card_GodPower_Beautify")
	check(screen.powers_panel.selected=="Card_GodPower_Beautify","Power gallery must support each selection")
	screen.powers_panel.hide()
	# Presentation must remove a used chest immediately and never respawn it.
	var chest_node := Node3D.new()
	screen.world_view.add_child(chest_node)
	screen.world_view.progression_nodes["chest:used"]=chest_node
	state["progression"]["chests"]=[{"id":"used","opened":true}]
	screen.world_view.apply_snapshot(state)
	check(not screen.world_view.progression_nodes.has("chest:used"),"A used chest must disappear from presentation")
	screen.world_view.update_progression()
	check(not screen.world_view.progression_nodes.has("chest:used"),"Used chests must remain absent on later snapshots")
	screen.progression_panel.visible=false
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_3
	screen._unhandled_key_input(key)
	check(screen.tool == "sculpt","Campaign must not expose prototype sheep-spawning shortcuts")
	var span: float = screen.world_view.zoom
	key.physical_keycode = KEY_PLUS
	screen._unhandled_key_input(key)
	check(screen.world_view.zoom < span,"Zoom must remain available without a prototype HUD bar")
	screen.queue_free()
	await process_frame
	print("Original campaign HUD: %d failures" % failures)
	quit(1 if failures else 0)


func font_width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
