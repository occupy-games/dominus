extends RefCounted
## Source advance research over shared inventory. Queries can register source
## counters; UI callers must query a detached copy, never authoritative state.

const Availability = preload("res://simulation/source_availability.gd")
const Hash = preload("res://simulation/source_hash.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const MASK := 4294967295


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not rules.get("research_suffixes") is Array or rules["research_suffixes"].size()!=6 or not rules.get("completion_suffix") is String: return false
	if rules["completion_suffix"].length()>256 or rules["completion_suffix"].to_utf8_buffer().has(0): return false
	for suffix: Variant in rules["research_suffixes"]:
		if not suffix is String or suffix.length()>256 or suffix.to_utf8_buffer().has(0): return false
	for field: String in ["research_limit","combination_limit"]:
		if not Numbers.integer_between(rules.get(field),0,MASK): return false
	if not rules.get("strings") is Dictionary or not rules.get("happiness") is Dictionary: return false
	for address: String in ["0x104a6510","0x104a64b8","0x104a6768","0x104a6700","0x104a6680","0x104a6644","0x104a65f8"]:
		if not rules["strings"].get(address) is String: return false
	for amount: String in ["-3","-2","-1","1","2","3"]:
		if not rules["happiness"].get(amount) is String: return false
	return true


static func valid_card(card: Variant) -> bool:
	if not card is Dictionary or not card.get("name") is String or card["name"].length()>256 or card["name"].to_utf8_buffer().has(0): return false
	for field: String in ["id","type","category"]:
		if not Numbers.integer_between(card.get(field),0,MASK): return false
	for field: String in ["research_needed","happiness"]:
		if not Numbers.integer_between(card.get(field),-2147483648,2147483647): return false
	return true


static func valid_sticker(sticker: Variant) -> bool:
	if not sticker is Dictionary or not Numbers.integer_between(sticker.get("id"),0,MASK) or not sticker.get("internal") is bool: return false
	for field: String in ["categories","counts"]:
		if not sticker.get(field) is Array or sticker[field].size()!=2: return false
		for value: Variant in sticker[field]:
			if not Numbers.integer_between(value,0,MASK): return false
	return true


static func research_key(state: Dictionary,card: Dictionary,rules: Dictionary) -> int:
	var category := int(card["category"])
	var suffix: String=rules["research_suffixes"][category] if category<6 else ""
	var id := Hash.text(card["name"]+suffix)
	Availability.register(state,id,int(rules["research_limit"]),int(rules["research_limit"]))
	return id


static func combination_key(state: Dictionary,card: Dictionary,sticker: int,rules: Dictionary) -> int:
	var id := Hash.pair(int(card["id"]),sticker)
	Availability.register(state,id,int(rules["combination_limit"]),int(rules["combination_limit"]))
	return id


static func completion_key(state: Dictionary,card: Dictionary,rules: Dictionary) -> int:
	var id := Hash.text(card["name"]+rules["completion_suffix"])
	Availability.register(state,id,1,1)
	return id


static func completed(state: Dictionary,card: Dictionary,rules: Dictionary) -> bool:
	return Availability.acquired(state,completion_key(state,card,rules))>0


static func progress(state: Dictionary,card: Dictionary,rules: Dictionary) -> float:
	var amount := Availability.owned(state,research_key(state,card,rules))
	return Terrain.f32(Terrain.f32(float(amount))/maxf(1.0,Terrain.f32(float(card["research_needed"]))))


static func remaining(state: Dictionary,card: Dictionary,rules: Dictionary) -> int:
	if completed(state,card,rules): return 0
	var amount := Availability.owned(state,research_key(state,card,rules))
	var difference := (int(card["research_needed"])-amount)&MASK
	if difference>=2147483648: return 0
	# This repeated read/registration is observable in the original map storage.
	return (int(card["research_needed"])-Availability.owned(state,research_key(state,card,rules)))&MASK


static func ready(state: Dictionary,card: Dictionary,rules: Dictionary) -> bool:
	return int(card["type"])==2 and Availability.owned(state,int(card["id"]))!=0 and not completed(state,card,rules) and remaining(state,card,rules)==0


static func find(stickers: Array,id: int) -> Dictionary:
	for index in range(stickers.size()-1,-1,-1):
		if int(stickers[index]["id"])==id: return stickers[index]
	return {}


static func can_assign(state: Dictionary,card: Dictionary,stickers: Array,id: int,allow_internal: bool,rules: Dictionary) -> bool:
	if id==0 or int(card["type"])!=2 or Availability.acquired(state,int(card["id"]))==0 or completed(state,card,rules) or remaining(state,card,rules)==0: return false
	if not allow_internal:
		var sticker := find(stickers,id)
		if sticker.is_empty() or sticker["internal"]: return false
	var sticker := find(stickers,id)
	return not sticker.is_empty() and int(card["category"]) in sticker["categories"]


static func log_(service: Callable,rules: Dictionary,address: String,args: Array=[]) -> void:
	service.call("log",[28,rules["strings"][address],args])


static func assign(state: Dictionary,card: Dictionary,stickers: Array,id: int,allow_internal: bool,rules: Dictionary,limits: Dictionary,events: Array,service: Callable,exempt: Array=[]) -> bool:
	if int(card["type"])!=2: return false
	if not can_assign(state,card,stickers,id,allow_internal,rules):
		log_(service,rules,"0x104a6768")
		return false
	if Availability.owned(state,int(card["id"]))==0 or completed(state,card,rules) or ready(state,card,rules):
		log_(service,rules,"0x104a65f8")
		return false
	var research := research_key(state,card,rules)
	var combination := combination_key(state,card,id,rules)
	var sticker := find(stickers,id)
	var slot: int=sticker["categories"].find(int(card["category"]))
	var count := mini(int(sticker["counts"][slot]),remaining(state,card,rules))
	if not Availability.spend(state,id,1,exempt):
		log_(service,rules,"0x104a6644")
		return false
	if not Availability.acquire(state,combination,1,limits,events,exempt) or not Availability.acquire(state,research,count,limits,events,exempt):
		log_(service,rules,"0x104a6680")
		return false
	log_(service,rules,"0x104a6700",[combination,int(card["id"]),id])
	return true


static func complete(state: Dictionary,card: Dictionary,context: Dictionary,player: int,rules: Dictionary,limits: Dictionary,events: Array,service: Callable,exempt: Array=[]) -> bool:
	if int(card["type"])!=2: return false
	if Availability.owned(state,int(card["id"]))==0 or completed(state,card,rules) or remaining(state,card,rules)!=0:
		log_(service,rules,"0x104a64b8")
		return false
	var research := research_key(state,card,rules)
	var completion := completion_key(state,card,rules)
	if not Availability.spend(state,research,int(card["research_needed"])&MASK,exempt) or not Availability.spend(state,int(card["id"]),1,exempt) or not Availability.acquire(state,completion,1,limits,events,exempt):
		log_(service,rules,"0x104a6510",[completion,int(card["id"])])
		log_(service,rules,"0x104a64b8")
		return false
	var notification: int=service.call("context",[])
	service.call("notice",[notification,9,card["name"]])
	context["cache_valid"]=false
	service.call("acquired",[completion])
	var happiness := str(int(card["happiness"]))
	if rules["happiness"].has(happiness): service.call("effect",[rules["happiness"][happiness],player,[0.0,0.0,0.0],0,0])
	return true
