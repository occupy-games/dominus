extends RefCounted
## Durable reward entitlements; replaying/loading cannot re-award a threshold.


static func empty() -> Dictionary:
	return {"version":2,"missions":{},"claimed":{},"earned":{},"last_awards":[]}


static func needed(home: Dictionary, rules: Dictionary) -> Dictionary:
	var result := {}
	var p: Dictionary = home.get("progression",{})
	for id: String in p.get("rules",{}).get("cards",{}):
		if id in p.get("completed",[]): continue
		var research: Dictionary = p["rules"].get("research_cards",{}).get(id,{})
		if not research.is_empty():
			var remaining := int(research["research_needed"])-int(p.get("research",{}).get(id,0))
			if remaining<=0: continue
			for sticker: String in rules.get("stickers",{}):
				if int(rules["stickers"][sticker].get("contributions",{}).get(research["research_type"],0))>0: result[sticker]=true
			continue
		for resource: String in p["rules"]["cards"][id]["requirements"]:
			if int(p["inventory"].get(resource,0))<int(p["rules"]["cards"][id]["requirements"][resource]): result[rules.get("aliases",{}).get(resource,resource)]=true
	return result


static func draw(rules: Dictionary, era: int, random: RandomNumberGenerator, needed: Dictionary, kind: String = "Reward_EventSticker") -> String:
	var config: Dictionary = rules.get("config",{})
	var fixed_era := {"Reward_PrimitiveSticker":1,"Reward_BronzeSticker":2,"Reward_IronSticker":3,"Reward_FrontierSticker":4}
	var chosen_era := int(fixed_era.get(kind,era))
	if not fixed_era.has(kind):
		var weights := [int(config.get("StickerChance_OldBeads_Event",1000)),int(config.get("StickerChance_CurrentBeads_Event",8000)),int(config.get("StickerChance_NewBeads_Event",1000))]
		var roll := random.randi_range(0,maxi(1,weights[0]+weights[1]+weights[2])-1)
		chosen_era=clampi(era+(-1 if roll<weights[0] else (0 if roll<weights[0]+weights[1] else 1)),1,4)
	var pool: Array[String] = []
	var useful: Array[String] = []
	for id: String in rules.get("stickers",{}):
		var sticker: Dictionary = rules["stickers"][id]
		if int(sticker["era"])!=chosen_era or sticker["internal"] or id.begins_with("Sticker_Rare_") or id=="Sticker_Gem_1": continue
		pool.append(id)
		if needed.has(id): useful.append(id)
	pool.sort()
	useful.sort()
	if random.randf()>=float(config.get("StickerChance_TotallyRandomPcnt",0.5)) and not useful.is_empty(): pool=useful
	return pool[random.randi_range(0,pool.size()-1)] if not pool.is_empty() else ""


static func grant(profile: Dictionary, id: String, count: int, rules: Dictionary, random: RandomNumberGenerator, era: int, needed: Dictionary) -> void:
	if count<=0: return
	if rules.get("packs",{}).has(id):
		for reward: Dictionary in rules["packs"][id]: grant(profile,reward["id"],int(reward["count"])*count,rules,random,era,needed)
		return
	if id.begins_with("Reward_"):
		for index in range(count):
			var chosen := draw(rules,era,random,needed,id)
			if not chosen.is_empty(): grant(profile,chosen,1,rules,random,era,needed)
		return
	if not rules.get("stickers",{}).has(id) and not rules.get("cards",{}).has(id): return
	profile["earned"][id]=int(profile["earned"].get(id,0))+count
	profile["last_awards"].append({"id":id,"count":count})


static func record(previous: Dictionary, state: Dictionary, rules: Dictionary, random: RandomNumberGenerator, era: int = 1, needed: Dictionary = {}) -> Dictionary:
	var profile := previous.duplicate(true) if previous.get("version")==2 else empty()
	profile["last_awards"]=[]
	if not state.has("voyage") or state["voyage"]["phase"]!="won": return profile
	var voyage: Dictionary = state["voyage"]
	var definition: Dictionary = voyage["definition"]
	if str(profile.get("rng_state","")).is_valid_int(): random.state=int(profile["rng_state"])
	var id: String = definition["id"]
	var before: Dictionary = profile["missions"].get(id,{})
	profile["missions"][id]={"stars":maxi(int(before.get("stars",0)),int(voyage["stars"])),"score":maxi(int(before.get("score",0)),int(voyage["score"])),"rescued":maxi(int(before.get("rescued",0)),int(voyage["rescued"]))}
	var family: String = definition["family"]
	var score := 0
	for mission_id: String in profile["missions"]:
		if mission_id.begins_with(family+"__"): score+=int(profile["missions"][mission_id]["score"])
	var track: Dictionary = rules.get("reward_tracks",{}).get(family,{})
	for reward: Dictionary in track.get("rewards",[]):
		var key := family+":"+str(int(reward["score"]))
		if score<int(reward["score"]) or profile["claimed"].has(key): continue
		grant(profile,reward["id"],int(reward["count"]),rules,random,era,needed)
		profile["claimed"][key]=true
	# Older authored voyages carry per-star rewards instead of a score track.
	if track.is_empty():
		for index in range(int(voyage["stars"])):
			var key := id+":star:"+str(index+1)
			if profile["claimed"].has(key): continue
			for reward: Dictionary in definition.get("rewards",[]):
				if int(reward["star"])==index+1: grant(profile,reward["id"],int(reward["count"]),rules,random,era,needed)
			profile["claimed"][key]=true
	profile["rng_state"]=str(random.state)
	return profile


static func transfer(state: Dictionary, profile: Dictionary, rules: Dictionary) -> Dictionary:
	if not state.has("progression") or state.has("voyage"): return {"ok":false,"count":0}
	var redeemed: Dictionary = state.get("voyage_redeemed",{}).duplicate(true)
	var p: Dictionary = state["progression"]
	var count := 0
	for id: String in profile.get("earned",{}):
		var amount := maxi(0,int(profile["earned"][id])-int(redeemed.get(id,0)))
		if amount==0: continue
		if rules.get("cards",{}).has(id):
			var card: Dictionary = rules["cards"][id]
			for resource: String in ["belief","gems","wheat","ore"]:
				if int(card.get(resource,0))>0: state[resource]=int(state.get(resource,0))+int(card[resource])*amount
		elif id=="Sticker_Gem_1": state["gems"]=int(state.get("gems",0))+amount
		elif rules.get("stickers",{}).has(id): p["inventory"][id]=int(p["inventory"].get(id,0))+amount
		else: continue
		redeemed[id]=int(profile["earned"][id])
		count+=amount
	state["voyage_redeemed"]=redeemed
	if count>0: p["revision"]+=1
	return {"ok":true,"count":count}
