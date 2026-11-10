extends SceneTree

const Metrics = preload("res://simulation/hud_metrics.gd")
const Happiness = preload("res://simulation/happiness.gd")
const World = preload("res://simulation/world.gd")
var failures := 0


func check(value: bool, message: String) -> void:
	if not value: failures+=1; push_error(message)


func _initialize() -> void:
	var interval := Metrics.interval(683,[800,650,1000,600])
	check(interval["previous"]==650 and interval["next"]==800 and is_equal_approx(interval["progress"],33.0/150),"Currency progress must advance between milestones, independent of table order")
	check(Metrics.interval(800,[650,800,1000])["progress"]==0,"Reaching a milestone must begin the next interval")
	check(Metrics.interval(1000,[650,800,1000])["next"]==0,"The final milestone must not invent another target")
	var config := preload("res://tests/fixtures/campaign_economy.gd").definition()
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed=22
	world.initialize({"campaign_data":config},rng)
	var snapshot := world.snapshot(false)
	check(snapshot["tribe_happiness"]=={"player":0.2,"astari":0.3},"Initial tribe values must come from the original config.csv")
	check(snapshot["currency_metrics"]["wheat"]["amount"]==0 and snapshot["currency_metrics"]["ore"]["amount"]==0,"Uncollected resources must not appear in HUD totals")
	snapshot["tribe_happiness"]["player"]=0.9
	snapshot["currency_metrics"]["wheat"]["amount"]=99
	check(world.snapshot(false)["tribe_happiness"]["player"]==0.2 and world.snapshot(false)["currency_metrics"]["wheat"]["amount"]==0,"HUD metrics must be detached from authoritative state")
	world.step()
	check(is_equal_approx(world.snapshot(false)["tribe_happiness"]["player"],0.2-0.000000125*0.1),"Happiness decay must use fixed simulation time and the source rate")
	var saved := world.export_state()
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"Happiness must survive world restore")
	check(restored.snapshot(false)["tribe_happiness"]==world.snapshot(false)["tribe_happiness"],"Restoring must preserve both tribe values")
	check(restored.step()==world.step() and restored.export_state()==world.export_state(),"HUD additions must preserve deterministic continuation")
	saved["state"]["progression"]["happiness"]["astari"]=NAN
	check(not World.new().restore(saved,RandomNumberGenerator.new()),"Malformed tribe happiness must be rejected before restore")
	saved=world.export_state()
	saved["state"]["progression"].erase("happiness")
	check(restored.restore(saved,RandomNumberGenerator.new()),"Older saves must remain loadable")
	restored.step()
	check(Happiness.valid(restored.snapshot(false)["tribe_happiness"]),"Older saves must initialize source tribe values at the next fixed tick")
	print("Source HUD metrics and tribe state: %d failures"%failures)
	quit(1 if failures else 0)
