extends SceneTree

const World = preload("res://simulation/world.gd")
const Content = preload("res://infrastructure/campaign_content.gd")
const Research = preload("res://simulation/research.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var definition := Content.homeworld()
	var raw := FileAccess.get_file_as_bytes("res://assets/original/campaign/homeworld-rock.bin")
	var dense := 0
	var placed := 0
	for cell in range(raw.size()):
		if raw[cell]>0 and definition["terrain"][cell]>0: dense+=1
		if definition["rock_field"][cell]>0: placed+=1
	check(placed>0 and placed<dense/10,"Source density must no longer become a solid carpet of rocks: %d / %d"%[placed,dense])
	definition["width"]=64
	definition["terrain"]=PackedByteArray(); definition["terrain"].resize(4096); definition["terrain"].fill(1)
	definition["rock_field"]=PackedByteArray(); definition["rock_field"].resize(4096)
	definition["tree_field"]=PackedByteArray(); definition["tree_field"].resize(4096)
	definition["followers"]=[]
	for i in range(15): definition["followers"].append({"x":20+i%3,"z":20+i/3})
	definition["automatic_settlement"]=false
	var rules: Dictionary=definition["progression_rules"]
	rules["influence_enabled"]=false; rules["shrines"]=[]; rules["objects"]=[]; rules["chests"]=[]
	for i in range(32): rules["chests"].append({"id":"resource:%d"%i,"type":"treasure1","x":4+i%8,"z":4+i/8,"source_height":1,"depth":0,"rotation":0,"card":"Card_TEMP" if i==0 else ""})
	rules["chests"].append({"id":"gems","type":"treasure1","x":14,"z":4,"source_height":1,"depth":0,"rotation":0,"card":"Card_Gems_5"})
	var world := World.new()
	var rng := RandomNumberGenerator.new(); rng.seed=2026
	world.initialize({"campaign_data":definition},rng)
	world.step()
	check("Card_MaxRank_2" in world._state["progression"]["discovered"],"Ordinary population progression must discover the first shelter advance: "+str(world._state["progression"]["discovered"])+" / "+str(world._state["followers"].size())+" / "+str(rules["reward_cards"].has("Card_MaxRank_2")))
	check(Research.definition(world._state["progression"],"Card_MaxRank_2").get("research_type")=="TECH","The early shelter card must use the same typed resources as its artwork")
	var gems: int=world._state["gems"]
	var gift_events := world.step([{"type":"open_chest","id":"gems"}])
	check(world._state["gems"]==gems+5,"A quantified source gift must retain its original gems even without a portrait")
	for event: Dictionary in gift_events:
		if event.get("type")=="chest_opened": check(event["card"].is_empty(),"Quantified gifts without artwork must not open an unavailable card")
	var catalog := Content.card_assets()
	for i in range(32):
		var events := world.step([{"type":"open_chest","id":"resource:%d"%i}])
		for event: Dictionary in events:
			if event.get("type")!="chest_opened": continue
			var reward: String=event["card"]
			check(catalog.has(reward) and catalog[reward].get("available",false),"Every awarded chest resource must resolve original artwork and a named card")
	var p: Dictionary=world._state["progression"]
	var compatible := ""
	for resource: String in p["inventory"]:
		if world.inspect({"type":"research_card","card":"Card_MaxRank_2","sticker":resource}).get("ok",false): compatible=resource; break
	check(not compatible.is_empty(),"Normal chest rewards must include usable early-card resources")
	var legacy := world.export_state()
	legacy["state"]["progression"]["rules"]["version"]=9
	legacy["state"]["progression"]["rules"]["research_cards"].erase("Card_MaxRank_2")
	legacy["state"]["progression"]["assigned_resources"]["Card_MaxRank_2"]={"Card_Textile_1":1}
	var migrated := World.new()
	check(migrated.restore(legacy,RandomNumberGenerator.new()),"An older partially supplied recipe must remain readable")
	var linen := Research.stock(migrated._state["progression"],"Sticker_Textile_1")
	migrated.migrate_progression(rules,definition["rock_field"])
	check(Research.stock(migrated._state["progression"],"Sticker_Textile_1")==linen+1 and migrated._state["progression"]["assigned_resources"]["Card_MaxRank_2"].is_empty(),"Migrating an incompatible old assignment must refund it rather than lose stock or show false progress")
	if not compatible.is_empty():
		var before := Research.stock(p,compatible)
		world.step([{"type":"research_card","card":"Card_MaxRank_2","sticker":compatible}])
		check("Card_MaxRank_2" in p["completed"] and Research.stock(p,compatible)==before-1,"A chest resource must complete the actual playable shelter advance and be consumed once")
	var saved := world.export_state()
	saved["state"]["rock_density_version"]=0
	saved["state"]["rocks"].fill(3)
	var restored := World.new()
	check(restored.restore(saved,RandomNumberGenerator.new()),"A prior dense-rock save must remain readable")
	restored.migrate_rocks(definition["terrain"],definition["rock_field"])
	check(restored._state["rocks"]==definition["rock_field"] and restored._state["rock_density_version"]==1,"Loading old rock fields must apply corrected source placements")
	print("Playable chest resources, named cards and sparse source rocks: %d failures"%failures)
	quit(1 if failures else 0)
