extends RefCounted
## Original 0x10050930: story selection, five-slot recursive packs, direct
## card/sticker routing and random selectors. The final credit service is
## separate; callbacks must be simulation services, never UI or asset access.

const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const MASK := 4294967295


static func u32(value: Variant) -> bool:
	return Numbers.integer_between(value,0,MASK)


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for field: String in ["next_story","random_side_story","random_story","fallback","event_reward","chest_reason","temple_reason","discovery_type","story_priority_limit"]:
		if not u32(rules.get(field)): return false
	if not (rules.get("story_chance") is int or rules.get("story_chance") is float) or not is_finite(float(rules["story_chance"])) or float(rules["story_chance"])<0 or float(rules["story_chance"])>1: return false
	if not (rules.get("random_divisor") is int or rules.get("random_divisor") is float) or float(rules["random_divisor"])<=0 or not is_finite(float(rules["random_divisor"])): return false
	if not rules.get("sticker_selectors") is Array or rules["sticker_selectors"].size()!=11: return false
	for id: Variant in rules["sticker_selectors"]:
		if not u32(id): return false
	return true


static func valid_state(state: Variant) -> bool:
	if not state is Dictionary or not state.get("stories_acquired") is Array or state["stories_acquired"].size()>1024: return false
	var found := {}
	for id: Variant in state["stories_acquired"]:
		if not u32(id) or found.has(int(id)): return false
		found[int(id)]=true
	return Numbers.integer_between(state.get("pack_count"),-2147483648,2147483647) and u32(state.get("pack_index"))


static func restore(saved: Variant) -> Dictionary:
	if not valid_state(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	for i in range(result["stories_acquired"].size()): result["stories_acquired"][i]=int(result["stories_acquired"][i])
	result["pack_count"]=int(result["pack_count"])
	result["pack_index"]=int(result["pack_index"])
	return result


static func valid_records(records: Variant) -> bool:
	if not records is Dictionary: return false
	for group: String in ["stories","packs","cards","stickers"]:
		var capacity := 32 if group=="stories" else (256 if group in ["cards","stickers"] else 1024)
		if not records.get(group) is Array or records[group].size()>capacity: return false
		var ids := {}
		for entry: Variant in records[group]:
			if not entry is Dictionary or not u32(entry.get("id")): return false
			# Source card/sticker arrays can repeat IDs. Ordered scans retain every
			# row; the registry resolves the last registered row. Packs are unique.
			if group=="packs" and ids.has(int(entry["id"])): return false
			ids[int(entry["id"])]=true
			if group=="stories":
				for field: String in ["essential","order"]:
					if not Numbers.integer_between(entry.get(field),-2147483648,2147483647): return false
			if group=="cards":
				for field: String in ["type","silent"]:
					if not u32(entry.get(field)): return false
			if group=="packs":
				if not entry.get("slots") is Array or entry["slots"].size()!=5: return false
				for slot: Variant in entry["slots"]:
					if not slot is Dictionary or not Numbers.integer_between(slot.get("count"),-2147483648,2147483647) or not u32(slot.get("reward")): return false
	# Reject recursive/unbounded supplied definitions before any grant or RNG.
	var packs := index(records["packs"])
	var memo := {}
	for id: int in packs:
		if calls(packs,id,[],memo)<0: return false
	return true


static func index(entries: Array) -> Dictionary:
	var result := {}
	for entry: Dictionary in entries: result[int(entry["id"])]=entry
	return result


static func calls(packs: Dictionary,id: int,path: Array,memo: Dictionary) -> int:
	if not packs.has(id): return 1
	if id in path or path.size()>=32: return -1
	if memo.has(id): return int(memo[id])
	var nested := path.duplicate()
	nested.append(id)
	var count := 1
	for slot: Dictionary in packs[id]["slots"]:
		if int(slot["count"])<=0: continue
		var child := calls(packs,int(slot["reward"]),nested,memo)
		if child<0: return -1
		count+=child*int(slot["count"])
		if count>100000: return -1
	memo[id]=count
	return count


static func story(state: Dictionary,id: int,service: Callable) -> void:
	if not id in state["stories_acquired"]: state["stories_acquired"].append(id)
	service.call("story",[id])


static func dispatch(state: Dictionary,records: Dictionary,rules: Dictionary,reward: int,source_id: int,flags: int,reason: int,override: int,random_word: Callable,service: Callable) -> bool:
	if not valid_state(state) or not valid_records(records) or not valid_rules(rules) or not random_word.is_valid() or not service.is_valid(): return false
	for value: int in [reward,source_id,flags,reason,override]:
		if not u32(value): return false
	var tables := {}
	for group: String in ["stories","packs","cards","stickers"]: tables[group]=index(records[group])
	apply(state,records,tables,rules,reward,source_id,flags,reason,override,random_word,service)
	return true


static func apply(state: Dictionary,records: Dictionary,tables: Dictionary,rules: Dictionary,reward: int,source_id: int,flags: int,reason: int,override: int,random_word: Callable,service: Callable) -> void:
	var side_story := reward==int(rules["random_side_story"])
	if reward==int(rules["next_story"]):
		var selected := -1
		var priority := int(rules["story_priority_limit"])
		for entry: Dictionary in records["stories"]:
			if int(entry["id"]) in state["stories_acquired"] or int(entry["order"])<=0 or int(entry["order"])>=priority: continue
			selected=int(entry["id"])
			priority=int(entry["order"])
		if selected<0: side_story=true
		else: story(state,selected,service)
	if reward==int(rules["random_story"]) or side_story:
		var chance := 0.0 if side_story else Terrain.f32(float(rules["story_chance"]))
		var candidates: Array=[]
		for entry: Dictionary in records["stories"]:
			var id := int(entry["id"])
			if int(entry["essential"])==0 and not id in state["stories_acquired"] and not id in candidates: candidates.append(id)
		candidates.sort() # Native std::set orders by unsigned source hash.
		var roll := Terrain.f32(float(int(random_word.call()))/float(rules["random_divisor"]))
		var selected := false
		if chance>roll and candidates.size()<records["stories"].size():
			for entry: Dictionary in records["stories"]:
				if int(entry["essential"])!=0 and not int(entry["id"]) in state["stories_acquired"]:
					story(state,int(entry["id"]),service)
					selected=true
					break
		if chance<=roll or not selected:
			if not candidates.is_empty():
				var position := (((int(random_word.call())&32767)*candidates.size())&MASK)>>15
				story(state,int(candidates[position]),service)
			else: reward=int(rules["fallback"])
	if tables["stories"].has(reward): story(state,reward,service)
	var packs: Dictionary=tables["packs"]
	if packs.has(reward):
		for slot: Dictionary in packs[reward]["slots"]:
			state["pack_count"]=int(slot["count"])
			for i in range(maxi(0,int(slot["count"]))):
				state["pack_index"]=i
				apply(state,records,tables,rules,int(slot["reward"]),source_id,flags,reason,override,random_word,service)
		state["pack_count"]=0
		state["pack_index"]=0
	var cards: Dictionary=tables["cards"]
	if cards.has(reward):
		var card: Dictionary=cards[reward]
		if int(card["silent"])==2 or (int(card["silent"])==1 and int(service.call("card_acquired",[reward]))!=0): flags|=2
		if int(card["type"])==1: flags|=16
		service.call("grant",[reward,false,flags,reason,source_id])
	var stickers: Dictionary=tables["stickers"]
	if stickers.has(reward): service.call("grant",[reward,true,flags,reason,source_id])
	var sticker_selector := false
	for id: Variant in rules["sticker_selectors"]:
		if reward==int(id): sticker_selector=true; break
	if sticker_selector:
		var selected := int(service.call("select_sticker",[reward,override]))&MASK
		service.call("grant",[selected,stickers.has(selected),flags,reason,source_id])
	if reward==int(rules["event_reward"]):
		var selected := int(service.call("select_event_reward",[]))&MASK
		service.call("grant",[selected,false,flags,reason,source_id])


static func from_site(state: Dictionary,records: Dictionary,rules: Dictionary,reward: int,source_id: int,flags: int,is_temple: bool,random_word: Callable,service: Callable) -> bool:
	if not dispatch(state,records,rules,reward,source_id,flags,int(rules.get("temple_reason",0) if is_temple else rules.get("chest_reason",0)),0,random_word,service): return false
	service.call("refresh",[])
	return true
