extends SceneTree

const World = preload("res://simulation/world.gd")
const Player = preload("res://simulation/campaign_opening_player.gd")
const Registry = preload("res://simulation/source_plot_registry.gd")
const SourcePlots = preload("res://simulation/source_plots.gd")
const Schedule = preload("res://simulation/source_plot_schedule.gd")
var failures := 0


func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func near_first_plot(world: RefCounted) -> Array:
	return Registry.snapshot(world._state["source_plots"])["plots"].filter(func(plot: Dictionary) -> bool:
		return SourcePlots.intersects_query(Vector2(plot["x"],plot["z"]),int(plot["size"]),Vector2(161,123),1.0))


func run() -> void:
	var definition := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(not definition.is_empty(),"Homeworld must inject the losslessly recovered plot field")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	check(world._state.has("source_plots") and Registry.valid(world._state["source_plots"]),"The campaign must own its persistent native plot registry")
	var player := Player.new()
	var sculpted := false
	var rejected := false
	var drag := {"type":"sculpt_drag","x":160,"z":120,"nx":1,"nz":0,"layer":1,"distance":1,"radius":0}
	for tick in range(5000):
		var opening: Dictionary=world._state["opening"]
		if not opening["error"].is_empty() or int(opening["promised_step"])>=2: break
		var commands := player.commands(world)
		# Change the coastal corner while the original trail still accepts
		# ordinary sculpting. No edited save, callback jump or terrain injection.
		if not sculpted and opening["phase"]=="trail" and int(opening["checkpoint"])>=12 and not opening["movement_paused"]:
			check(world.inspect(drag)["ok"],"The coastal plot preparation must be an accepted terrain drag")
			if world.inspect(drag)["ok"]: commands.append(drag); sculpted=true
		var events := world.step(commands)
		rejected=rejected or events.any(func(event: Dictionary) -> bool: return event["type"]=="rejected")
	check(sculpted and not rejected and world._state["opening"]["error"].is_empty(),"Played terrain preparation and source callbacks must use accepted commands")
	check(int(world._state["opening"]["promised_step"])==2,"Real trail, arrival, explanations and first-rock removal must reach the abode handoff")
	check(world.source_plot_capacity(158,120)>=4,"The ordinary drag and rock removal must expose the full four-quad tent footprint")
	var plots := near_first_plot(world)
	check(plots.size()==1 and int(plots[0]["x"])==158 and int(plots[0]["z"])==120 and int(plots[0]["size"])==4,"The real campaign must allocate the source-observed first tent plot")
	check(Registry.valid(world._state["source_plots"]),"Played allocation must retain pool, ownership and scheduler invariants")
	check(world._state["homes"].is_empty() and not world._state["opening"]["handoff"]["available"],"Allocating plots must not fabricate unported follower construction")
	if plots.is_empty():
		print("Original campaign plot integration: %d failures"%failures)
		quit(1)
		return
	var id := int(plots[0]["id"])
	var actor: int=world._state["followers"][0]["id"]
	var profile := {"radius":12.0,"height_balance":1.0,"priority_scale":1.0,"disabled":false,"actor_mode":0}
	var before_offer := world.export_state()
	var offer := world.source_build_offer(actor,[id],profile)
	check(offer.get("action")==102 and offer.get("plot")==id and offer.get("center")==[160.0,122.0],"The original builder plot branch must evaluate the genuinely played first plot from the follower's current position")
	check(world.export_state()==before_offer and world.query_copy().source_build_offer(actor,[id],profile)==offer,"Native construction offers must remain read-only across live and detached queries")
	check(world.source_build_offer(actor,[id,id],profile).is_empty() and world.source_build_offer(-1,[id],profile).is_empty(),"Invalid candidate identities must not produce source offers")
	var detached := world.snapshot(false)
	detached["source_plots"]["slots"][id]["size"]=0
	detached["source_plots"]["owners"].clear()
	check(int(world._state["source_plots"]["slots"][id]["size"])==4 and not world._state["source_plots"]["owners"].is_empty(),"Presentation snapshots must detach plot geometry and ownership")
	var store := preload("res://infrastructure/world_store.gd").new()
	store.database_path="res://../build/test-campaign-plots.sqlite"
	check(store.save_world(world.export_state()).get("ok",false),"A newly appearing source plot must save through SQLite")
	var saved: Dictionary=store.load_world()
	var restored := World.new()
	check(saved.get("ok",false) and restored.restore(saved.get("data",{}),RandomNumberGenerator.new()),"Plot pool identities, pending dirty regions and animation progress must reload")
	check(restored.source_build_offer(actor,[id],profile)==offer,"SQLite must preserve the native builder's exact offer and source priorities")
	for tick in range(8): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Source plots must continue identically after SQLite reload")
	check(int(world._state["source_plots"]["slots"][id]["stored_size"])==4,"The source lifetime must retain settled plot geometry")
	check(world.reconfigure([{"category":"influence","index":0,"field":"radius","value":1},{"category":"influence","index":1,"field":"radius","value":1}]).get("ok",false),"Live area values must rebuild authoritative influence around existing plots")
	for tick in range(21): world.step()
	check(not world.source_plot_eligible(158,120) and int(world._state["source_plots"]["slots"][id]["size"])==4,"Existing plots must receive native geometry maintenance even after their origin leaves construction influence")
	check(world.source_build_offer(actor,[id],profile).get("action")==250,"A retained plot must still pass the builder's center influence gate before it can be offered")
	var power_area := -1
	for index in range(world._state["progression"]["rules"]["influence_areas"].size()):
		if world._state["progression"]["rules"]["influence_areas"][index].get("powers_only",false): power_area=index; break
	check(power_area>=0 and world.reconfigure([{"category":"influence","index":power_area,"field":"x","value":160},{"category":"influence","index":power_area,"field":"z","value":122},{"category":"influence","index":power_area,"field":"radius","value":4}]).get("ok",false),"A controlled source power-only area must apply through the real live configuration boundary")
	for tick in range(21): world.step()
	check(not world.source_plot_eligible(160,122) and world.source_build_offer(actor,[id],profile).get("action")==102,"The native builder's power/max gate must differ from fresh allocation's normal-minus-restricted gate")
	check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"A retained plot outside reduced influence must remain saveable")
	# Controlled damage to the genuinely played map checks the live terrain
	# adapter and delayed release. It does not bypass the tutorial handoff or
	# claim that sculpting during that unavailable stage is supported.
	var damaged := world.export_state()
	damaged["state"]["terrain"][122*1024+160]=0
	damaged["state"]["terrain_revision"]+=1
	Schedule.mark(damaged["state"]["source_plots"]["schedule"],160,122)
	var repaired := World.new()
	check(repaired.restore(damaged,RandomNumberGenerator.new()),"A controlled terrain-damage checkpoint must retain valid registry ownership")
	repaired.step()
	check(int(repaired._state["source_plots"]["slots"][id]["size"])==0 and repaired._state["source_plots"]["active"].has(id),"An interior slope must remove the live footprint while retaining its fading source slot")
	check(store.save_world(repaired.export_state()).get("ok",false),"A disappearing source plot must save before its pool slot is released")
	saved=store.load_world()
	check(saved.get("ok",false) and restored.restore(saved.get("data",{}),RandomNumberGenerator.new()),"Removed footprints and source lifetime progress must reload")
	for tick in range(4): repaired.step(); restored.step()
	check(repaired._state["source_plots"]["active"].has(id) and repaired._state["source_plots"]["slots"][id]["progress"]==1.0,"The plot must retain its slot through the final fade tick")
	repaired.step(); restored.step()
	check(not repaired._state["source_plots"]["active"].has(id) and int(repaired._state["source_plots"]["free"][0])==id,"The following source tick must release the old identity to the front of the free pool")
	check(repaired.export_state()==restored.export_state() and Registry.valid(repaired._state["source_plots"]),"Fading plot ownership and free-list continuation must remain exact after SQLite reload")
	var invalid := world.export_state()
	invalid["state"]["source_plots"]["free"].append(id)
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"An overlapping active/free pool must reject before replacing simulation state")
	invalid=world.export_state()
	invalid["state"]["opening"]["definition"]["plot_field"]["values"]["0"]=1
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Nonzero rotation fields must not silently use the specialized Homeworld adapter")
	for key: String in ["plot_environment","house_selection","plot_field"]:
		invalid=world.export_state()
		invalid["state"]["opening"]["definition"].erase(key)
		check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Missing plot adapter dependencies must reject cleanly: "+key)
	invalid=world.export_state()
	invalid["state"]["opening"]["definition"]["plot_resize_rules"].erase("progress_rate")
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Missing plot transition timing must reject before a fixed tick")
	invalid=world.export_state()
	invalid["state"]["opening"]["definition"]["build_candidate_values"]["AbodeType_0_Rank_1"]["build capacity"]=NAN
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Malformed saved source worker capacities must reject before querying the builder")
	invalid=world.export_state()
	invalid["state"]["opening"]["definition"]["build_candidate_values"].erase("AbodeType_0_Rank_1")
	check(not World.new().restore(invalid,RandomNumberGenerator.new()),"Every injected house selection must have its source candidate inputs")
	print("Original campaign plot integration: %d failures"%failures)
	quit(1 if failures else 0)
