extends SceneTree

const World = preload("res://simulation/world.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	var world := World.new()
	world.initialize({"campaign_data":definition},RandomNumberGenerator.new())
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
		if opening["phase"]=="promised_land" and (not continue_promised or not opening["handoff"]["available"]) or not opening["error"].is_empty(): break
		var commands := player.commands(world)
		if not commands.is_empty(): trace.append({"tick":tick,"commands":commands.duplicate(true)})
		var output := world.step(commands)
		if output.any(func(event: Dictionary) -> bool: return event["type"] in ["rejected","campaign_catch_up"]): print("Events: ",output)
		if player.planned_edits!=last_edit:
			last_edit=player.planned_edits
			print("Edit ",last_edit,": ",commands)
		if tick%200==199: print("Waiting ",tick," ",player.diagnostic," ",state["followers"].map(func(a: Dictionary) -> Array: return [a["x"],a["z"],a["state"]]))
		if player.planned_edits>150: break
	var terminal: Dictionary = world._state["opening"]
	var success: bool = terminal["error"].is_empty() and terminal["phase"]=="promised_land" and (not continue_promised or terminal["promised_step"]==2 and not terminal["handoff"]["available"])
	FileAccess.open("res://../build/authored-trail-commands.json",FileAccess.WRITE).store_string(JSON.stringify({"trace":trace,"phase":terminal["phase"],"checkpoint":terminal["checkpoint"],"promised_step":terminal["promised_step"],"error":terminal["error"],"diagnostic":player.diagnostic,"supported_terminal_reached":success},"  "))
	print("Trail result: ",terminal["phase"]," checkpoint ",terminal["checkpoint"]," Promised Land step ",terminal["promised_step"]," error ",terminal["error"]," diagnostic ",player.diagnostic)
	quit(0 if success else 1)
