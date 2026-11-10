extends RefCounted
## Read-only building queries and the same timing arithmetic used by World.

const Economy = preload("res://simulation/campaign_economy.gd")


static func belief_enabled(state: Dictionary) -> bool:
	if not state.has("progression"): return true
	var p: Dictionary=state["progression"]
	if p["rules"].get("source_unlocks",{}).has("GenerateBelief"):
		return preload("res://simulation/source_unlocks.gd").enabled(p,"GenerateBelief")
	return "Card_Spirituality" in p["completed"]


static func birth_interval(state: Dictionary,home: Dictionary) -> int:
	var ticks := maxi(1,roundi(float(home.get("birth_ticks",state.get("birth_ticks",100)))/float(state.get("runtime",{}).get("birth_rate",1.0))))
	for area: Dictionary in state.get("progression",{}).get("beautified",[]):
		if Vector2(home["x"],home["z"]).distance_to(Vector2(area["x"],area["z"]))<=float(area["radius"]):
			ticks=maxi(1,roundi(ticks/maxf(1,float(state["progression"]["rules"]["config"].get("maxBeautifyBeautyFactor",9)))))
			break
	return ticks


static func belief_interval(state: Dictionary) -> int:
	return maxi(1,roundi(20/float(state.get("runtime",{}).get("belief_rate",1.0))))


static func belief_per_cycle(home: Dictionary) -> float:
	return (1.0+float(home.get("belief_modifier",0)))*pow(float(home.get("belief_multiplier",1)),maxi(0,int(home["residents"])))


static func inspect(state: Dictionary,id: Variant,entity: String="home") -> Dictionary:
	var homes: Array=state.get("homes",[])
	if entity=="temple":
		for site: Dictionary in state.get("progression",{}).get("shrines",[]):
			if site["id"]!=str(id): continue
			var result := {"entity":"temple","id":site["id"],"kind":"shrine","complete":bool(site.get("complete",false)),"started":bool(site.get("started",false)),
				"progress":0.0,"occupants":0,"capacity":0,"belief":0,"builders":0,"builders_working":0,"build_capacity":int(site.get("build_capacity",1)),
				"repair_seconds":float(site.get("build_ticks",0))*0.1,"food_cost":int(site.get("food_cost",0)),"ore_cost":int(site.get("ore_cost",0)),
				"wheat":int(state.get("wheat",0)),"ore":int(state.get("ore",0)),"reward_card":site.get("card",""),"site_type":site.get("type",""),
				"title_key":site.get("title",""),"description_key":site.get("info_description","")}
			for home: Dictionary in homes:
				if home.get("kind","")=="shrine" and home.get("shrine_id","")==site["id"]:
					var work := inspect(state,int(home["id"]))
					for field: String in ["progress","repair_seconds","builders","builders_working","stalled"]: result[field]=work[field]
					break
			return result
		return {}
	if not id is int: return {}
	if entity=="settlement":
		if not state.has("progression"): return {}
		var item := Economy.settlement(state,id)
		if item.is_empty(): return {}
		var result := {"entity":entity,"id":id,"role":item["role"],"capacity":int(item["capacity"]),"occupants":0,"belief":0,"belief_capacity":0,"workers":0,"wheat":int(item["wheat"]),"ore":int(item["ore"]),"members":item["members"].size()}
		for home: Dictionary in homes:
			if not int(home["id"]) in item["members"]: continue
			result["occupants"]+=int(home["residents"])
			result["belief"]+=int(home["stored"])
			result["belief_capacity"]+=int(home.get("max_belief",30))
		for follower: Dictionary in state["followers"]:
			if int(follower.get("settlement_id",-1))==id and follower.has("workplace"): result["workers"]+=1
		return result
	if entity!="home": return {}
	for home: Dictionary in homes:
		if int(home["id"])!=id: continue
		var duration := int(home.get("build_ticks",state.get("build_ticks",60)))
		var result := {"entity":entity,"id":id,"kind":home.get("kind",""),"family":int(home.get("family",0)),"rank":int(home.get("rank",1)),"name":home.get("name",""),
			"complete":home["progress"]>=duration,"progress":float(home["progress"])/maxi(1,duration),"stalled":bool(home.get("stalled",false)),"occupants":int(home["residents"]),"capacity":int(home.get("capacity",2)),
			"belief":int(home["stored"]),"belief_capacity":int(home.get("max_belief",30)),"builders":0,"builders_working":0,"build_capacity":maxi(1,floori(float(home.get("build_capacity",1)))),"workers":0,"workers_working":0,
			"next_follower_seconds":-1.0,"full":int(home["residents"])>=int(home.get("capacity",2)),"belief_per_hour":0.0}
		for follower: Dictionary in state["followers"]:
			if int(follower["job"])==id:
				result["builders"]+=1
				if follower["state"]=="building": result["builders_working"]+=1
			if int(follower.get("workplace",-1))==id:
				result["workers"]+=1
				if follower["state"] in ["farming","mining"]: result["workers_working"]+=1
		if result["kind"] in ["farm","mine"]:
			result["harvest_size"]=int(home["max_belief"])
			result["harvest_progress"]=float(home.get("harvest_accumulator",0))
			result["harvest_per_second"]=Economy.harvest_rate(state,home)
			result["harvest_seconds"]=maxf(0,(float(result["harvest_size"])-float(result["harvest_progress"]))/float(result["harvest_per_second"])/int(result["workers_working"])) if result["workers_working"]>0 and result["complete"] and result["harvest_per_second"]>0 else -1.0
		elif result["kind"]=="shrine":
			result["occupants"]=0
			result["capacity"]=0
			var work := float(home.get("temple_work",float(home["progress"])*0.1))
			result["progress"]=clampf(work/maxf(0.1,duration*0.1),0,1)
			result["repair_seconds"]=maxf(0,duration*0.1-work)
			for shrine: Dictionary in state.get("progression",{}).get("shrines",[]):
				if shrine["id"]==home.get("shrine_id",""): result["reward_card"]=shrine["card"]; break
		elif result["kind"]=="":
			if result["complete"] and not result["full"] and int(home.get("breeder_count",1))>0:
				var interval := birth_interval(state,home)
				result["next_follower_seconds"]=(interval-int(state["tick"])%interval)*0.1
			if result["complete"] and belief_enabled(state) and result["occupants"]>0: result["belief_per_hour"]=belief_per_cycle(home)*36000.0/belief_interval(state)
		return result
	return {}
