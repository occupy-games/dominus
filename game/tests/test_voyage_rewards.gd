extends SceneTree

const Content = preload("res://infrastructure/adventure_content.gd")
const Campaign = preload("res://infrastructure/campaign_content.gd")
const World = preload("res://simulation/world.gd")
const Rewards = preload("res://simulation/voyage_rewards.gd")
const Progression = preload("res://simulation/progression.gd")
const Store = preload("res://infrastructure/world_store.gd")
var failures := 0


func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures+=1


func run() -> void:
	var definition := Content.definition("event_01__ex01_map01_coretutorial")
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=2026
	world.initialize({"campaign_data":definition},random)
	world.step([{"type":"start_voyage","followers":8}])
	world.step([{"type":"sculpt_drag","x":23,"z":23,"nx":0,"nz":1,"layer":1,"distance":3,"dx":4,"dz":3,"radius":1}])
	for tick in range(600): world.step()
	check(world.snapshot(false)["voyage"]["phase"]=="won","Earn rewards by actually finishing the original first island")
	check(preload("res://simulation/voyage.gd").arrival_score({"MissionScoreFollowerReachedTemple":200,"MissionScoreFollowerReachedTempleTimeMult":0.08,"MissionScoreFollowerTimePower":2},60,30)==440,"Arrival score must use the original executable’s normalized quadratic time bonus")
	var rules := Content.reward_rules()
	var profile := Rewards.record(Rewards.empty(),world.snapshot(false),rules,random)
	check(profile["earned"].get("Sticker_ReligiousObject_1",0)==1 and profile["earned"].get("Sticker_Textile_1",0)==1,"First-island score must award the exact original 1000/2000-point stickers")
	var again := Rewards.record(profile,world.snapshot(false),rules,random)
	check(again["earned"]==profile["earned"] and again["last_awards"].is_empty(),"Revisiting victory must not duplicate source rewards")
	Content.progress_path="res://../build/test-voyage-profile.json"
	check(Content.write_progress(profile),"Reward entitlements must persist atomically before transfer")
	var durable := Content.read_profile()
	check(durable["earned"]==profile["earned"] and durable["claimed"]==profile["claimed"],"Reward grants and claimed thresholds must survive restart")
	var home := World.new()
	home.initialize({"campaign_data":Campaign.homeworld()},RandomNumberGenerator.new())
	check(home.receive_voyage_rewards(durable,rules)["count"]==2,"Source stickers must transfer into Homeworld inventory")
	check(home.receive_voyage_rewards(durable,rules)["count"]==0,"Applying the same durable profile twice must be idempotent")
	check(home.snapshot(false)["progression"]["inventory"].get("Sticker_Textile_1",0)==1,"Homeworld must retain the canonical original sticker ID")
	# Controlled card-discovery precondition: the normal population gate is
	# covered by campaign self-play; this checks real card-payment behavior.
	Progression.discover(home._state["progression"],"Card_TownLife_1")
	var assignment := {"type":"research_card","card":"Card_TownLife_1","sticker":"Sticker_Textile_1"}
	check(home.inspect(assignment)["ok"],"An adventure Linen sticker must contribute to its matching SOCIAL research type")
	home.step([assignment])
	check(home.snapshot(false)["progression"]["research"].get("Card_TownLife_1")==1,"Homeworld research must receive the actual adventure sticker contribution")
	check(home.snapshot(false)["progression"]["inventory"]["Sticker_Textile_1"]==0,"The used Linen sticker must leave inventory")
	check(home.receive_voyage_rewards(durable,rules)["count"]==0 and home.snapshot(false)["progression"]["inventory"]["Sticker_Textile_1"]==0,"A spent adventure sticker must not reappear on return or reload")
	var store := Store.new()
	store.database_path="res://../build/test-voyage-homeworld.sqlite"
	check(store.save_world(home.export_state())["ok"],"Homeworld must save consumed rewards and redemption counters together")
	var loaded := store.load_world()
	var restored := World.new()
	check(loaded["ok"] and restored.restore(loaded["data"],RandomNumberGenerator.new()),"Homeworld reward state must restore from SQLite")
	check(restored.receive_voyage_rewards(durable,rules)["count"]==0,"Reloading Homeworld cannot duplicate rewards")
	var glacier := Content.definition("event_02a__ex02a_map10_glacier")
	var fixture := {"voyage":{"definition":glacier["voyage"],"phase":"won","stars":1,"score":1000,"rescued":15}}
	var rare := Rewards.record(Rewards.empty(),fixture,rules,random)
	check(rare["earned"].get("Sticker_Rare_Tech",0)==1,"Glacier must award its explicitly authored rare technology sticker")
	var generator := Rewards.empty()
	Rewards.grant(generator,"Pack_PrimitiveB",1,rules,random,1,{})
	var count := 0
	for amount: int in generator["earned"].values(): count+=amount
	check(count==5,"The original Primitive pack must unpack into five source stickers")
	for id: String in generator["earned"]: check(rules["stickers"].has(id),"Random rewards must be original original game stickers")
	for path: String in [Content.progress_path,store.database_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Original voyage rewards, Homeworld spending and durable deduplication: %d failures"%failures)
	quit(1 if failures else 0)
