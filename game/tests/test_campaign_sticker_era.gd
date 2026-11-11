extends SceneTree

const World = preload("res://simulation/world.gd")
const Chests = preload("res://simulation/authored_chests.gd")
const Lifetime = preload("res://simulation/source_chest_lifetime.gd")
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool,message: String) -> void:
	if condition: return
	failures+=1
	push_error(message)


func run() -> void:
	var world:=World.new()
	var rng:=RandomNumberGenerator.new()
	rng.seed=525
	world.initialize({"campaign_data":preload("res://infrastructure/campaign_opening_content.gd").definition()},rng)
	var state: Dictionary=world._state
	state["opening"].merge({"phase":"discovery","discovery_step":2,"pit_step":1,"messages":[]},true)
	state["opening"]["globals"]["onStartPlayTriggered"]=true
	world.initialize_authored_chests()
	var events: Array=[]
	var chests:=Chests.new()
	chests.configure(world,state,events)
	chests.random=rng
	check(world.snapshot(false)["progression"]["sticker_era"]==1,"The source default sticker era must be Primitive")
	check_advance(world,chests,150,"Card_Stickers_Bronze",2)
	if not failures: check_advance(world,chests,525,"Card_Stickers_Iron",3)
	if not failures: check_bonus(world,chests,events)
	if not failures:
		var restored:=World.new()
		check(restored.restore(world.export_state(),RandomNumberGenerator.new()),"Researched sticker eras must save and reload")
		if not failures: check(restored.snapshot(false)["progression"]["sticker_era"]==3,"Reloading must retain the completed Iron advance")
	print("Homeworld6 sticker advances and chest bonuses: ",failures," failures")
	quit(1 if failures else 0)


func check_advance(world: RefCounted,chests: RefCounted,population: int,card: String,era: int) -> void:
	var state: Dictionary=world._state
	var progression: Dictionary=state["progression"]
	while state["followers"].size()<population-1: state["followers"].append(world._agent(160,123,false))
	world.step()
	check(not card in progression["discovered"],"The sticker card must remain hidden below its source population")
	state["followers"].append(world._agent(160,123,false))
	world.step()
	check(card in progression["discovered"] and world.snapshot(false)["progression"]["sticker_era"]==era-1,"Discovery must reveal the card without advancing the sticker era")
	if failures: return
	var sticker:="Sticker_ReligiousObject_1"
	var research: Dictionary=progression["rules"]["research_cards"][card]
	var value: int=progression["rules"]["stickers"][sticker]["contributions"].get(research["research_type"],0)
	check(research["research_type"]=="FAITH" and value>0,"The source advance must accept Faith stickers")
	if failures: return
	var count:=ceili(float(research["research_needed"])/value)
	progression["inventory"][sticker]=count
	for assignment in range(count): world.step([{"type":"research_card","card":card,"sticker":sticker}])
	check(card in progression["completed"] and world.snapshot(false)["progression"]["sticker_era"]==era,"Completing Faith research must advance the original reward era")
	# Force only the current-era bead to isolate the reward's input era.
	var fixture: Dictionary=state["opening"]["definition"].duplicate(false)
	fixture["sticker_selection_rules"]=fixture["sticker_selection_rules"].duplicate(true)
	for name: String in ["OldBeads","NewBeads","RareBeads"]:
		fixture["sticker_selection_rules"]["configuration"]["StickerChance_"+name]=0
	var reward: String=chests.select_sticker(fixture,progression,"Reward_ChestSticker")
	check(progression["rules"]["stickers"].get(reward,{}).get("era")==era,"The authored selector must draw from the researched era")


func check_bonus(world: RefCounted,chests: RefCounted,events: Array) -> void:
	var state: Dictionary=world._state
	var opening: Dictionary=state["opening"]
	var rules: Dictionary=opening["definition"]["chest_lifetime_rules"]
	var ordinary: Array=opening["chests"].filter(func(chest: Dictionary) -> bool: return chest["reward"].is_empty())
	check(ordinary.size()>=2,"The original chest table must provide ordinary sticker chests")
	if failures: return
	Lifetime.grant(ordinary[0],rules,0,chests.service)
	check(events.size()==1,"The original bonus gate must leave the first ordinary grant single")
	events.clear()
	Lifetime.grant(ordinary[1],rules,0,chests.service)
	check(events.size()==2,"A later eligible chest must dispatch its original bonus sticker")
	if failures: return
	var reward: String=events[1]["card"]
	check(state["progression"]["rules"]["stickers"].get(reward,{}).get("era")==2,"An Iron-era bonus must use the preceding Bronze sticker bucket")
	check(int(state["progression"]["inventory"].get(reward,0))>0,"The bonus sticker must reach the same inventory used by research")
