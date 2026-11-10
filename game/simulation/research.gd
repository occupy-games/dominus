extends RefCounted
## Typed source sticker contributions. No assets, scenes or storage services.


static func definition(p: Dictionary,id: String) -> Dictionary:
	return p["rules"].get("research_cards",{}).get(id,{})


static func points(p: Dictionary,id: String) -> int:
	return int(p.get("research",{}).get(id,0))


static func sources(p: Dictionary,sticker: String) -> Array:
	var result: Array = [sticker]
	var aliases: Dictionary = p["rules"].get("sticker_aliases",{})
	var keys := aliases.keys()
	keys.sort()
	for id: String in keys:
		if aliases[id]==sticker and id!=sticker: result.append(id)
	return result


static func stock(p: Dictionary,sticker: String) -> int:
	var result := 0
	for id: String in sources(p,sticker): result+=int(p["inventory"].get(id,0))
	return result


static func canonical(p: Dictionary,resource: String) -> String:
	return str(p["rules"].get("sticker_aliases",{}).get(resource,resource))


static func remaining(p: Dictionary,id: String) -> Dictionary:
	var result := {}
	var assigned: Dictionary=p.get("assigned_resources",{}).get(id,{})
	for resource: String in p["rules"]["cards"][id]["requirements"]:
		result[resource]=maxi(0,int(p["rules"]["cards"][id]["requirements"][resource])-int(assigned.get(resource,0)))
	return result


static func status(p: Dictionary,id: String) -> Dictionary:
	var card := definition(p,id)
	var total := int(card.get("research_needed",0))
	var filled := points(p,id)
	if card.is_empty():
		filled=0
		for resource: String in p["rules"]["cards"][id]["requirements"]:
			var count := int(p["rules"]["cards"][id]["requirements"][resource])
			total+=count
			filled+=mini(count,int(p.get("assigned_resources",{}).get(id,{}).get(resource,0)))
	if id in p["completed"]: filled=total
	return {"filled":filled,"total":total,"complete":id in p["completed"]}


static func inspect(p: Dictionary,command: Dictionary) -> Dictionary:
	var reject := {"ok":false,"cost":0,"reason":""}
	var id: String = command.get("card","")
	var card := definition(p,id)
	if not id in p["discovered"] or id in p["completed"]: return reject
	if card.is_empty():
		if command.get("type")!="research_card": return reject
		var sticker := canonical(p,str(command.get("sticker","")))
		if stock(p,sticker)<=0: return reject
		var needed := remaining(p,id)
		for resource: String in needed:
			if int(needed[resource])>0 and canonical(p,resource)==sticker:
				var progress := status(p,id)
				return {"ok":true,"cost":0,"reason":"","resource":resource,"points":1,"progress":float(int(progress["filled"])+1)/maxi(1,int(progress["total"]))}
		return reject
	var needed := int(card["research_needed"])
	var current := points(p,id)
	if command.get("type")=="claim_card": return {"ok":current>=needed,"cost":0,"reason":p["rules"]["cards"][id]["title"]}
	var sticker := canonical(p,str(command.get("sticker","")))
	var value := int(p["rules"].get("stickers",{}).get(sticker,{}).get("contributions",{}).get(card["research_type"],0))
	if value<=0 or stock(p,sticker)<=0 or current>=needed: return reject
	return {"ok":true,"cost":0,"reason":"","points":value,"progress":minf(1,float(current+value)/maxi(1,needed))}


static func apply(p: Dictionary,command: Dictionary) -> bool:
	var id: String = command["card"]
	var sticker := canonical(p,str(command["sticker"]))
	var card := definition(p,id)
	var plan := inspect(p,command)
	if not plan.get("ok",false): return false
	for resource: String in sources(p,sticker):
		if int(p["inventory"].get(resource,0))<=0: continue
		p["inventory"][resource]-=1
		break
	if not p.has("assigned_resources"): p["assigned_resources"]={}
	if not p["assigned_resources"].has(id): p["assigned_resources"][id]={}
	var assigned: Dictionary=p["assigned_resources"][id]
	var key := str(plan.get("resource",sticker))
	assigned[key]=int(assigned.get(key,0))+1
	p["revision"]+=1
	if card.is_empty():
		for needed: int in remaining(p,id).values():
			if needed>0: return false
		return true
	var value := int(p["rules"]["stickers"][sticker]["contributions"].get(card["research_type"],0))
	if not p.has("research"): p["research"]={}
	p["research"][id]=mini(int(card["research_needed"]),points(p,id)+value)
	return points(p,id)>=int(card["research_needed"])


static func valid(p: Dictionary) -> bool:
	if not p.get("research",{}) is Dictionary: return false
	for id: Variant in p.get("research",{}):
		var value: Variant = p["research"][id]
		if not id is String or not p["rules"].get("research_cards",{}).has(id): return false
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value!=int(value) or value>int(definition(p,id)["research_needed"]): return false
	if not p.get("assigned_resources",{}) is Dictionary: return false
	for id: Variant in p.get("assigned_resources",{}):
		if not id is String or not id in p["discovered"] or not p["rules"]["cards"].has(id) or not p["assigned_resources"][id] is Dictionary: return false
		for resource: Variant in p["assigned_resources"][id]:
			var count: Variant=p["assigned_resources"][id][resource]
			if not resource is String or not (count is int or count is float) or not is_finite(float(count)) or count<0 or count!=int(count) or count>1000000: return false
			if definition(p,id).is_empty():
				# Live CSV edits may remove a requirement after its resource was
				# assigned. Retain that spent history; it grants no new progress.
				if not p["rules"]["cards"].has(resource) or int(p["rules"]["cards"][resource]["type"])!=1: return false
			elif not p["rules"].get("stickers",{}).has(resource): return false
	return true
