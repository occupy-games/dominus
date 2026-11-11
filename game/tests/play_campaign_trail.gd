extends SceneTree

const World = preload("res://simulation/world.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	var player := Player.new()
	var trace: Array = []
	var last_checkpoint := -2
	var last_edit := -1
	var continue_promised := "--promised-land" in OS.get_cmdline_user_args()
	for tick in range(12000):
		var state: Dictionary = world._state
		var opening: Dictionary = state["opening"]
		if int(opening["checkpoint"])!=last_checkpoint:
			last_checkpoint=int(opening["checkpoint"])
			print("Checkpoint ",last_checkpoint," at ",tick," edits ",player.planned_edits," followers ",state["followers"].map(func(a: Dictionary) -> Array: return [a["x"],a["z"],a["state"]]))
		if opening["phase"] in ["promised_land","timeline","shrine","belief","discovery"] and (not continue_promised or not opening["handoff"]["available"]) or not opening["error"].is_empty(): break
		var commands := player.commands(world) if opening["phase"]!="discovery" or tick%5==0 else []
		if not commands.is_empty(): trace.append({"tick":tick,"commands":commands.duplicate(true)})
		var output := world.step(commands)
		if output.any(func(event: Dictionary) -> bool: return event["type"] in ["rejected","campaign_catch_up"]): print("Events: ",output)
		if player.planned_edits!=last_edit:
			last_edit=player.planned_edits
			print("Edit ",last_edit,": ",commands)
		if tick%200==199: print("Waiting ",tick," ",player.diagnostic," ",state["followers"].map(func(a: Dictionary) -> Array: return [a["x"],a["z"],a["state"]]))
		if player.planned_edits>150: break
	for follower: Dictionary in world._state["followers"]:
		if follower["state"]!="indoors": print("Unsettled follower: ",follower)
	if world._state["opening"].get("shrine_step",-1)==4: print("Incomplete housing: ",world._state["homes"])
	var terminal: Dictionary = world._state["opening"]
	var success: bool=terminal["error"].is_empty() and (terminal["phase"]=="promised_land" if not continue_promised else terminal["phase"]=="discovery" and terminal.get("pit_step")==1)
	var occupancy: Array=world._state["homes"].filter(func(home: Dictionary) -> bool: return home.get("kind","")=="").map(func(home: Dictionary) -> int: return int(home["residents"]))
	var population: int=world._state["followers"].size()
	var card: String=terminal.get("level_card","")
	var stickers: int=preload("res://simulation/research.gd").stock(world._state["progression"],"Sticker_Tools_1")
	var huts: int=world._state["homes"].filter(func(home: Dictionary) -> bool: return home.get("source_house")=="AbodeType_1_Rank_1" and home["progress"]==home["build_ticks"]).size()
	var shrine_active: bool=world.source_shrine_site(terminal["definition"].get("first_shrine_id","")).get("complete",false)
	var pit_active: bool=terminal["phase"]=="discovery" and world.source_shrine_site().get("complete",false)
	if continue_promised:
		success=success and population>=24 and occupancy.size()>=12 and huts>=7
		success=success and card in world._state["progression"]["completed"] and stickers==0 and shrine_active and world.can_act_at(160,166)
		success=success and terminal.get("belief_level_card","") in world._state["progression"]["discovered"]
		success=success and terminal.get("belief_level_card","") in world._state["progression"]["completed"] and terminal["persistent"]["BeliefProgress"]==1337 and world._state["collected"]>0
		success=success and pit_active and "Card_PitOfSacrifice" in world._state["progression"]["completed"]
	var result := {"trace":trace,"phase":terminal["phase"],"checkpoint":terminal["checkpoint"],"handoff":terminal["handoff"],
		"promised_step":terminal["promised_step"],"timeline_step":terminal.get("timeline_step",-1),
		"shrine_step":terminal.get("shrine_step",-1),"belief_step":terminal.get("belief_step",-1),
		"error":terminal["error"],"diagnostic":player.diagnostic,"supported_terminal_reached":success,
		"population":population,"occupancy":occupancy,"level_card":card,"first_chest_stickers":stickers,
		"mud_huts":huts,"shrine_active":shrine_active,"belief_level_card":terminal.get("belief_level_card",""),
		"belief_collected":world._state["collected"],"belief_balance":world._state["belief"],"pit_active":pit_active}
	FileAccess.open("res://../build/authored-trail-commands.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("Trail result: ",terminal["phase"]," checkpoint ",terminal["checkpoint"]," Promised Land step ",terminal["promised_step"]," error ",terminal["error"]," diagnostic ",player.diagnostic)
	quit(0 if success else 1)
