extends SceneTree

const World = preload("res://simulation/world.gd")
const Content = preload("res://infrastructure/adventure_content.gd")
const Session = preload("res://application/game_session.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures+=1


func world_for(definition: Dictionary) -> RefCounted:
	var random := RandomNumberGenerator.new()
	random.seed=2026
	var world := World.new()
	world.initialize({"campaign_data":definition},random)
	return world


func clear_route(world: RefCounted, definition: Dictionary) -> void:
	# Self-play submits ordinary geometry commands; it never edits a snapshot.
	var start := Vector2i(definition["voyage"]["dock"][0],definition["voyage"]["dock"][1])
	var goal := Vector2i(definition["voyage"]["goal"][0],definition["voyage"]["goal"][1])
	var path: Array[Vector2i] = [start]
	var cell := start
	while cell!=goal:
		if cell.x!=goal.x: cell.x+=signi(goal.x-cell.x)
		else: cell.y+=signi(goal.y-cell.y)
		path.append(cell)
	var from: int = world.height_at(start.x,start.y)
	var to: int = world.height_at(goal.x,goal.y)
	var commands: Array = []
	for index in range(path.size()):
		cell=path[index]
		var desired := roundi(lerpf(from,to,float(index)/float(path.size()-1)))
		var old: int = world.height_at(cell.x,cell.y)
		for layer in range(absi(desired-old)):
			commands.append({"type":"raise" if desired>old else "lower","x":cell.x,"z":cell.y,"radius":0})
	for offset in range(0,commands.size(),100):
		var events: Array = world.step(commands.slice(offset,offset+100))
		for event: Dictionary in events: check(event["type"]!="rejected","Self-play route edit must be accepted: "+str(event))


func run() -> void:
	var available: Array = Content.missions().filter(func(m: Dictionary) -> bool: return m["available"] and m["family"]=="event_01" and int(m.get("order",0))<=4)
	check(available.size()==4,"Four source introductory voyages must be playable")
	var total := Content.missions().size()
	check(total>200,"Browser must include the recovered original voyage inventory")
	for descriptor: Dictionary in available:
		var definition := Content.definition(descriptor["id"])
		check(not definition.is_empty(),"Original island fields must verify against source hashes")
		var world := world_for(definition)
		check(world.snapshot()["followers"].is_empty(),"Followers must stay aboard before launch")
		check(not world.inspect({"type":"home","x":10,"z":10})["ok"],"Voyages must not start a settlement")
		check(not world.inspect({"type":"start_voyage","followers":31})["ok"],"Boat capacity must be authoritative")
		world.step([{"type":"start_voyage","followers":5}])
		check(world.snapshot()["followers"].size()==1,"First follower must leave the original dock on launch")
		if int(descriptor["order"])==1:
			# Mend the actual tutorial gap with the same diagonal layer drag as UI.
			var drag := {"type":"sculpt_drag","x":23,"z":23,"nx":0,"nz":1,"layer":1,"distance":3,"dx":4,"dz":3,"radius":1}
			check(world.inspect(drag)["ok"],"Original tutorial gap must accept a terrain-layer drag")
			world.step([drag])
			check(world.snapshot()["belief"]==0,"The introductory free-sculpt voyage must not require belief")
		else: clear_route(world,definition)
		var snapshot: Dictionary = world.snapshot()
		snapshot["voyage"]["rescued"]=999
		check(world.snapshot()["voyage"]["rescued"]==0,"Voyage snapshots must be detached")
		var restored := World.new()
		check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Mid-voyage data must restore headlessly")
		for tick in range(1300):
			world.step()
			restored.step()
			if world.snapshot(false)["voyage"]["phase"] in ["won","lost"]: break
		check(world.export_state()==restored.export_state(),"Restored voyage must continue deterministically")
		var final: Dictionary = world.snapshot(false)
		print(descriptor["name"],": ",final["voyage"]["phase"]," rescued=",final["voyage"]["rescued"]," elapsed=",final["voyage"]["elapsed"])
		check(final["voyage"]["phase"]=="won" and final["voyage"]["rescued"]==5,"All introductory islands must be completable through player commands")
		check(final["homes"].is_empty(),"Voyage followers must travel to the temple instead of building tents")
		var log := preload("res://simulation/voyage.gd").record_result({},final)
		check(log.has(descriptor["id"]),"Successful voyages must record their best result")
		check(preload("res://simulation/voyage.gd").record_result(log,final)==log,"Revisiting a finished result must be idempotent")
		check(not world.inspect({"type":"raise","x":10,"z":10})["ok"],"Finished voyages must reject further geometry edits")
	var first := Content.definition(available[0]["id"])
	var failed := world_for(first)
	failed.step([{"type":"start_voyage","followers":5}])
	for tick in range(605): failed.step()
	check(failed.snapshot()["voyage"]["phase"]=="lost","Unmended original tutorial must time out")
	var bad: Dictionary = failed.export_state()
	bad["state"]["voyage"]["definition"]["speed"]=-1
	check(not World.new().restore(bad,RandomNumberGenerator.new()),"Invalid saved voyage rates must be rejected")
	var session := Session.new()
	root.add_child(session)
	session.set_process(false)
	session.new_campaign(first)
	session.submit({"type":"start_voyage","followers":5})
	session.advance_elapsed(0.5)
	var save: Dictionary = session.save_game("res://../build/test-voyage.sqlite")
	check(save["ok"],"Voyages must save through the existing plain-data SQLite adapter")
	var before: Dictionary = session.world.export_state()
	check(session.load_game("res://../build/test-voyage.sqlite")["ok"],"Voyage load must skip Homeworld progression migrations")
	check(session.world.export_state()==before,"SQLite must preserve voyage and followers exactly")
	session.free()
	Content.progress_path="res://../build/test-voyage-results.json"
	var log := {"test":{"stars":2,"score":100,"rescued":5}}
	check(Content.write_progress(log) and Content.read_progress()==log,"Detached voyage result log must survive atomic persistence")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Content.progress_path))
	print("Original voyages and deterministic island self-play: %d failures"%failures)
	quit(1 if failures else 0)
