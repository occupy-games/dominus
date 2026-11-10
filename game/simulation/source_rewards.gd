extends RefCounted
## Pure composition of original dispatch, queued collection and inventory writes.
## The caller supplies the shared source RNG and remaining domain services.

const Availability = preload("res://simulation/source_availability.gd")
const Dispatch = preload("res://simulation/source_reward_dispatch.gd")
const Queue = preload("res://simulation/source_reward_queue.gd")
const Research = preload("res://simulation/source_card_research.gd")
const Selection = preload("res://simulation/source_sticker_selection.gd")
const Catalog = preload("res://simulation/source_reward_catalog.gd")
const Era = preload("res://simulation/source_era.gd")
const Unlocks = preload("res://simulation/source_unlock_dispatch.gd")
const Temple = preload("res://simulation/source_temple_repair.gd")


class Context extends RefCounted:
	var state: Dictionary
	var records: Dictionary
	var rules: Dictionary
	var mode: int
	var service: Callable
	var observer: Callable
	var events: Array
	var player: int=0
	var random_word: Callable
	var claim_clock: Dictionary


	func selection_query(name: String,index: int,args: Array) -> Variant:
		match name:
			"era":
				if rules.has("era"):
					if not state["research_context"].has("period") and not state["research_context"].has("era"): state["research_context"]=Era.restore(state["research_context"])
					return Era.era(state["research_context"],rules["era"],route)
				return service.call("era",[])
			"card_complete": return Research.completed(state["availability"],records["cards"][index],rules["research"])
			"card_remaining": return Research.remaining(state["availability"],records["cards"][index],rules["research"])
			"acquired": return Availability.acquired(state["availability"],args[0])
			"owned": return Availability.owned(state["availability"],args[0])
		return null


	func route(name: String,args: Array) -> Variant:
		if name=="select_sticker" and rules.has("selection"):
			var kind: String=rules["selection"]["kinds"].get(Availability.key(int(args[0])),"")
			return Selection.select(kind,records["cards"],records["stickers"],rules["selection"],int(args[1]),random_word,selection_query)
		match name:
			"notification_context": return service.call("context",[])
			"unlock":
				if rules.has("unlock"):
					var id := preload("res://simulation/source_hash.gd").text(str(args[0]))
					return Unlocks.force_claim_(state["unlock_dispatch"],state["availability"],rules["unlock"],rules["availability"],id,int(claim_clock["seconds"]),claim_clock["millis"],route,events,rules["queue"]["exempt"])
			"grant_temple":
				return Dispatch.from_site(state["dispatch"],records,rules["dispatch"],int(args[0]),int(args[1]),int(args[2]),true,random_word,route)
			"unlocked":
				if rules.has("unlock"): return Unlocks.unlocked(state["unlock_dispatch"],preload("res://simulation/source_hash.gd").text(str(args[0])))
			"acquired":
				if rules.has("unlock"):
					# Context validated the shared state/rules/clock before any
					# inventory write. Internal research credits preserve them.
					Unlocks.claim_(state["unlock_dispatch"],rules["unlock"],int(args[0]),int(claim_clock["seconds"]),claim_clock["millis"],route)
					return true
			"grant":
				return Queue.admit(state["queue"],state["availability"],records,rules["queue"],rules["availability"],int(args[0]),1 if args[1] else 0,int(args[2]),int(args[3]),int(args[4]),mode,route,events)
			"pack_count","pack_index": return state["dispatch"][name]
			"card_acquired":
				if observer.is_valid(): observer.call(name,args.duplicate(true))
				return Availability.acquired(state["availability"],int(args[0]))
		if rules.has("research") and name in ["research_remaining","research_complete","research_credit","complete_card"]:
			var card := Queue.registered(records["cards"],int(args[0]))
			if card.is_empty(): return false if name!="research_remaining" else 0
			match name:
				"research_remaining": return Research.remaining(state["availability"],card,rules["research"])
				"research_complete": return Research.ready(state["availability"],card,rules["research"])
				"research_credit": return Research.assign(state["availability"],card,records["stickers"],int(args[1]),bool(int(args[2])&255),rules["research"],rules["availability"],events,route,rules["queue"]["exempt"])
				"complete_card": return Research.complete(state["availability"],card,state["research_context"],player,rules["research"],rules["availability"],events,route,rules["queue"]["exempt"])
		return service.call(name,args)


static func initial() -> Dictionary:
	return {"availability":Availability.initial(),"dispatch":{"stories_acquired":[],"pack_count":0,"pack_index":0},"queue":Queue.initial(),"research_context":{"cache_valid":false}}


static func prepare_catalog(state: Dictionary,source: Dictionary,special: Array,stories: Array=[]) -> Dictionary:
	if not valid(state) or not Catalog.valid_rules(source.get("rules")) or not Catalog.valid_input(source.get("records"),source.get("details")): return {}
	var records: Dictionary=source["records"].duplicate(true)
	records["special"]=special.duplicate(true)
	records["stories"]=stories.duplicate(true)
	# Validate the complete graph before registering any capacity.
	if not Queue.valid_records(records) or not Dispatch.valid_records(records): return {}
	var bound := Catalog.bind(state["availability"],records,source["details"],source["rules"])
	if bound.is_empty(): return {}
	var result: Dictionary=bound["records"]
	result["registry"]=bound["registry"]
	result["detail_registry"]=bound["details"]
	return result


static func prepare_unlocks(state: Dictionary,definition: Dictionary) -> bool:
	if not valid(state) or not Unlocks.valid_rules(definition.get("rules")) or not definition.get("dependencies") is Array: return false
	var prepared := Unlocks.prepare(definition["dependencies"])
	if prepared.is_empty(): return false
	state["unlock_dispatch"]=prepared
	return true


static func valid_clock(value: Variant) -> bool:
	return value is Dictionary and Unlocks.u32(value.get("seconds")) and Unlocks.valid_time(value.get("millis"))


static func claim_unlock(state: Dictionary,rules: Dictionary,id: int,clock_: Dictionary,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not rules.has("unlock") or not state.has("unlock_dispatch") or not valid_clock(clock_): return false
	return Unlocks.claim(state["unlock_dispatch"],rules["unlock"],id,int(clock_["seconds"]),clock_["millis"],service)


static func expire_unlocks(state: Dictionary,rules: Dictionary,clock_: Dictionary,force_rebuild: bool,service: Callable) -> bool:
	if not valid(state) or not valid_rules(rules) or not rules.has("unlock") or not state.has("unlock_dispatch") or not valid_clock(clock_): return false
	return Unlocks.expire(state["unlock_dispatch"],rules["unlock"],int(clock_["seconds"]),clock_["millis"],force_rebuild,service)


static func force_unlock(state: Dictionary,rules: Dictionary,id: int,clock_: Dictionary,service: Callable,events: Array) -> bool:
	if not valid(state) or not valid_rules(rules) or not rules.has("unlock") or not state.has("unlock_dispatch") or not valid_clock(clock_) or not Unlocks.u32(id) or not service.is_valid(): return false
	return Unlocks.force_claim_(state["unlock_dispatch"],state["availability"],rules["unlock"],rules["availability"],id,int(clock_["seconds"]),clock_["millis"],service,events,rules["queue"]["exempt"])


static func temple_pending(state: Dictionary,temple: Dictionary,records: Dictionary,rules: Dictionary,temple_rules: Dictionary,mode: int,random_word: Callable,service: Callable,events: Array) -> bool:
	if not Temple.valid(temple) or not Dispatch.u32(temple.get("reward")) or not Temple.valid_rules(temple_rules) or not random_word.is_valid() or not rules.has("unlock"): return false
	var bound := context(state,records,rules,mode,service,events,Callable())
	if bound==null: return false
	bound.random_word=random_word
	return Temple.dispatch_pending(temple,temple_rules,bound.route)


static func current_era(state: Dictionary,rules: Dictionary,service: Callable) -> int:
	if not valid(state) or not valid_rules(rules) or not rules.has("era") or not service.is_valid(): return 0
	if rules.has("unlock") and not state.has("unlock_dispatch"): return 0
	if not state.has("research_context"): state["research_context"]=Era.initial()
	elif not state["research_context"].has("period") and not state["research_context"].has("era"): state["research_context"]=Era.restore(state["research_context"])
	var query := func(name: String,args: Array) -> Variant:
		if name=="unlocked" and rules.has("unlock"): return Unlocks.unlocked(state["unlock_dispatch"],preload("res://simulation/source_hash.gd").text(str(args[0])))
		return service.call(name,args)
	return Era.era(state["research_context"],rules["era"],query)


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not Availability.valid(state.get("availability")) or not Dispatch.valid_state(state.get("dispatch")) or not Queue.valid(state.get("queue")): return false
	if state.has("unlock_dispatch") and not Unlocks.valid(state["unlock_dispatch"]): return false
	if not state.has("research_context"): return true
	var context_: Variant=state["research_context"]
	if not context_ is Dictionary or not context_.get("cache_valid") is bool: return false
	return Era.valid(context_) if context_.has("period") or context_.has("era") else true


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result := {"availability":Availability.restore(saved["availability"]),"dispatch":Dispatch.restore(saved["dispatch"]),"queue":Queue.restore(saved["queue"]),"research_context":saved.get("research_context",{"cache_valid":false}).duplicate(true)}
	if saved.has("unlock_dispatch"): result["unlock_dispatch"]=Unlocks.restore(saved["unlock_dispatch"])
	return result


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Availability.valid_rules(rules.get("availability")) or not Dispatch.valid_rules(rules.get("dispatch")) or not Queue.valid_rules(rules.get("queue")) or (rules.has("research") and not Research.valid_rules(rules["research"])): return false
	if rules.has("era") and not Era.valid_rules(rules["era"]): return false
	if rules.has("unlock") and not Unlocks.valid_rules(rules["unlock"]): return false
	if rules.has("selection"):
		if not rules.has("research") or not Selection.valid_rules(rules["selection"]) or not rules["selection"].get("kinds") is Dictionary: return false
		if rules["selection"]["kinds"].size()!=Selection.KINDS.size(): return false
		for kind: String in Selection.KINDS:
			if rules["selection"]["kinds"].get("@"+str(preload("res://simulation/source_hash.gd").text(kind)))!=kind: return false
	return true


static func context(state: Dictionary,records: Dictionary,rules: Dictionary,mode: int,service: Callable,events: Array,observer: Callable) -> Context:
	if not valid(state) or not valid_rules(rules) or not Queue.valid_records(records) or not Dispatch.valid_records(records) or not Dispatch.u32(mode) or not service.is_valid(): return null
	var clock_: Variant={}
	if rules.has("unlock"):
		if not state.has("unlock_dispatch"): return null
		clock_=service.call("claim_clock",[])
		if not valid_clock(clock_): return null
	if rules.has("research"):
		if not state.has("research_context"): return null
		for card: Dictionary in records["cards"]:
			if not Research.valid_card(card): return null
		for sticker: Dictionary in records["stickers"]:
			if not Research.valid_sticker(sticker): return null
	if rules.has("selection") and not Selection.valid_records(records["cards"],records["stickers"]): return null
	var result := Context.new()
	result.state=state
	result.records=records
	result.rules=rules
	result.mode=mode
	result.service=service
	result.events=events
	result.observer=observer
	result.claim_clock=clock_
	return result


static func request(state: Dictionary,records: Dictionary,rules: Dictionary,reward: int,source_id: int,flags: int,reason: int,override: int,mode: int,random_word: Callable,service: Callable,events: Array,observer: Callable=Callable()) -> bool:
	var bound := context(state,records,rules,mode,service,events,observer)
	if bound==null: return false
	bound.random_word=random_word
	return Dispatch.dispatch(state["dispatch"],records,rules["dispatch"],reward,source_id,flags,reason,override,random_word,bound.route)


static func from_site(state: Dictionary,records: Dictionary,rules: Dictionary,reward: int,source_id: int,flags: int,is_temple: bool,mode: int,random_word: Callable,service: Callable,events: Array,observer: Callable=Callable()) -> bool:
	var bound := context(state,records,rules,mode,service,events,observer)
	if bound==null: return false
	bound.random_word=random_word
	return Dispatch.from_site(state["dispatch"],records,rules["dispatch"],reward,source_id,flags,is_temple,random_word,bound.route)


static func take(state: Dictionary,rules: Dictionary,kind: int,reason: int,mode: int,population: float,service: Callable) -> Dictionary:
	if not valid(state) or not valid_rules(rules): return {}
	return Queue.take(state["queue"],rules["queue"],kind,reason,mode,population,service)


static func consume(state: Dictionary,records: Dictionary,rules: Dictionary,mode: int,player: int,random_word: Callable,service: Callable,events: Array) -> bool:
	if not valid(state) or not valid_rules(rules): return false
	if rules.has("research") or rules.has("unlock"):
		var bound := context(state,records,rules,mode,service,events,Callable())
		if bound==null: return false
		bound.player=player
		bound.random_word=random_word
		return Queue.consume(state["queue"],state["availability"],records,rules["queue"],rules["availability"],mode,player,random_word,bound.route,events)
	return Queue.consume(state["queue"],state["availability"],records,rules["queue"],rules["availability"],mode,player,random_word,service,events)


static func assign_card(state: Dictionary,records: Dictionary,rules: Dictionary,card_id: int,sticker_id: int,allow_internal: bool,service: Callable,events: Array) -> bool:
	var bound := context(state,records,rules,0,service,events,Callable())
	if bound==null or not rules.has("research") or not Dispatch.u32(card_id) or not Dispatch.u32(sticker_id): return false
	return bool(bound.route("research_credit",[card_id,sticker_id,int(allow_internal)]))


static func complete_card(state: Dictionary,records: Dictionary,rules: Dictionary,card_id: int,player: int,service: Callable,events: Array) -> bool:
	var bound := context(state,records,rules,0,service,events,Callable())
	if bound==null or not rules.has("research") or not Dispatch.u32(card_id) or player<0 or player>7: return false
	bound.player=player
	return bool(bound.route("complete_card",[card_id]))
