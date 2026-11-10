extends SceneTree
const Session=preload("res://application/game_session.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message); failures+=1
func run() -> void:
	var asynchronous := Session.new()
	var synchronous := Session.new()
	asynchronous.threaded=true
	asynchronous.new_world()
	synchronous.new_world()
	var edge: Dictionary=asynchronous.find_edge(16,3,1)
	edge.merge({"type":"sculpt_drag","distance":1,"radius":0},true)
	asynchronous.submit(edge)
	synchronous.submit(edge)
	var before: Dictionary=asynchronous.presentation_snapshot()
	asynchronous.advance_threaded(0.1)
	check(asynchronous.presentation_snapshot()==before,"A running worker must expose the last detached snapshot")
	asynchronous.inspect(edge)
	for tick in range(100):
		if tick>0: asynchronous.advance_threaded(0.1)
		while asynchronous.worker.is_started() and asynchronous.worker.is_alive(): await process_frame
		asynchronous.finish_worker()
		synchronous.advance_elapsed(0.1)
	check(asynchronous.world.export_state()==synchronous.world.export_state(),"Threaded fixed ticks and commands must match synchronous simulation exactly")
	var detached: Dictionary=asynchronous.presentation_snapshot()
	detached["followers"][0]["x"]=-1
	check(asynchronous.world.snapshot()["followers"][0]["x"]>=0,"Published snapshots must not mutate the authoritative worker state")
	asynchronous.paused=true
	var tick: int=asynchronous.world.snapshot()["tick"]
	asynchronous.advance_threaded(1)
	check(not asynchronous.worker.is_started() and asynchronous.world.snapshot()["tick"]==tick,"Paused scheduler must not start background ticks")
	asynchronous.free()
	synchronous.free()
	print("Threaded fixed-tick ownership: %d failures" % failures)
	quit(1 if failures else 0)
