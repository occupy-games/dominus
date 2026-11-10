extends SceneTree

const Content = preload("res://infrastructure/adventure_content.gd")
const World = preload("res://simulation/world.gd")
const Challenges = preload("res://simulation/voyage_challenges.gd")
var failures := 0


func _initialize() -> void:
	create_timer(180).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func run() -> void:
	var count := 0
	var variants := 0
	for mission: Dictionary in Content.missions():
		if not mission["available"]: continue
		count+=1
		for mode in range(3):
			if not mission.get("difficulties",[])[mode]["available"]: continue

			var data := Content.definition(mission["id"],mode)
			var random := RandomNumberGenerator.new()
			random.seed=2026
			var world := World.new()
			world.initialize({"campaign_data":data},random)
			world.step([{"type":"start_voyage","followers":int(data["voyage"]["minimum"])}])
			if world._state["voyage"]["phase"]!="running": failures+=1
			for tick in range(4): world.step()
			var host := Challenges.new()
			host.configure(world,world._state,[])
			for temple: Dictionary in world._state["voyage"]["temples"]:
				if temple["type"]!="Expedition_Goal": host.hook("onTempleComplete",[temple["uid"]])
			# Exercise delayed source functions at their scheduled simulation ticks.
			# This is script coverage, not a claim of winning every authored puzzle.
			for index in range(14):
				var jobs: Array = world._state["voyage"]["scheduled"]
				if jobs.is_empty(): break
				jobs.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a["tick"])<int(b["tick"]))
				world._state["voyage"]["elapsed"]=int(jobs[0]["tick"])
				world.step()
			var error: String = world._state["voyage"].get("script_error","")
			if not error.is_empty():
				failures+=1
				print(mission["id"],": ",error)
			var restored := World.new()
			if not restored.restore(world.export_state(),RandomNumberGenerator.new()):
				failures+=1
				print(mission["id"],": restore failed")
			variants+=1
	print("Original voyage script coverage: %d missions, %d variants, %d failures"%[count,variants,failures])
	quit(1 if failures else 0)
