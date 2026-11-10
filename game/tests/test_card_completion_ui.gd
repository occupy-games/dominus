extends SceneTree

const Session = preload("res://application/game_session.gd")
const Screen = preload("res://presentation/world/game_screen.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func button(parent: Node,caption: String) -> Button:
	for child: Node in parent.find_children("*","Button",true,false):
		if child.text==caption: return child
	return null


func sticker(parent: Node,id: String) -> TextureButton:
	for child: Node in parent.get_children():
		if child.get_script()==preload("res://presentation/ui/source_card.gd") and child.source.get("canonical_id")==id: return child
		var found := sticker(child,id)
		if found!=null: return found
	return null


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	session.new_campaign(preload("res://tests/fixtures/campaign_economy.gd").definition())
	session.submit({"type":"home","x":12,"z":12,"rank":1})
	for batch in range(300): session.advance_elapsed(0.5)
	var rewards := {"earned":{"Sticker_Textile_1":1,"Sticker_ReligiousObject_3":2,"Sticker_Rare_Settlement":1}}
	session.receive_voyage_rewards(rewards,preload("res://infrastructure/adventure_content.gd").reward_rules())
	var screen := Screen.new()
	screen.campaign_mode=true
	screen.hud_textures=preload("res://infrastructure/ui_content.gd").textures()
	screen.campaign_cards=preload("res://infrastructure/campaign_content.gd").card_assets()
	screen.inspect_action=session.inspect
	screen.intent.connect(session.submit)
	root.add_child(screen)
	session.changed.connect(screen.apply_snapshot)
	screen.apply_snapshot(session.presentation_snapshot())
	# The portrait's legacy alias must spend a real earned resource and unlock
	# both the simulation rule and the ordinary sculpt command.
	for id: String in ["Card_MaxRank_2","Card_DoubleClick"]:
		screen.progression_panel.open_card(id)
		check(screen.progression_panel.confirm_button==null,"Resource cards must complete through assignment to %s"%id)
		for resource: String in (["Sticker_Textile_1"] if id=="Card_MaxRank_2" else ["Sticker_ReligiousObject_3","Sticker_ReligiousObject_3"]):
			screen.progression_panel.detail_card._drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":resource})
			session.advance_elapsed(0.1)
		check(id in session.presentation_snapshot()["progression"]["completed"],"The gallery must complete %s in authoritative progression"%id)
	var state := session.presentation_snapshot()
	check(state["progression"]["inventory"]["Sticker_Textile_1"]==0 and state["progression"]["inventory"]["Sticker_ReligiousObject_3"]==0,"Completing resource recipes must debit their real sticker aliases")
	check(session.world.house_spec()["rank"]==2 and session.inspect({"type":"dig","x":30,"z":30})["ok"],"Completed cards must enable the larger abode and actual digging")
	var before := session.world.export_state()
	check(not session.inspect({"type":"claim_card","card":"Card_DoubleClick"})["ok"],"A completed card cannot be claimed twice")
	check(session.world.export_state()==before,"Repeated completion queries must not spend another resource")
	# Follow the locked power's link into its typed advance while remaining in
	# the powers view. Previously that view returned before rendering research.
	screen.progression_panel.hide()
	screen.powers_panel.open_card("Card_GodPower_Settlement_2")
	var unlock := button(screen.powers_panel.detail,"Unlock through "+str(screen.campaign_cards["Card_Settlement_Farming"]["title"]))
	check(unlock!=null,"A locked power must link to its actual source advance")
	if unlock!=null: unlock.pressed.emit()
	check(screen.powers_panel.selected=="Card_Settlement_Farming","The power link must open the original settlement research card")
	var resource: TextureButton=screen.powers_panel.resource_slots.get("Sticker_Rare_Settlement")
	check(resource!=null,"Matching earned resources must be usable from the powers view")
	if resource!=null: screen.powers_panel.detail_card._drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Rare_Settlement"})
	session.advance_elapsed(0.1)
	state=session.presentation_snapshot()
	check("Card_Settlement_Farming" in state["progression"]["completed"] and "GodPower_PlaceSettlement_2" in state["progression"]["powers"],"Typed resources must complete the advance and unlock its real power")
	check(state["progression"]["inventory"]["Sticker_Rare_Settlement"]==0,"Research must consume the earned voyage sticker once")
	var codec := preload("res://infrastructure/world_store.gd").new()
	var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers(session.world.export_state()))))
	check(session.world.restore(saved,RandomNumberGenerator.new()),"Completed recipes, research and power unlocks must restore")
	session.refresh_queries()
	screen.apply_snapshot(session.presentation_snapshot())
	screen.powers_panel.open_card("Card_GodPower_Settlement_2")
	var cast := button(screen.powers_panel.detail,"Farming Settlement")
	check(cast!=null and not cast.disabled,"The researched power must be castable after save/load")
	if cast!=null and not cast.disabled: cast.pressed.emit()
	check(screen.tool=="GodPower_PlaceSettlement_2","The unlocked power must arm the world interaction")
	screen.on_action(Vector2i(12,12),Vector2(12,12))
	session.advance_elapsed(0.1)
	check(session.presentation_snapshot()["progression"]["settlements"].size()==1,"Using the completed power card must create the actual settlement")
	# This source power unlocks on discovery; farming above requires completion.
	var original := session.world.export_state()
	var progression: Dictionary=original["state"]["progression"]
	if not "Card_Adv_Beautify_1" in progression["discovered"]: progression["discovered"].append("Card_Adv_Beautify_1")
	check(session.world.restore(original,RandomNumberGenerator.new()),"The controlled source power-discovery state must restore")
	session.world.step()
	check("GodPower_Beautify" in session.world.snapshot(false)["progression"]["powers"],"The actual source discovery condition must unlock its supported power independently of legacy IDs")
	check(session.world.inspect({"type":"use_power","power":"GodPower_Beautify","x":30,"z":30})["ok"],"The source-unlocked power must pass the ordinary gameplay gate")
	screen.queue_free()
	session.queue_free()
	await process_frame
	await process_frame
	print("Resource card completion, upgrades and playable power unlocks: %d failures"%failures)
	quit(1 if failures else 0)
