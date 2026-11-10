extends SceneTree

const Content = preload("res://infrastructure/adventure_content.gd")
const World = preload("res://simulation/world.gd")
const Challenges = preload("res://simulation/voyage_challenges.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures+=1


func load_world(id: String) -> RefCounted:
	var config := Content.definition(id)
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":config},random)
	world.step([{"type":"start_voyage","followers":int(config["voyage"]["minimum"])}])
	return world


func run() -> void:
	var champion := load_world("event_02a__ex02a_map04_whackamole1")
	var state: Dictionary = champion.snapshot(false)
	check(not state["enemies"].is_empty(),"The authored Whack-a-Mole island must contain original champions")
	var enemy: Dictionary = state["enemies"][0]
	check(not champion.can_act_at(enemy["x"],enemy["z"]),"Original champion protection must prevent sculpting beneath them")
	var power := {"type":"voyage_power","power":"GodPower_FingerOfGod","x":enemy["x"],"z":enemy["z"]}
	check(champion.inspect(power)["ok"],"Champion sculpt protection must not block Finger of God")
	var belief := int(state["belief"])
	var cost: int = champion.inspect(power)["cost"]
	champion.step([power])
	state=champion.snapshot(false)
	check(state["belief"]==belief-cost and state["enemies"][0]["stamina"]<0.1,"Finger of God must charge its source cost and put a champion to sleep")
	var purity := {"type":"voyage_power","power":"GodPower_RainOfPurity","x":enemy["x"],"z":enemy["z"]}
	var cell := roundi(enemy["z"])*int(state["width"])+roundi(enemy["x"])
	# Controlled hazard fixture on a real source island: check player commands,
	# independently of whether followers happened to cross that cell this tick.
	champion._state["voyage"]["blight"][cell]=255
	champion._state["voyage"]["swamp"][cell]=255
	champion._state["voyage"]["powers"].append("GodPower_RainOfPurity")
	check(champion.inspect(purity)["ok"],"An unlocked source purification power must be usable")
	champion.step([purity])
	check(champion.snapshot(false)["voyage"]["blight"][cell]==0 and champion.snapshot(false)["voyage"]["swamp"][cell]==0,"Purification must remove both harmful fields")
	var expansion := load_world("event_02a__ex02a_map01_expshrineintroeasy")
	var goal: Array = expansion._state["voyage"]["definition"]["goal"]
	check(not expansion.can_act_at(goal[0],goal[1]),"The original goal must initially lie outside god influence")
	var host := Challenges.new()
	host.configure(expansion,expansion._state,[])
	host.hook("onTempleComplete",[1001])
	check(expansion.can_act_at(goal[0],goal[1]),"Restoring the original beacon must expand the actionable region")
	var meteor := load_world("event_03a__ex03a_map01_meteorbarrage")
	host=Challenges.new()
	host.configure(meteor,meteor._state,[])
	host.hook("onTempleComplete",[1001])
	check(meteor._state["voyage"]["scheduled"].size()==5,"Restoring the original obelisk must schedule five authored meteor strikes")
	var initial: Variant = meteor._state["terrain"].duplicate()
	for temple: Dictionary in meteor._state["voyage"]["temples"]:
		if temple["type"]=="Monument_Speed": check(temple["complete"],"Prebuilt source speed shrines must work without an invented construction detour")
	for tick in range(55): meteor.step()
	check(meteor._state["terrain"]!=initial,"Scheduled source meteors must deform the terrain through simulation")
	var saved: Dictionary = meteor.export_state()
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"Active challenge scripts and hazard fields must restore")
	meteor.step()
	restored.step()
	check(meteor.export_state()==restored.export_state(),"A restored meteor challenge must continue identically")
	print("Source voyage powers, champion protection, purification and shrine triggers: %d failures"%failures)
	quit(1 if failures else 0)
