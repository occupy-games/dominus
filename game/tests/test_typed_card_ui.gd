extends SceneTree

const Session = preload("res://application/game_session.gd")
const Gallery = preload("res://presentation/world/progression_panel.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func types(node: Node) -> Array:
	var result: Array=[]
	if node.has_meta("research_type"):
		check(node.texture!=null,"Type badges must use recovered original icons")
		result.append(node.get_meta("research_type"))
	for child: Node in node.get_children(): result.append_array(types(child))
	return result


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	root.size=Vector2i(1100,800)
	var data := preload("res://infrastructure/campaign_content.gd").homeworld()
	data["width"]=64
	data["terrain"]=PackedByteArray(); data["terrain"].resize(4096); data["terrain"].fill(1)
	data["rock_field"]=PackedByteArray(); data["rock_field"].resize(4096)
	data["tree_field"]=PackedByteArray(); data["tree_field"].resize(4096)
	data["followers"]=[]
	for i in range(40): data["followers"].append({"x":20+i%5,"z":20+i/5})
	data["automatic_settlement"]=false
	data["progression_rules"]["influence_enabled"]=false
	for key: String in ["chests","shrines","objects"]: data["progression_rules"][key]=[]
	var session := Session.new()
	root.add_child(session); session.set_process(false)
	session.new_campaign(data); session.advance_elapsed(0.1)
	session.receive_voyage_rewards({"earned":{"Sticker_Tools_2":1,"Sticker_Textile_2":2,"Sticker_ReligiousObject_1":1}},preload("res://infrastructure/adventure_content.gd").reward_rules())
	var panel := Gallery.new()
	panel.theme=preload("res://presentation/ui/style.gd").make_theme()
	panel.cards=preload("res://infrastructure/current_card_content.gd").entries()
	panel.textures=preload("res://infrastructure/ui_content.gd").textures()
	panel.inspect_command=session.inspect
	panel.command_requested.connect(session.submit)
	root.add_child(panel)
	session.changed.connect(func(state: Dictionary,_events: Array) -> void: panel.apply_snapshot(state))
	panel.apply_snapshot(session.presentation_snapshot())
	panel.open_card("Card_TownLife_1")
	check(types(panel.detail).has("SOCIAL"),"The selected society card must visibly identify its research type")
	var tools: TextureButton=panel.resource_slots.get("Sticker_Tools_2")
	check(tools!=null and types(tools.get_parent()).has("TECH") and types(tools.get_parent()).has("SOCIAL"),"Resources must visibly retain both original types")
	check(panel.resource_slots["Sticker_ReligiousObject_1"].self_modulate.a<1 and tools.self_modulate.a==1,"The resource tray must distinguish incompatible and compatible held resources")
	var rejected := {"type":"dominus_resource","resource":"Sticker_ReligiousObject_1"}
	check(not panel.detail_card._can_drop_data(Vector2.ZERO,rejected),"The actual portrait must reject a mismatched resource")
	var accepted := {"type":"dominus_resource","resource":"Sticker_Tools_2"}
	check(panel.detail_card._can_drop_data(Vector2.ZERO,accepted),"The portrait must accept a resource's secondary matching type")
	panel.detail_card._drop_data(Vector2.ZERO,accepted)
	session.advance_elapsed(0.1)
	check(session.world._state["progression"]["research"]["Card_TownLife_1"]==1 and session.world._state["progression"]["inventory"]["Sticker_Tools_2"]==0,"UI assignment must credit only the secondary SOCIAL point and debit exactly once")
	check(panel.snapshot["progression"]["research"]["Card_TownLife_1"]==1 and panel.resource_slots["Sticker_Tools_2"].resource_count==0,"The displayed progress and stock must refresh after an accepted drop")
	panel.open_card("Card_MaxRank_2")
	check(types(panel.detail).has("TECH"),"Changing the selected advance must update its visible type")
	check(panel.detail_card._can_drop_data(Vector2.ZERO,{"type":"dominus_resource","resource":"Sticker_Textile_2"}),"Textile's secondary TECH contribution must fit the actual shelter portrait")
	if "--capture-card-types" in OS.get_cmdline_user_args():
		panel.open_card("Card_TownLife_1")
		await process_frame; await process_frame
		root.get_texture().get_image().save_png("res://../build/card-types-ui.png")
	panel.queue_free(); session.queue_free()
	await process_frame; await process_frame
	print("Original type icons and secondary-type card drops: %d failures"%failures)
	quit(1 if failures else 0)
