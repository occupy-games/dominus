extends SceneTree

const World = preload("res://simulation/world.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
const Influence = preload("res://simulation/influence.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok:
		push_error(message)
		failures+=1


func run() -> void:
	var definition := Content.homeworld()
	var start: Dictionary = definition["followers"][0]
	var x := int(start["x"])
	var z := int(start["z"])
	var locked := Vector2i(186,218) # Authored Homeworld Expansion_2 center.
	# A source follower-reward card is supplied at the start solely to exercise
	# threshold changes without simulating hours of construction in this test.
	definition["progression_rules"]["chests"].append({"id":"fixture:growth","type":"treasure1","x":x,"z":z,"source_height":1,"depth":0,"rotation":0,"card":"Card_Character_Follower_20"})
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed=2026
	world.initialize({"campaign_data":definition},rng)
	var state := world.snapshot(false)
	check(state["progression"]["player_level"]==1,"Two original starting followers must earn the first source expansion")
	check(world.can_act_at(x,z) and not world.can_act_at(locked.x,locked.y),"The opening region must constrain actual actions")
	check(not world.inspect({"type":"lower","x":locked.x,"z":locked.y})["ok"],"An action outside influence must be rejected by simulation")
	var before: Variant = state["terrain"].duplicate()
	var belief: int = state["belief"]
	world.step([{"type":"lower","x":locked.x,"z":locked.y}])
	check(world.snapshot(false)["terrain"]==before and world.snapshot(false)["belief"]==belief,"Rejected outside actions must leave terrain and resources unchanged")
	var edited := world.snapshot(false)
	edited["progression"]["influence"][0]["radius"]=999
	check(not world.can_act_at(locked.x,locked.y),"Detached influence snapshots must not change authority")
	world.step([{"type":"open_chest","id":"fixture:growth"}])
	state=world.snapshot(false)
	check(state["followers"].size()==22 and state["progression"]["player_level"]==5,"Population must advance through distinct source thresholds")
	check(world.can_act_at(locked.x,locked.y),"Growth must make previously locked land actionable")
	var activated := false
	for area: Dictionary in state["progression"]["influence"]:
		if area["unlock"]=="Expansion_2": activated=true
	check(activated,"Population progression must reveal the authored second expansion")
	var exported := world.export_state()
	exported["state"]["followers"]=exported["state"]["followers"].slice(0,2)
	var clone := World.new()
	check(clone.restore(exported,RandomNumberGenerator.new()),"Influence and earned levels must restore")
	clone.step()
	check(clone.can_act_at(locked.x,locked.y),"Losing population must not remove earned expansions")
	var shrine_state := clone.snapshot(false)
	var expansion: Dictionary = {}
	for area: Dictionary in shrine_state["progression"]["rules"]["influence_areas"]:
		if area["unlock"]=="Expansion_9": expansion=area
	check(not Influence.contains(shrine_state,expansion["x"],expansion["z"]),"A distant shrine expansion must start locked")
	for shrine: Dictionary in shrine_state["progression"]["shrines"]:
		if shrine["id"]=="1013": shrine["complete"]=true
	Influence.refresh(shrine_state)
	check(Influence.contains(shrine_state,expansion["x"],expansion["z"]),"Completing the source shrine must unlock its new region")
	print("God influence and expansion: %d failures" % failures)
	quit(1 if failures else 0)
