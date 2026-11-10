extends RefCounted
## Original reward admission, collection and stack consumption. All callbacks
## are simulation services; display flags never let a renderer grant inventory.

const Availability = preload("res://simulation/source_availability.gd")
const Dispatch = preload("res://simulation/source_reward_dispatch.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const MASK := 4294967295


static func initial() -> Dictionary:
	return {"queue":[],"delay":0.0,"gems":0,"deferred":{"belief":[0,0],"wheat":[0,0],"ore":[0,0]},"totem_capacity":[0,0,0,0,0,0,0,0],"win_name":""}


static func finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary or not Dispatch.u32(rules.get("gem_sticker")) or not rules.get("strings") is Dictionary: return false
	for field: String in ["auto_claim","delay","totem_upgrade"]:
		if not finite(rules.get(field)): return false
	if float(rules["delay"])<0 or absf(float(rules["totem_upgrade"]))>2147483520.0: return false
	for field: String in ["actions","exempt"]:
		if not rules.get(field) is Array or rules[field].size()>50: return false
		for id: Variant in rules[field]:
			if not Dispatch.u32(id): return false
	if rules["actions"].size()!=3: return false
	if not rules.get("internal_stickers") is Array or rules["internal_stickers"].size()!=6: return false
	for id: Variant in rules["internal_stickers"]:
		if not Dispatch.u32(id): return false
	for address: String in ["0x104ac880","0x104ac864","0x104ac844","0x104ac814","0x104ac7ec","0x104ac7b8","0x104ac770","0x104ac740","0x104ac728","0x104ac6fc","0x104ac95c","0x104ac94c","0x104ac93c"]:
		if not rules["strings"].get(address) is String: return false
	return true


static func valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("taken") is bool or not entry.get("display") is bool: return false
	for field: String in ["kind","reason","source_id","reward","flags"]:
		if not Dispatch.u32(entry.get(field)): return false
	return true


static func valid(state: Variant) -> bool:
	if not state is Dictionary or not state.get("queue") is Array or state["queue"].size()>100000 or not finite(state.get("delay")) or Terrain.f32(float(state["delay"]))!=float(state["delay"]) or not Dispatch.u32(state.get("gems")): return false
	for entry: Variant in state["queue"]:
		if not valid_entry(entry): return false
	if not state.get("deferred") is Dictionary: return false
	for field: String in ["belief","wheat","ore"]:
		var words: Variant=state["deferred"].get(field)
		if not words is Array or words.size()!=2 or not Dispatch.u32(words[0]) or not Dispatch.u32(words[1]): return false
	if not state.get("totem_capacity") is Array or state["totem_capacity"].size()!=8: return false
	for value: Variant in state["totem_capacity"]:
		if not Dispatch.u32(value): return false
	return state.get("win_name") is String and state["win_name"].length()<=1024 and not state["win_name"].to_utf8_buffer().has(0)


static func restore(saved: Variant) -> Dictionary:
	if not valid(saved): return {}
	var result: Dictionary=saved.duplicate(true)
	result["delay"]=float(result["delay"])
	result["gems"]=int(result["gems"])
	for entry: Dictionary in result["queue"]:
		for field: String in ["kind","reason","source_id","reward","flags"]: entry[field]=int(entry[field])
	for field: String in ["belief","wheat","ore"]:
		for i in range(2): result["deferred"][field][i]=int(result["deferred"][field][i])
	for i in range(8): result["totem_capacity"][i]=int(result["totem_capacity"][i])
	return result


static func valid_records(records: Variant) -> bool:
	if not records is Dictionary: return false
	for group: String in ["cards","stickers","special"]:
		if not records.get(group) is Array or records[group].size()>256: return false
		for row: Variant in records[group]:
			if not row is Dictionary or not Dispatch.u32(row.get("id")): return false
			if group=="cards":
				if not Dispatch.u32(row.get("type")) or not Dispatch.u32(row.get("category")) or not Numbers.integer_between(row.get("research_needed"),-2147483648,2147483647): return false
			if group=="special":
				for field: String in ["gems","belief","wheat","ore","followers","role"]:
					if not Numbers.integer_between(row.get(field),-2147483648,2147483647): return false
				if not Dispatch.u32(row.get("extra")): return false
	return true


static func find(records: Array,id: int) -> Dictionary:
	for row: Dictionary in records:
		if int(row["id"])==id: return row
	return {}


static func registered(records: Array,id: int) -> Dictionary:
	for index in range(records.size()-1,-1,-1):
		if int(records[index]["id"])==id: return records[index]
	return {}


static func log_(service: Callable,rules: Dictionary,address: String,channel: int,args: Array=[]) -> void:
	service.call("log",[channel,rules["strings"][address],args])


static func add_signed(words: Array,value: int) -> void:
	var previous := int(words[0])
	words[0]=(previous+(value&MASK))&MASK
	words[1]=(int(words[1])+(-1 if value<0 else 0)+(1 if int(words[0])<previous else 0))&MASK


static func gems(state: Dictionary,amount: int,description: String,source_id: int,service: Callable) -> void:
	service.call("context",[])
	service.call("gem_credit",[amount,4,description,source_id,0])
	state["gems"]=(int(state["gems"])+amount)&MASK


static func admit(state: Dictionary,availability: Dictionary,records: Dictionary,rules: Dictionary,limits: Dictionary,reward: int,kind: int,flags: int,reason: int,source_id: int,mode: int,service: Callable,events: Array) -> bool:
	if not valid(state) or not Availability.valid(availability) or not valid_records(records) or not valid_rules(rules) or not Availability.valid_rules(limits) or not service.is_valid(): return false
	for value: int in [reward,kind,flags,reason,source_id,mode]:
		if not Dispatch.u32(value): return false
	if mode==3: return false
	var sticker := registered(records["stickers"],reward)
	if reward==0 or (kind==0 and registered(records["cards"],reward).is_empty()) or (kind==1 and sticker.is_empty()):
		log_(service,rules,"0x104ac6fc",28)
		return false
	var queued := 1
	for entry: Dictionary in state["queue"]:
		if int(entry["reward"])==reward: queued+=1
	if not Availability.can_acquire(availability,reward,queued,limits,events):
		log_(service,rules,"0x104ac880",28)
		return false
	var entry := {"kind":kind,"reason":reason,"source_id":source_id,"reward":reward,"flags":flags,"taken":bool(flags&2),"display":not bool(flags&16)}
	if kind==0:
		var card := registered(records["cards"],reward)
		if int(card["type"])==2 and int(card["research_needed"])<=0: entry["flags"]=flags|1
	var special := find(records["special"],reward)
	if not special.is_empty() and not bool(int(entry["flags"])&12):
		if int(special["gems"])!=0:
			gems(state,int(special["gems"]),str(rules["strings"]["0x104ac864"]).replace("%i","%d")%signed(mode),MASK,service)
		var changed := false
		for field: String in ["belief","wheat","ore"]:
			var value := int(special[field])
			if value==0: continue
			if mode!=0: add_signed(state["deferred"][field],value)
			else:
				service.call("currency",[field,Terrain.f32(float(value))])
				if field=="belief": service.call("context",[])
				changed=true
		if int(special["extra"])==int(rules["actions"][2]): service.call("revive_explorers",[])
		if changed: service.call("refresh",[])
	elif kind==1 and reward==int(rules["gem_sticker"]) and not bool(int(entry["flags"])&12):
		var description := str(rules["strings"]["0x104ac844"]).replace("%i","%d")%signed(mode)
		var source := source_id
		if reason!=7:
			log_(service,rules,"0x104ac814",55)
			source=MASK
		else: log_(service,rules,"0x104ac7ec",55,[signed(source)])
		var count := int(service.call("pack_count",[]))
		if count>0:
			if int(service.call("pack_index",[]))==0:
				log_(service,rules,"0x104ac7b8",55,[count])
				gems(state,count,description,MASK if source==0 else source,service)
			else: log_(service,rules,"0x104ac770",55)
		else:
			log_(service,rules,"0x104ac740",55)
			gems(state,1,description,MASK if source==0 else source,service)
	log_(service,rules,"0x104ac728",5)
	state["queue"].append(entry)
	service.call("changed",[])
	return true


static func signed(value: int) -> int:
	return value if value<2147483648 else value-4294967296


static func select(state: Dictionary,rules: Dictionary,kind: int,reason: int,mode: int,population: float,service: Callable) -> int:
	if float(state["delay"])<Terrain.f32(float(rules["delay"])) or state["queue"].is_empty() or mode==3: return -1
	var restricted := mode==1 and int(service.call("mission_type",[]))==0
	for i in range(state["queue"].size()):
		var entry: Dictionary=state["queue"][i]
		if int(entry["kind"])!=kind or bool(int(entry["flags"])&2) or (int(entry["reason"])!=2 and restricted): continue
		if reason==4 and Terrain.f32(population)<float(entry["source_id"]): continue
		if reason!=12 and int(entry["reason"])!=reason: continue
		if not entry["taken"]: return i
	return -1


static func take(state: Dictionary,rules: Dictionary,kind: int,reason: int,mode: int,population: float,service: Callable) -> Dictionary:
	var result := {"kind":0,"reason":10,"source_id":0,"reward":0,"flags":0,"taken":true,"display":true}
	if not valid(state) or not valid_rules(rules) or not service.is_valid() or not finite(population): return {}
	for value: int in [kind,reason,mode]:
		if not Dispatch.u32(value): return {}
	var selected := select(state,rules,kind,reason,mode,population,service)
	if selected>=0:
		state["queue"][selected]["taken"]=true
		result=state["queue"][selected].duplicate(true)
	# Preserve the original repeated query boundaries in fast-card mode.
	if float(rules["auto_claim"])>0 and select(state,rules,kind,reason,mode,population,service)>=0:
		while true:
			selected=select(state,rules,kind,reason,mode,population,service)
			state["queue"][selected]["taken"]=true
			if select(state,rules,kind,reason,mode,population,service)<0: break
	return result


static func consume(state: Dictionary,availability: Dictionary,records: Dictionary,rules: Dictionary,limits: Dictionary,mode: int,player: int,random_word: Callable,service: Callable,events: Array) -> bool:
	if not valid(state) or not Availability.valid(availability) or not valid_records(records) or not valid_rules(rules) or not Availability.valid_rules(limits) or not service.is_valid() or not random_word.is_valid() or not Dispatch.u32(mode) or player<0 or player>7: return false
	if state["queue"].is_empty() or mode==3: return false
	var entry: Dictionary=state["queue"][-1].duplicate(true)
	if not entry["taken"]: return false
	var reward := int(entry["reward"])
	var flags := int(entry["flags"])
	log_(service,rules,"0x104ac95c",5,[reward])
	state["queue"].pop_back()
	if bool(flags&8) or not Availability.acquire(availability,reward,1,limits,events,rules["exempt"]): return true
	service.call("acquired",[reward])
	var kind := int(entry["kind"])
	if kind==0:
		var card := registered(records["cards"],reward)
		if not card.is_empty() and int(card["type"])==2:
			if bool(flags&1):
				var remaining := int(service.call("research_remaining",[reward]))
				var category := int(card["category"])
				var internal := int(rules["internal_stickers"][category]) if category<6 else 0
				for i in range(remaining):
					service.call("acquired",[internal])
					Availability.acquire(availability,internal,1,limits,events,rules["exempt"])
					service.call("research_credit",[reward,internal,1])
			if bool(service.call("research_complete",[reward])): service.call("complete_card",[reward])
		if bool(flags&4): Availability.spend(availability,reward,1,rules["exempt"])
	elif kind==1:
		var sticker := registered(records["stickers"],reward)
		if bool(flags&4) or (not sticker.is_empty() and reward==int(rules["gem_sticker"])): Availability.spend(availability,reward,1,rules["exempt"])
	if bool(flags&4): Availability.spend(availability,reward,1,rules["exempt"])
	var special := find(records["special"],reward)
	if not special.is_empty() and not bool(flags&12):
		if int(special["followers"])!=0:
			var context: Dictionary=service.call("mission_spawn",[])
			var seed_flag := ((int(random_word.call())&32767)*2)&32768
			service.call("spawn_followers",[context["position"].duplicate(),0,seed_flag,int(special["followers"]),1,0,context["extra"].duplicate()])
		var extra := int(special["extra"])
		if extra==int(rules["actions"][0]):
			service.call("win_name",[state["win_name"]])
			state["win_name"]=""
		elif extra==int(rules["actions"][1]):
			service.call("totem_upgrade",[player])
			state["totem_capacity"][player]=(int(state["totem_capacity"][player])+int(Terrain.f32(float(rules["totem_upgrade"]))))&MASK
	service.call("hook",[rules["strings"]["0x104ac94c"] if kind==0 else rules["strings"]["0x104ac93c"],reward])
	return true
