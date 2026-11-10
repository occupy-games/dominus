extends RefCounted
## Full original sticker selector (0x1004de10). Input records retain the native
## slot 0x08/0x20 gates rather than assigning them guessed gameplay meanings.
## Service callbacks are pure simulation queries: era, card completion/remaining,
## lifetime acquired count and current owned count. No inventory is granted here.

const Bag = preload("res://simulation/source_weighted_rewards.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const MASK := 4294967295
const KINDS := ["Reward_PrimitiveSticker","Reward_BronzeSticker","Reward_IronSticker","Reward_FrontierSticker","Reward_BonusChestSticker","Reward_ChestSticker","Reward_HubworldSticker","Reward_EventSticker","Reward_RandomSticker","Reward_StormChestSticker","Reward_RandomStickerOrGem"]
const CONFIG := ["StickerChance_TotallyRandomPcnt","StickerChance_PackBeads","StickerChance_OldBeads","StickerChance_CurrentBeads","StickerChance_NewBeads","StickerChance_OldBeads_Event","StickerChance_CurrentBeads_Event","StickerChance_NewBeads_Event","StickerChance_RareBeads","StickerChance_GemBeads"]


static func finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("configuration") is Dictionary: return false
	for name: String in CONFIG:
		var value: Variant=rules["configuration"].get(name)
		if not finite(value) or float(value)<0 or float(value)>2147483647: return false
	if float(rules["configuration"][CONFIG[0]])>1: return false
	if not finite(rules.get("chance_scale")) or float(rules["chance_scale"])<=0 or float(rules["chance_scale"])>2147483647: return false
	if not Numbers.integer_between(rules.get("rare_threshold"),0,MASK) or not rules.get("rare_rewards") is Array or rules["rare_rewards"].size()!=5: return false
	for value: Variant in rules["rare_rewards"]:
		if not valid_key(value): return false
	return valid_key(rules.get("gem_reward"))


static func valid_key(value: Variant) -> bool:
	return (value is String and not value.is_empty() and value.length()<=256) or Numbers.integer_between(value,0,MASK)


static func valid_records(cards: Variant,stickers: Variant) -> bool:
	if not cards is Array or not stickers is Array or cards.size()>256 or stickers.size()>256: return false
	for card: Variant in cards:
		if not card is Dictionary or not valid_key(card.get("id")) or not Numbers.integer_between(card.get("type"),0,MASK) or not Numbers.integer_between(card.get("slot_20"),-2147483648,2147483647) or not Numbers.integer_between(card.get("category"),0,5): return false
	for sticker: Variant in stickers:
		if not sticker is Dictionary or not valid_key(sticker.get("id")) or not sticker.get("internal") is bool or not Numbers.integer_between(sticker.get("category"),0,5): return false
		for name: String in ["slot_08","era","count"]:
			if not Numbers.integer_between(sticker.get(name),0,MASK): return false
	return true


static func add(bag: Array,weight: int,value: Variant) -> void:
	bag.append({"weight":weight&MASK,"value":value})


static func total(bag: Array) -> int:
	var sum := 0
	for entry: Dictionary in bag: sum=(sum+int(entry["weight"]))&MASK
	return sum


static func config(rules: Dictionary,name: String) -> int:
	return int(Terrain.f32(float(rules["configuration"]["StickerChance_"+name])))&MASK


static func nonnegative_difference(a: int,b: int) -> int:
	var value := (a-b)&MASK
	return value if value<2147483648 else 0


static func select(kind: String,cards: Array,stickers: Array,rules: Dictionary,override: int,random_word: Callable,service: Callable) -> Variant:
	if not valid_rules(rules) or not valid_records(cards,stickers) or not Numbers.integer_between(override,0,MASK) or not service.is_valid() or (override==0 and not random_word.is_valid()): return 0
	var era := int(service.call("era",-1,[]))&MASK
	var eras: Array=[]
	var fixed := {"Reward_PrimitiveSticker":0,"Reward_BronzeSticker":1,"Reward_IronSticker":2,"Reward_FrontierSticker":3}
	if fixed.has(kind):
		add(eras,config(rules,"PackBeads"),fixed[kind])
		add(eras,config(rules,"RareBeads"),4)
	elif kind=="Reward_BonusChestSticker": add(eras,config(rules,"PackBeads"),Bag.era_bucket((era-1)&MASK))
	elif kind in ["Reward_ChestSticker","Reward_HubworldSticker","Reward_EventSticker","Reward_RandomSticker","Reward_StormChestSticker","Reward_RandomStickerOrGem"]:
		var event := kind in ["Reward_EventSticker","Reward_RandomSticker"]
		var suffix := "_Event" if event else ""
		add(eras,config(rules,"OldBeads"+suffix),Bag.era_bucket((era-1)&MASK))
		add(eras,config(rules,"CurrentBeads"+suffix),Bag.era_bucket(era))
		add(eras,config(rules,"NewBeads"+suffix),Bag.era_bucket((era+1)&MASK))
		if kind in ["Reward_ChestSticker","Reward_StormChestSticker","Reward_RandomStickerOrGem"]: add(eras,config(rules,"RareBeads"),4)
		if kind in ["Reward_StormChestSticker","Reward_RandomStickerOrGem"]: add(eras,config(rules,"GemBeads"),5)
	if total(eras)==0: return 0
	var chosen := int(Bag.choose(eras,total(eras),override,random_word))
	if chosen==4:
		var rare: Array=[]
		for value: Variant in rules["rare_rewards"]: add(rare,1,value)
		return Bag.choose(rare,5,override,random_word)
	if chosen==5: return rules["gem_reward"]
	var chosen_era := Bag.bucket_era(chosen)
	var chance := Terrain.f32(float(rules["configuration"][CONFIG[0]]))
	var random_chance: Array=[]
	add(random_chance,int(chance*float(rules["chance_scale"])),0)
	add(random_chance,int((1.0-chance)*float(rules["chance_scale"])),1)
	var prefer_active := int(Bag.choose(random_chance,total(random_chance),override,random_word))!=0
	var all_need: Array=[0,0,0,0,0,0]
	var active_need: Array=[0,0,0,0,0,0]
	var owned: Array=[0,0,0,0,0,0]
	var present: Array=[false,false,false,false,false,false]
	var any_need := false
	var any_active := false
	for index in range(cards.size()):
		var card: Dictionary=cards[index]
		if int(card["type"])!=2 or int(card["slot_20"])<=0 or bool(service.call("card_complete",index,[])): continue
		var category := int(card["category"])
		any_need=true
		all_need[category]=(int(all_need[category])+int(service.call("card_remaining",index,[])))&MASK
		if int(service.call("acquired",index,[card["id"]]))!=0:
			any_active=true
			active_need[category]=(int(active_need[category])+int(service.call("card_remaining",index,[])))&MASK
	for index in range(stickers.size()):
		var sticker: Dictionary=stickers[index]
		if sticker["id"]==0 or int(sticker["slot_08"])==0 or sticker["internal"] or int(sticker["count"])>int(rules["rare_threshold"]): continue
		var category := int(sticker["category"])
		if int(sticker["era"])==chosen_era: present[category]=true
		if int(service.call("owned",index,[sticker["id"]]))!=0:
			owned[category]=(int(owned[category])+int(service.call("owned",index,[sticker["id"]]))*int(sticker["count"]))&MASK
	var active_bag: Array=[]
	var need_bag: Array=[]
	var equal_bag: Array=[]
	# Native category zero is the empty category and never enters these bags.
	for category in range(1,6):
		if not present[category]: continue
		add(active_bag,nonnegative_difference(int(active_need[category]),int(owned[category])),category)
		add(need_bag,nonnegative_difference(int(all_need[category]),int(owned[category])),category)
		add(equal_bag,1,category)
	var chosen_category := 0
	if prefer_active and any_active and total(active_bag)!=0: chosen_category=int(Bag.choose(active_bag,total(active_bag),override,random_word))
	elif any_need and total(need_bag)!=0: chosen_category=int(Bag.choose(need_bag,total(need_bag),override,random_word))
	else: chosen_category=int(Bag.choose(equal_bag,total(equal_bag),override,random_word))
	if chosen_category==0: return 0
	var final: Array=[]
	for sticker: Dictionary in stickers:
		if sticker["id"]==0 or int(sticker["count"])>int(rules["rare_threshold"]) or sticker["internal"] or int(sticker["era"])!=chosen_era or int(sticker["category"])!=chosen_category: continue
		# The native final pass deliberately does not repeat the slot 0x08 gate.
		add(final,1,sticker["id"])
	return Bag.choose(final,total(final),override,random_word)
