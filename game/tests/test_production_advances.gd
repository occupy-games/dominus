extends SceneTree

const World = preload("res://simulation/world.gd")
const Economy = preload("res://simulation/campaign_economy.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
const Rules = preload("res://infrastructure/progression_content.gd")
const Rewards = preload("res://infrastructure/adventure_content.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)


func definition(scope: String, population: int = 245) -> Dictionary:
	var data := preload("res://tests/fixtures/campaign_economy.gd").definition()
	data["research_scope"]=scope
	data["progression_rules"]=Rules.rules(data)
	data["progression_rules"]["influence_enabled"]=false
	data["progression_rules"]["chests"]=[]
	data["progression_rules"]["shrines"]=[]
	data["progression_rules"]["objects"]=[]
	while data["followers"].size()<population: data["followers"].append(data["followers"][0].duplicate(true))
	data["followers"].resize(population)
	return data


func make_world(scope: String,population: int = 245) -> RefCounted:
	var random := RandomNumberGenerator.new()
	random.seed=42
	var world := World.new()
	world.initialize({"campaign_data":definition(scope,population)},random)
	return world


func run() -> void:
	check(Content.homeworld()["progression_rules"]["research_scope"]=="initialworldsetup6","Runtime additional research must use the 2.4 reference scope")
	var before := make_world("initialworldsetup6",164)
	check(not "GodPower_PlaceSettlement_2" in before.snapshot(false)["progression"]["powers"],"Farming must remain locked below the source 165 followers")
	check(not "GodPower_PlaceSettlement_3" in make_world("initialworldsetup6",549).snapshot(false)["progression"]["powers"],"Mining must remain locked below the source 550 followers")
	check("GodPower_PlaceSettlement_3" in make_world("initialworldsetup6",550).snapshot(false)["progression"]["powers"],"Mining must unlock at its own source population milestone")
	var world := make_world("initialworldsetup6",165)
	var snapshot: Dictionary = world.snapshot(false)
	check("Card_Settlement_Farming" in snapshot["progression"]["discovered"] and "GodPower_PlaceSettlement_2" in snapshot["progression"]["powers"],"Discovering the original no-cost Farming advance must enable its power")
	check(world.inspect({"type":"claim_card","card":"Card_Settlement_Farming"})["ok"],"The source zero-research advance must not demand a sticker")
	world.step([{"type":"claim_card","card":"Card_Settlement_Farming"}])
	check(world.snapshot(false)["progression"]["inventory"].is_empty(),"A no-cost advance must not invent or consume stickers")
	check(not Economy.spends_resource(world.snapshot(false),"wheat"),"Farming discovery alone must not activate the later wheat-spending gate")
	for point: Vector2i in [Vector2i(12,12),Vector2i(19,12)]:
		var build := {"type":"home","x":point.x,"z":point.y,"rank":1}
		check(world.inspect(build)["ok"],"Farming must not prevent construction before Super Fast Building")
		world.step([build])
	for tick in range(1500): world.step()
	world.step([{"type":"use_power","power":"GodPower_PlaceSettlement_2","x":12,"z":12}])
	var settlement: Dictionary = world.snapshot(false)["progression"]["settlements"][0]
	var deploy := {"type":"deploy_worker","id":settlement["id"]}
	check(world.inspect(deploy)["ok"] and world.inspect(deploy)["plot_command"]["rank"]==6,"Cleared land must offer the largest reachable original farm")
	world.step([deploy])
	# The source ore milestone, then original earned Social research, unlocks a
	# real production effect. These are controlled prerequisites, not a playthrough.
	var saved: Dictionary = world.export_state()
	saved["state"]["ore"]=5
	saved["state"]["wheat"]=2
	check(world.restore(saved,RandomNumberGenerator.new()),"The ore milestone fixture must restore")
	world.step()
	var ordinary_ticks := int(world.house_spec(1)["build_ticks"])
	check(world.inspect({"type":"claim_card","card":"Card_GrainToBuild"})["ok"],"Two collected wheat must discover the original zero-research Super Fast Building card")
	world.step([{"type":"claim_card","card":"Card_GrainToBuild"}])
	check(Economy.spends_resource(world.snapshot(false),"wheat") and not Economy.spends_resource(world.snapshot(false),"ore"),"Super Fast Building must enable wheat spending independently of ore spending")
	check(world.house_spec(1)["build_ticks"]==maxi(1,roundi(ordinary_ticks*0.1)),"Super Fast Building must apply the source tenfold construction improvement")
	var modified_ticks := int(world.house_spec(1)["build_ticks"])
	check(world.reconfigure([{"category":"runtime","key":"build_rate","value":1.0}])["ok"] and world.house_spec(1)["build_ticks"]==modified_ticks,"Reloading live balance must retain active construction advances without compounding them")
	check("Card_WheatBuff_1" in world.snapshot(false)["progression"]["discovered"],"Five collected ore must discover the original Advanced Farming card")
	var field := {"kind":"farm","rank":1,"harvest_rate":0.00333}
	check(is_equal_approx(Economy.harvest_rate(world.snapshot(false),field),0.00333),"Undone advances cannot change production")
	var sticker := ""
	var p: Dictionary = world.snapshot(false)["progression"]
	for id: String in p["rules"]["stickers"]:
		if id.begins_with("Sticker_Rare_") and int(p["rules"]["stickers"][id]["contributions"].get("SOCIAL",0))>0: sticker=id; break
	check(not sticker.is_empty(),"The original catalog must contain a Social research reward")
	world.receive_voyage_rewards({"earned":{sticker:1}},Rewards.reward_rules())
	# Put the real constructed field and its assigned worker at a work tick to
	# verify the modifier in World.step, not just through a helper query.
	saved=world.export_state()
	var field_id := -1
	var baseline := 0.0
	for home: Dictionary in saved["state"]["homes"]:
		if home.get("kind","")!="farm": continue
		home["progress"]=home["build_ticks"]
		home["harvest_accumulator"]=0.1
		field_id=home["id"]
		baseline=home["harvest_rate"]
		for agent: Dictionary in saved["state"]["followers"]:
			if agent.get("workplace",-1)!=field_id: continue
			agent["job"]=-1
			agent["x"]=float(home["work_x"])
			agent["z"]=float(home["work_z"])
			agent["path"]=[]
			agent["carrying"]=0
	check(world.restore(saved,RandomNumberGenerator.new()),"The actual farmer and field must remain a valid work-state fixture")
	var command := {"type":"research_card","card":"Card_WheatBuff_1","sticker":sticker}
	check(world.inspect(command)["ok"],"An earned matching sticker must be usable on Advanced Farming")
	world.step([command])
	snapshot=world.snapshot(false)
	for home: Dictionary in snapshot["homes"]:
		if home["id"]==field_id: check(is_equal_approx(home["harvest_accumulator"],0.1+baseline*1.5*0.1),"Completing Advanced Farming must change the actual worker's next harvest tick")
	check("Card_WheatBuff_1" in snapshot["progression"]["completed"] and snapshot["progression"]["inventory"][sticker]==0,"Advanced Farming must complete by spending the actual earned sticker")
	check(is_equal_approx(Economy.harvest_rate(snapshot,field),0.00333*1.5),"Advanced Farming must apply its original 1.5 multiplier")
	for rank in range(1,7):
		var farm: Dictionary = snapshot["progression"]["rules"]["economy"]["plots"]["farm:%d"%rank]
		var mine: Dictionary = snapshot["progression"]["rules"]["economy"]["plots"]["mine:%d"%rank]
		check(is_equal_approx(Economy.harvest_rate(snapshot,farm),float(farm["harvest_rate"])*1.5),"Every source farm row must receive its modifier")
		check(is_equal_approx(Economy.harvest_rate(snapshot,mine),float(mine["harvest_rate"])),"A farming advance must leave mines unchanged")
	var later: Dictionary = snapshot.duplicate(true)
	var later_rules: Dictionary = definition("initialworldsetup7")["progression_rules"]
	later["progression"]["rules"]=later_rules
	later["progression"]["completed"].append("Card_FarmBuff2")
	check(is_equal_approx(Economy.harvest_rate(later,field),0.00333*1.5*1.5),"Weyworld Crop Rotation must compound with the retained Homeworld farming advance")
	later["progression"]["completed"].append("Card_MineBuff1")
	check(is_equal_approx(Economy.harvest_rate(later,{"kind":"mine","rank":1,"harvest_rate":0.00333}),0.00333*1.5),"Superior Pickaxes must apply the original mining multiplier")
	var weyworld := make_world("initialworldsetup7",800)
	var earned := {}
	for card: String in ["Card_FarmBuff2","Card_MineBuff1"]:
		p=weyworld.snapshot(false)["progression"]
		var research_type: String = p["rules"]["research_cards"][card]["research_type"]
		var reward := ""
		for id: String in p["rules"]["stickers"]:
			if id.begins_with("Sticker_Rare_") and int(p["rules"]["stickers"][id]["contributions"].get(research_type,0))>0: reward=id; break
		earned[reward]=int(earned.get(reward,0))+1
		weyworld.receive_voyage_rewards({"earned":earned},Rewards.reward_rules())
		var research_command := {"type":"research_card","card":card,"sticker":reward}
		check(weyworld.inspect(research_command)["ok"],"Weyworld's source population thresholds must permit its own advances: "+card)
		weyworld.step([research_command])
		check(card in weyworld.snapshot(false)["progression"]["completed"],"The later production advance must complete through real research: "+card)
	var repeated: Dictionary = world.export_state()
	check(not world.inspect(command)["ok"] and world.export_state()==repeated,"A completed buff must never spend twice or stack itself")
	var restored := World.new()
	check(restored.restore(repeated,RandomNumberGenerator.new()),"Production research must restore without presentation")
	check(is_equal_approx(Economy.harvest_rate(restored.snapshot(false),field),0.00333*1.5),"Restoring must preserve the actual production effect")
	for tick in range(10): restored.step(); world.step()
	check(restored.export_state()==world.export_state(),"Source production research must preserve deterministic continuation")
	var migration := make_world("initialworldsetup")
	saved=migration.export_state()
	saved["state"]["progression"]["research"]={"Card_Settlement_Farming":7}
	check(migration.restore(saved,RandomNumberGenerator.new()),"Previous source research must remain readable")
	migration.migrate_progression(definition("initialworldsetup6")["progression_rules"],PackedByteArray())
	check(migration.snapshot(false)["progression"]["research"]["Card_Settlement_Farming"]==0 and migration.snapshot(false)["progression"]["prior_research"]["initialworldsetup"]["Card_Settlement_Farming"]==7,"Changing source research must keep a record of earlier contributions")
	check(World.new().restore(migration.export_state(),RandomNumberGenerator.new()),"Migrated source research must remain valid for subsequent loads")
	print("Source production advances and field ranks: %d failures"%failures)
	quit(1 if failures else 0)
