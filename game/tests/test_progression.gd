extends SceneTree

const World = preload("res://simulation/world.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures+=1


func state_of(world: RefCounted) -> Dictionary:
	return world.snapshot(false)


func fixture() -> Dictionary:
	# A controlled small map tests original rules independently of unresolved
	# compatibility between the supplied map versions and legacy object tables.
	var definition := Content.homeworld()
	definition["width"]=34
	definition["terrain"]=PackedByteArray()
	for z in range(34):
		for x in range(34): definition["terrain"].append(3 if x>=10 else 2)
	definition["objects"]={"tree":[],"rock":[]}
	definition["rock_field"]=PackedByteArray()
	definition["rock_field"].resize(34*34)
	definition["rock_field"][8*34+11]=1
	definition["followers"]=[]
	for index in range(15): definition["followers"].append({"x":16+index%3,"z":16+index/3})
	definition["automatic_settlement"]=false
	var rules: Dictionary = definition["progression_rules"]
	for id: String in ["Card_MaxRank_2","Card_AbodeType_2","Card_Spirituality","Card_TotemCapacity","Card_DoubleClick"]: rules["research_cards"].erase(id)
	rules.erase("reward_cards")
	rules["influence_enabled"]=false
	check(rules["cards"]["Card_DoubleClick"]["requirements"]=={"Card_ReligiousObject_1":2},"Digging requirements must come from the original initial card data")
	check(int(rules["config"]["Cards_PercentChanceToGetCardYouNeed"])==50,"Chest weights must use the source desktop configuration")
	var power_shrine: Dictionary = {}
	for shrine: Dictionary in rules["shrines"]:
		if shrine["card"]=="Card_GodPower_TotemActivate": power_shrine=shrine.duplicate(true)
	check(power_shrine.get("build_ticks")==3000,"Totem shrine must retain its original 300-second repair time")
	power_shrine.merge({"x":20,"z":18,"build_ticks":10},true)
	rules["shrines"]=[power_shrine]
	rules["objects"]=[]
	rules["chests"]=[]
	var rewards := ["Card_Textile_1","Card_ReligiousObject_1","Card_ReligiousObject_1","Card_Character_Follower_20","Card_BuildingMaterial_1","Card_BuildingMaterial_1","Card_Tools_1","Card_Belief_1000","Card_GodPower_FingerOfGod","Card_GodPower_Beautify","Card_Belief_10000","Card_TotemCapacity"]
	for index in range(rewards.size()):
		rules["chests"].append({"id":"fixture:%d" % index,"type":"treasure1","x":10 if index==0 else 9,"z":8+index,"depth":1 if index==0 else 0,"source_height":3 if index==0 else 2,"rotation":180,"card":rewards[index]})
	return definition


func run() -> void:
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed=2026
	world.initialize({"campaign_data":fixture()},rng)
	var state := state_of(world)
	check("Card_MaxRank_2" in state["progression"]["discovered"],"Population must discover the original advance card")
	check(not world.inspect({"type":"claim_card","card":"Card_MaxRank_2"})["ok"],"A discovered card must require its material")
	check(not world.inspect({"type":"open_chest","id":"fixture:0"})["ok"],"Buried chests must remain closed")
	check(not world.inspect({"type":"dig","x":10,"z":8})["ok"],"Double-click digging must remain locked before card completion")
	var before := world.export_state()
	world.step([{"type":"claim_card","card":"Card_MaxRank_2"}])
	check(state_of(world)["progression"]["inventory"].is_empty(),"Rejected claims must not award or spend materials")
	var edge := world.find_edge(10,8,3)
	edge.merge({"type":"sculpt_drag","distance":-1,"radius":0},true)
	check(world.inspect(edge)["ok"],"A regular inward terrain drag must be able to expose the chest")
	world.step([edge])
	check(world.inspect({"type":"open_chest","id":"fixture:0"})["ok"],"Removing the covering layer must expose its chest")
	world.step([{"type":"open_chest","id":"fixture:0"}])
	check(state_of(world)["progression"]["inventory"].get("Card_Textile_1")==1,"Opening must grant the original fixed reward")
	check(not world.inspect({"type":"open_chest","id":"fixture:0"})["ok"],"An opened chest must never grant its reward twice")
	world.step([{"type":"claim_card","card":"Card_MaxRank_2"}])
	state=state_of(world)
	check(state["progression"]["max_rank"]==2 and state["progression"]["inventory"]["Card_Textile_1"]==0,"Card completion must consume its components and unlock the larger rank")
	var spec := world.house_spec()
	check(spec["span"]==3 and spec["capacity"]==3 and spec["build_ticks"]==600 and spec["birth_ticks"]==300,"Felt Tent size, capacity and timings must come from the original house table")
	world.step([{"type":"open_chest","id":"fixture:1"},{"type":"open_chest","id":"fixture:2"},{"type":"claim_card","card":"Card_DoubleClick"}])
	check(world.inspect({"type":"dig","x":10,"z":9})["ok"],"Completing Sculpting Upgrade must enable actual digging")
	world.step([{"type":"open_chest","id":"fixture:3"}])
	check(state_of(world)["followers"].size()==35,"Original follower reward cards must add the specified followers")
	world.step([{"type":"open_chest","id":"fixture:4"},{"type":"open_chest","id":"fixture:5"},{"type":"open_chest","id":"fixture:6"},{"type":"claim_card","card":"Card_AbodeType_2"}])
	check(world.house_spec()["family"]==1 and world.house_spec()["build_ticks"]==1200,"Construction completion must change the actual abode family and build time")
	check(world.inspect({"type":"home","x":23,"z":12,"rank":1})["ok"],"The upgraded construction family must have reachable plots")
	world.step([{"type":"home","x":23,"z":12,"rank":1}])
	for tick in range(600): world.step()
	var dwelling: Dictionary = state_of(world)["homes"][0]
	check(dwelling["progress"]==dwelling["build_ticks"],"A source-configured dwelling must complete construction")
	check(world.inspect({"type":"upgrade_home","id":dwelling["id"]})["ok"],"A completed dwelling must upgrade when the larger source footprint is free")
	world.step([{"type":"upgrade_home","id":dwelling["id"]}])
	dwelling=state_of(world)["homes"][0]
	check(dwelling["rank"]==2 and dwelling["span"]==3 and dwelling["build_ticks"]==1200 and dwelling["model_id"]=="hiend_primitive.group.bin:90cbbc80","Upgrading must change the actual footprint, construction duration and assembled source model")
	var power := {"type":"use_power","power":"GodPower_Totem","x":24,"z":20}
	check(not world.inspect(power)["ok"],"Undiscovered powers must remain unavailable")
	var shrine: Dictionary = state_of(world)["progression"]["shrines"][0]
	check(world.inspect({"type":"repair_shrine","id":shrine["id"]})["ok"],"A reachable original shrine must accept follower repair")
	world.step([{"type":"repair_shrine","id":shrine["id"]}])
	for tick in range(250): world.step()
	check("GodPower_Totem" in state_of(world)["progression"]["powers"],"Completing shrine repair must unlock the original power")
	world.step([{"type":"open_chest","id":"fixture:7"},power])
	state=state_of(world)
	check(state["progression"]["totem"].get("active",false),"A validated cast must place and activate the totem")
	var following := 0
	while following<3 and state["followers"][following]["job"]!=-1: following+=1
	var follower_before: Dictionary = state["followers"][following].duplicate(true)
	for tick in range(120): world.step()
	state=state_of(world)
	check(Vector2(state["followers"][following]["x"],state["followers"][following]["z"]).distance_to(Vector2(24,20))<Vector2(follower_before["x"],follower_before["z"]).distance_to(Vector2(24,20)),"Totem commands must affect headless follower navigation")
	world.step([{"type":"use_power","power":"GodPower_TotemActivate"}])
	check(not state_of(world)["progression"]["totem"]["active"],"The power must be able to release its followers")
	world.step([{"type":"open_chest","id":"fixture:8"},{"type":"open_chest","id":"fixture:9"}])
	state=state_of(world)
	var victim: Dictionary = state["followers"][0]
	var population_before: int = state["followers"].size()
	var belief_before: int = state["belief"]
	var finger := {"type":"use_power","power":"GodPower_FingerOfGod","x":victim["x"],"z":victim["z"]}
	world.step([finger])
	state=state_of(world)
	check(state["followers"].size()==population_before-1 and state["belief"]==belief_before-200,"Finger of God must affect its target and charge the source activation cost")
	check(world.inspect(finger)["cost"]==0,"An armed timed power must not charge its activation cost again for each drag sample")
	var dig_before := world.height_at(10,9)
	world.step([{"type":"dig","x":10,"z":9}])
	check(world.height_at(10,9)==dig_before-1,"Digging must change authoritative terrain")
	world.step([{"type":"use_power","power":"GodPower_Beautify","x":17,"z":17}])
	# Insufficient belief rejects the cast atomically (source cost 5000).
	check(state_of(world)["progression"]["beautified"].is_empty(),"Powers must charge the original cost and reject insufficient belief")
	world.step([{"type":"open_chest","id":"fixture:10"},{"type":"use_power","power":"GodPower_Beautify","x":17,"z":17}])
	check(not state_of(world)["progression"]["beautified"].is_empty(),"A funded Beautify cast must activate its simulation effect")
	for tick in range(81): world.step()
	check(state_of(world)["progression"]["beautified"].is_empty(),"Timed effects must expire on simulation ticks")
	world.step([{"type":"open_chest","id":"fixture:11"},{"type":"claim_card","card":"Card_TotemCapacity"}])
	check(state_of(world)["progression"]["totem_capacity"]==9,"The original Totem Upgrade must add five follower places")
	world.step([{"type":"tap_object","cell":8*34+11},{"type":"tap_object","cell":8*34+11}])
	for tick in range(34): world.step()
	check("Card_Spirituality" in state_of(world)["progression"]["discovered"],"Two rock taps plus the original delay must discover Spirituality")
	var store := Store.new()
	store.database_path="/private/tmp/dominus-progression-%d.sqlite3" % OS.get_process_id()
	check(store.save_world(world.export_state()).get("ok",false),"Progression must save through SQLite, including larger JSON requests")
	var loaded := store.load_world()
	var clone := World.new()
	check(clone.restore(loaded.get("data",{}),RandomNumberGenerator.new()),"Cards, chests, shrine progress and powers must restore")
	world.step()
	clone.step()
	check(world.export_state()==clone.export_state(),"Restored progression must continue deterministically")
	DirAccess.remove_absolute(store.database_path)
	var corrupt := world.export_state()
	corrupt["state"]["progression"]["inventory"]["Card_Textile_1"]=-1
	check(not clone.restore(corrupt,RandomNumberGenerator.new()),"Corrupt inventory must be rejected")
	print("Original chest, card and power rules: %d failures" % failures)
	quit(1 if failures else 0)
