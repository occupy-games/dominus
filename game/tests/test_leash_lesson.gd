extends SceneTree

const World = preload("res://simulation/world.gd")
const Lesson = preload("res://simulation/leash_lesson.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value:
		failures+=1
		push_error(message)


func run() -> void:
	var source := preload("res://infrastructure/leash_lesson_content.gd").definition()
	if source.is_empty():
		push_error("Missing original mission-3 content")
		quit(1)
		return
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"leash_lesson":source},random)
	var state: Dictionary=world._state
	var lesson: Dictionary=state["leash_lesson"]
	check(state["followers"].size()==5+source["home_capacity"] and state["belief"]==10000,"Mission 3 must use the scripted spawns, occupied house and starting belief")
	var target: Array=source["target"]
	var first := {"type":"leash","followers":[lesson["first_id"]],"x":target[0],"z":target[1]}
	check(not world.inspect(first)["ok"],"The introduction must precede the first leash")
	world.step([{"type":"campaign_ack","id":6000}])
	var off_target := first.duplicate()
	off_target["x"]=0
	check(not world.inspect(off_target)["ok"] and state["belief"]==10000,"An off-target leash must leave the follower and belief unchanged")
	check(world.inspect(first)["ok"] and world.inspect(first)["cost"]==100,"The first authored follower must have a reachable route to the plot")
	world.step([first])
	for tick in range(700):
		if lesson["prompt"]["ack"]: break
		world.step()
	check(lesson["stage"]==Lesson.BUILDER_SLOT and lesson["prompt"]["ack"] and state["belief"]==9900,"A real walk and build must expose the second builder slot")
	world.step([{"type":"campaign_ack","id":6004}])
	var house := {"type":"leash","followers":[],"home_id":lesson["home_id"],"x":target[0],"z":target[1]}
	check(world.inspect(house)["ok"],"An occupant must be able to take the second construction slot")
	world.step([house])
	check(lesson["stage"]==Lesson.TEAMWORK and state["homes"][0]["residents"]==source["home_capacity"]-1 and state["belief"]==9800,"House leash must release exactly one occupant and charge once")
	world.step([{"type":"campaign_ack","id":6008}])
	var temple: Array=source["temple_hint"]
	var group := {"type":"leash","followers":[],"x":temple[0],"z":temple[1]}
	for index in range(1,5): group["followers"].append(state["followers"][index]["id"])
	var incomplete := group.duplicate(true)
	incomplete["followers"].pop_back()
	check(not world.inspect(incomplete)["ok"],"All four original followers must participate in the group lesson")
	check(world.inspect(group)["ok"] and world.inspect(group)["cost"]==400,"The group must find four approaches to the original shrine")
	world.step([group])
	check(lesson["stage"]==Lesson.REPAIR and state["belief"]==9400 and not state["progression"]["shrines"][0]["complete"],"Directing the group must start actual repair and charge all four followers once")
	var pins: Dictionary=world.snapshot(false)["leash_pins"]
	check(group["followers"].all(func(id: int) -> bool: return pins.get(id)==Vector2(temple[0],temple[1])),
		"The tutorial group must share the dropped pin as it walks to the shrine")
	for tick in range(1600):
		if lesson["stage"]==Lesson.RETURN: break
		world.step()
	check(state["progression"]["shrines"][0]["complete"] and lesson["stage"]==Lesson.RETURN,"Only completing the work can expose the original return prompt")
	check(world.snapshot(false)["leash_pins"].is_empty(),"The group pin must clear after the followers reach their work slots")
	var events:=world.step([{"type":"campaign_ack","id":6013}])
	check(state["won"] and events.has({"type":"campaign_leash_lesson_return"}),"Dismissing the final instruction must request the return to Homeworld")
	print("Original Leashing tutorial: ",failures," failures")
	quit(1 if failures else 0)
