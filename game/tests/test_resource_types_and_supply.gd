extends SceneTree

const World = preload("res://simulation/world.gd")
const Research = preload("res://simulation/research.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var definition := preload("res://infrastructure/campaign_content.gd").homeworld()
	definition["width"]=64
	definition["terrain"]=PackedByteArray(); definition["terrain"].resize(4096); definition["terrain"].fill(1)
	definition["tree_field"]=PackedByteArray(); definition["tree_field"].resize(4096)
	definition["rock_field"]=PackedByteArray(); definition["rock_field"].resize(4096)
	definition["followers"]=[]
	for i in range(24): definition["followers"].append({"x":30+i%3,"z":30+i/3})
	definition["automatic_settlement"]=false
	definition["configuration"]["InitialBelief"]=1000
	var rules: Dictionary=definition["progression_rules"]
	rules["shrines"]=[]; rules["objects"]=[]; rules["chests"]=[]
	rules["influence_areas"]=[{"unlock":"Default","x":32,"z":32,"radius":25,"force":true}]
	check(rules["research_cards"]["Card_DoubleClick"]["research_type"]=="FAITH" and rules["research_cards"]["Card_DoubleClick"]["research_needed"]==24,"Dig Down must use its original FAITH research instead of a fixed resource recipe")
	check(rules["research_cards"].has("Card_TotemCapacity"),"The leash upgrade must use source typed research too")
	var world := World.new()
	var rng := RandomNumberGenerator.new(); rng.seed=2026
	world.initialize({"campaign_data":definition},rng)
	world.step()
	var p: Dictionary=world._state["progression"]
	for id: String in ["Card_MaxRank_2","Card_TownLife_1","Card_DoubleClick"]:
		if not id in p["discovered"]: p["discovered"].append(id)
	p["inventory"]={"Sticker_Textile_2":2,"Sticker_Tools_2":1,"Sticker_ReligiousObject_1":1}
	var before := world.export_state()
	check(not world.inspect({"type":"research_card","card":"Card_MaxRank_2","sticker":"Sticker_ReligiousObject_1"})["ok"],"A FAITH-only resource cannot complete a TECH card")
	check(world.export_state()==before,"An incompatible drop must preserve stock, progress and RNG")
	check(world.inspect({"type":"research_card","card":"Card_MaxRank_2","sticker":"Sticker_Textile_2"})["ok"],"A resource's secondary TECH type must be accepted")
	world.step([{"type":"research_card","card":"Card_MaxRank_2","sticker":"Sticker_Textile_2"}])
	check(Research.stock(p,"Sticker_Textile_2")==1 and "Card_MaxRank_2" in p["completed"],"Secondary-type completion consumes one resource once")
	check(world.inspect({"type":"research_card","card":"Card_TownLife_1","sticker":"Sticker_Tools_2"})["ok"],"The same Tools resource must contribute its secondary SOCIAL value to society research")
	world.step([{"type":"research_card","card":"Card_TownLife_1","sticker":"Sticker_Tools_2"}])
	check(Research.points(p,"Card_TownLife_1")==1 and Research.stock(p,"Sticker_Tools_2")==0,"Only the matching type's one point is credited; the other type is not added")
	# Houses reproduce up to their capacity and produce belief as soon as the
	# original GenerateBelief discovery unlock becomes available.
	check(not "Card_Spirituality" in p["completed"] and preload("res://simulation/building_stats.gd").belief_enabled(world._state),"Belief generation unlocks on discovery, without requiring completion")
	var plan := {"type":"home","x":24,"z":24,"rank":1}
	check(world.inspect(plan)["ok"],"The housing check must use an ordinary valid home command")
	world.step([plan])
	var opened := 0
	for tick in range(4500):
		var commands: Array=[]
		for chest: Dictionary in p["chests"]:
			var open := {"type":"open_chest","id":chest["id"]}
			if world.inspect(open)["ok"]: commands.append(open); opened+=1
		world.step(commands)
		var live := 0
		for chest: Dictionary in p["chests"]:
			if not chest["opened"]: live+=1
		check(live<=1,"Generated supply must respect the original Default area's live-chest cap")
	check(opened>=2,"Chests must replenish during a normal session rather than run out: %d"%opened)
	check(world._state["homes"].size()==1,"The housing check must retain its constructed home")
	if world._state["homes"].size()==1:
		var home: Dictionary=world._state["homes"][0]
		check(home["residents"]>0 and home["residents"]==home["capacity"],"A completed house must fill its real population capacity")
		check(home["stored"]>0 and world.inspect_building(home["id"])["belief_per_hour"]>0,"Occupied houses must store collectible belief and report their production")
		var belief: int=world._state["belief"]
		world.step([{"type":"collect","home_id":home["id"]}])
		check(world._state["belief"]>belief,"Stored house belief must be collectable through the ordinary command")
	var saved := world.export_state()
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"Resource spending, house population and chest clocks must save/load")
	for i in range(50):
		world.step(); restored.step()
	check(world.export_state()==restored.export_state(),"Supply and house production must continue deterministically after restoration")
	print("Typed resource matching, replenishing chests and occupied house belief: %d failures"%failures)
	quit(1 if failures else 0)
