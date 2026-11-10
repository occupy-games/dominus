extends SceneTree

const World = preload("res://simulation/world.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
const Rewards = preload("res://infrastructure/adventure_content.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func fixture() -> Dictionary:
	return preload("res://tests/fixtures/campaign_economy.gd").definition()

func new_world() -> RefCounted:
	var random := RandomNumberGenerator.new()
	random.seed=42
	var world := World.new()
	world.initialize({"campaign_data":fixture()},random)
	return world


func research(world: RefCounted,card: String) -> void:
	var p: Dictionary = world.snapshot(false)["progression"]
	var kind: String = p["rules"]["research_cards"][card]["research_type"]
	var chosen := ""
	for id: String in p["rules"]["stickers"]:
		if id.begins_with("Sticker_Rare_") and p["rules"]["stickers"][id]["contributions"].has(kind): chosen=id; break
	var profile := {"earned":{chosen:10}}
	world.receive_voyage_rewards(profile,Rewards.reward_rules())
	var command := {"type":"research_card","card":card,"sticker":chosen}
	check(world.inspect(command)["ok"],"A matching source research sticker must be usable: "+card)
	world.step([command])
	check(card in world.snapshot(false)["progression"]["completed"],"Research must activate its actual advance: "+card)


func run() -> void:
	var world := new_world()
	var p: Dictionary = world.snapshot(false)["progression"]
	check(p["rules"]["research_cards"]["Card_Settlement_Farming"]["research_needed"]==7,"Farming must use original TRADE research, not legacy fixed component recipes")
	var research_home: Dictionary = world.snapshot(false)
	research_home["progression"]["completed"]=research_home["progression"]["rules"]["cards"].keys()
	research_home["progression"]["completed"].erase("Card_Settlement_Farming")
	var useful: Dictionary = preload("res://simulation/voyage_rewards.gd").needed(research_home,Rewards.reward_rules())
	check(not useful.has("Sticker_Tools_1"),"Voyage usefulness must follow typed research, not an obsolete farming recipe")
	var trade := false
	for sticker: String in useful:
		if int(p["rules"]["stickers"].get(sticker,{}).get("contributions",{}).get("TRADE",0))>0: trade=true
	check(trade,"Voyages must recognize stickers that contribute to the new settlement research")
	check(p["rules"]["economy"]["plots"]["farm:1"]["build_ticks"]==100,"Field construction uses the source 10 seconds")
	check(is_equal_approx(float(p["rules"]["economy"]["plots"]["farm:1"]["harvest_rate"]),0.00333),"Crop production must use the source house formula")
	check(not world.inspect({"type":"use_power","power":"GodPower_PlaceSettlement_2","x":12,"z":12})["ok"],"Settlements must remain locked before their advance")
	world.receive_voyage_rewards({"earned":{"Sticker_Tools_1":1}},Rewards.reward_rules())
	var wrong := {"type":"research_card","card":"Card_Settlement_Farming","sticker":"Sticker_Tools_1"}
	var before: Dictionary = world.export_state()
	check(not world.inspect(wrong)["ok"] and world.export_state()==before,"Wrong research type must not mutate state or RNG")
	research(world,"Card_Settlement_Follower")
	for point: Vector2i in [Vector2i(12,12),Vector2i(19,12),Vector2i(40,40),Vector2i(47,40),Vector2i(12,42)]:
		var command := {"type":"home","x":point.x,"z":point.y,"rank":1}
		check(world.inspect(command)["ok"],"A source abode must be reachable for the settlement fixture")
		world.step([command])
	for tick in range(1500): world.step()
	research(world,"Card_Settlement_Farming")
	check(world.snapshot(false)["progression"]["age"]>=2,"The source Farming master advance must enter the next era")
	check(not world.inspect({"type":"home","x":24,"z":14,"rank":1})["ok"],"After farming unlocks, new abodes must require the source wheat cost")
	var farming := {"type":"use_power","power":"GodPower_PlaceSettlement_2","x":12,"z":12}
	check(world.inspect(farming)["ok"],"A researched Farming Settlement must group completed abodes")
	var belief := int(world.snapshot(false)["belief"])
	world.step([farming])
	var state: Dictionary = world.snapshot(false)
	check(state["belief"]==belief-20,"Settlement creation must pay the original cost exactly once")
	check(state["progression"]["settlements"].size()==1,"Settlement state must exist without presentation")
	var id := int(state["progression"]["settlements"][0]["id"])
	check(not world.inspect(farming)["ok"],"An abode cannot belong to two settlements")
	var deploy := {"type":"deploy_worker","id":id}
	check(world.inspect(deploy)["ok"],"Clicking the source settlement must find a reachable field plot")
	world.step([deploy])
	state=world.snapshot(false)
	var field := {}
	for home: Dictionary in state["homes"]:
		if home.get("kind","")=="farm": field=home
	check(not field.is_empty() and field["rank"]==6 and field["model_id"]=="hiend_farms.group.bin:54355584","An open large plot must use the recovered rank-six field assembly")
	check(not world.inspect({"type":"upgrade_home","id":field.get("id",-1)})["ok"],"Fields must not be upgraded as dwellings")
	var detached: Dictionary = world.snapshot(false)
	detached["progression"]["settlements"][0]["wheat"]=999
	check(world.snapshot(false)["progression"]["settlements"][0]["wheat"]==0,"Settlement snapshots must be detached")
	for tick in range(4200): world.step()
	state=world.snapshot(false)
	check(int(state["progression"]["settlements"][0]["wheat"])>=1,"A farmer must grow, harvest and carry wheat back to its settlement")
	check(int(state.get("wheat",0))==0,"Harvest must wait at the settlement for collection")
	world.step([{"type":"collect_settlement","id":id}])
	check(int(world.snapshot(false).get("wheat",0))>=1,"Collecting the settlement must grant the delivered wheat")
	# A source quantified reward exercises the original wheat-to-mining milestone;
	# the crop itself above is earned by a real construction/harvest/return loop.
	world.receive_voyage_rewards({"earned":{"Card_Wheat_10":30}},Rewards.reward_rules())
	world.step()
	check("Card_Settlement_Mine" in world.snapshot(false)["progression"]["discovered"],"Collected wheat must unlock the source mining research milestone")
	research(world,"Card_Settlement_Mine")
	var mining := {"type":"use_power","power":"GodPower_PlaceSettlement_3","x":40,"z":40}
	check(world.inspect(mining)["ok"],"Mining research must unlock a separate original mining settlement")
	world.step([mining])
	state=world.snapshot(false)
	if state["progression"]["settlements"].size()<2: quit(1); return
	var mining_id := int(state["progression"]["settlements"][1]["id"])
	var wheat := int(state["wheat"])
	world.step([{"type":"deploy_worker","id":mining_id}])
	state=world.snapshot(false)
	check(int(state["wheat"])==wheat-32,"A large rank-six mine must consume its source 32 wheat construction cost")
	for tick in range(4200): world.step()
	state=world.snapshot(false)
	check(int(state["progression"]["settlements"][1]["ore"])>=1,"A miner must work and carry ore back to its own settlement")
	world.step([{"type":"collect_settlement","id":mining_id}])
	check(int(world.snapshot(false).get("ore",0))>=1,"Delivered ore must be collectable")
	var field_before: Dictionary = {}
	for home: Dictionary in world.snapshot(false)["homes"]:
		if home.get("kind","")=="farm": field_before=home
	check(world.reconfigure([{"category":"runtime","key":"build_rate","value":1.1}])["ok"],"Live CSV balance must remain usable during the economic loop")
	for home: Dictionary in world.snapshot(false)["homes"]:
		if home.get("kind","")=="farm": check(home["max_belief"]==field_before["max_belief"] and home["harvest_rate"]==field_before["harvest_rate"] and home["build_ticks"]==field_before["build_ticks"],"Reloading abode values must not turn fields into houses")
	var restored := World.new()
	var restored_ok := restored.restore(world.export_state(),RandomNumberGenerator.new())
	check(restored_ok,"Economy and in-flight transport must restore headlessly")
	if not restored_ok: quit(1); return
	for tick in range(50): world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Restored economy must continue deterministically")
	var store := Store.new()
	store.database_path="res://../build/test-campaign-economy.sqlite"
	check(store.save_world(world.export_state()).get("ok",false),"Settlement state must save to SQLite")
	var saved: Dictionary = store.load_world()
	var loaded := World.new()
	check(saved.get("ok",false) and loaded.restore(saved.get("data",{}),RandomNumberGenerator.new()),"SQLite must preserve research, workers, carried harvest and membership")
	check(loaded.export_state()==world.export_state(),"SQLite must preserve every economy value")
	var previous: Dictionary = world.export_state()
	previous["state"]["progression"]["rules"]["version"]=2
	previous["state"]["progression"]["rules"]["houses"][0]["capacity"]=17
	previous["state"]["progression"]["rules"]["config"]["InitialTotemCapacity"]=23
	var migrated := World.new()
	check(migrated.restore(previous,RandomNumberGenerator.new()),"The previous rule version must remain readable")
	migrated.migrate_progression(fixture()["progression_rules"],PackedByteArray())
	var migrated_state: Dictionary = migrated.snapshot(false)
	check(migrated_state["progression"]["rules"]["houses"][0]["capacity"]==17 and int(migrated_state["progression"]["rules"]["config"]["InitialTotemCapacity"])==23,"Content migration must retain the player's saved CSV values")
	check(migrated_state["progression"]["research"]==world.snapshot(false)["progression"]["research"] and migrated_state["progression"]["settlements"]==world.snapshot(false)["progression"]["settlements"],"Content migration must retain applied stickers and settlement inventory")
	FileAccess.open("res://../build/campaign-economy-preview.json",FileAccess.WRITE).store_string(JSON.stringify(world.export_state()))
	var bad: Dictionary = world.export_state()
	bad["state"]["progression"]["settlements"][0]["members"].append(999999)
	check(not World.new().restore(bad,RandomNumberGenerator.new()),"Saves with orphan settlement membership must be rejected")
	print("Original research, settlements and harvest transport: %d failures"%failures)
	quit(0 if failures==0 else 1)
