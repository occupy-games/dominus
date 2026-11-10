extends SceneTree
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func sticker_button(node: Node,id: String) -> TextureButton:
	if node.get_script()==preload("res://presentation/ui/source_card.gd") and node.source.get("canonical_id")==id: return node
	for child: Node in node.get_children():
		var found := sticker_button(child,id)
		if found!=null: return found
	return null


func run() -> void:
	var adventures := preload("res://infrastructure/adventure_content.gd")
	adventures.progress_path="res://../build/test-economy-interface-profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(adventures.progress_path))
	var app: Variant = load("res://application/front_end.tscn").instantiate()
	root.add_child(app)
	app.show_campaign()
	app.session.set_process(false)
	app.session.finish_worker()
	app.session.threaded=false
	app.session.store.database_path="res://../build/test-economy-interface.sqlite"
	app.session.changed.disconnect(app.on_world_changed)
	app.session.new_campaign(preload("res://tests/fixtures/campaign_economy.gd").definition())
	for point: Vector2i in [Vector2i(12,12),Vector2i(19,12)]: app.session.submit({"type":"home","x":point.x,"z":point.y,"rank":1})
	for batch in range(300): app.session.advance_elapsed(0.5)
	app.session.receive_voyage_rewards({"earned":{"Sticker_Rare_Settlement":1}},adventures.reward_rules())
	var campaign := preload("res://infrastructure/campaign_content.gd")
	campaign.definition["width"]=64
	campaign.definition["bathymetry"]=PackedByteArray()
	campaign.definition["bathymetry"].resize(64*64)
	campaign.definition["bathymetry"].fill(23)
	app.session.changed.connect(app.on_world_changed)
	app.show_game(false)
	app.session.set_process(false)
	var screen: Variant = app.screen
	screen.progression_panel.open_card("Card_Settlement_Farming")
	var sticker: TextureButton=screen.progression_panel.resource_slots.get("Sticker_Rare_Settlement")
	check(sticker!=null,"The detail gallery must expose the owned matching research sticker")
	if sticker==null: app.free(); quit(1); return
	screen.progression_panel.detail_card._drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Rare_Settlement"})
	app.session.advance_elapsed(0.1)
	check("Card_Settlement_Farming" in app.session.presentation_snapshot()["progression"]["completed"],"Clicking a matching sticker must complete the real simulation advance")
	check(app.session.presentation_snapshot()["progression"]["inventory"]["Sticker_Rare_Settlement"]==0,"The UI must consume the actual earned sticker exactly once")
	screen.progression_panel.hide()
	screen.powers_panel.open_card("Card_GodPower_Settlement_2")
	var cast: Button
	for child: Node in screen.powers_panel.detail.find_children("*","Button",true,false):
		if child.text=="Farming Settlement": cast=child
	check(cast!=null and not cast.disabled,"Research must enable the original settlement power in the powers gallery")
	if cast==null: app.free(); quit(1); return
	cast.pressed.emit()
	check(screen.tool=="GodPower_PlaceSettlement_2" and not screen.powers_panel.visible,"The original power button must arm world placement and close its popup")
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	app.session.advance_elapsed(0.1)
	check(app.session.presentation_snapshot()["progression"]["settlements"].size()==1,"A world click must create the authoritative settlement")
	check(screen.tool=="sculpt","An accepted single-use settlement placement must return to normal world controls")
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	app.session.advance_elapsed(0.1)
	var fields := 0
	for home: Dictionary in app.session.presentation_snapshot()["homes"]:
		if home.get("kind","")=="farm": fields+=1
	check(fields==1,"Clicking the new settlement must send a real farmer to construct a field")
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("Research gallery and settlement controls: %d failures"%failures)
	quit(0 if failures==0 else 1)
