extends RefCounted
## Shared placement and settlement affiliation for the campaign's statues.

const Membership = preload("res://simulation/source_temple_membership.gd")
const Numbers = preload("res://simulation/source_plot_schedule.gd")
const Terrain = preload("res://simulation/source_terrain.gd")


static func status(state: Dictionary,kind: String,rules: Dictionary,unlocked: bool,parameters: Dictionary) -> Dictionary:
	var count:=0
	for prop: Dictionary in state["props"]:
		if prop.get("kind")==kind: count+=1
	var price: int=rules["prices"][mini(count,rules["prices"].size()-1)]
	var offers: Array=[]
	if unlocked:
		var flags: Dictionary=state["progression"].get("script_unlocks",{})
		for upgrade: Dictionary in rules["upgrades"]:
			if flags.get(upgrade["id"],false): continue
			offers.append({"next":upgrade.duplicate(true),"affordable":int(state.get(upgrade["currency"],0))>=int(upgrade["cost"])})
	return parameters.merged({"price":price,"can_place":unlocked and int(state["belief"])>=price,"upgrades":offers})


static func bounds(prop: Dictionary,rules: Dictionary) -> Rect2i:
	return Rect2i(prop["x"],prop["z"],rules["width"],rules["depth"])


static func inspect(world: RefCounted,state: Dictionary,command: Dictionary,rules: Dictionary,current: Dictionary,upgrade_type: String) -> Dictionary:
	var reject:={"ok":false,"cost":0,"reason":""}
	if command["type"]==upgrade_type:
		for offer: Dictionary in current.get("upgrades",[]):
			var upgrade: Dictionary=offer["next"]
			if command.get("id")==upgrade["id"] and offer["affordable"]:
				return {"ok":true,"cost":0,"reason":"","resource_cost":{upgrade["currency"]:upgrade["cost"]},"upgrade":upgrade["id"]}
		return reject
	if not current.get("can_place",false) or state["props"].size()>=4096: return reject
	for axis: String in ["x","z"]:
		var value: Variant=command.get(axis)
		if not (value is int or value is float) or not is_finite(value) or value<0 or value>=state["width"]: return reject
	var point:=Vector2i(roundi(command["x"]),roundi(command["z"]))
	if not world.source_clear_footprint(bounds({"x":point.x,"z":point.y},rules)): return reject
	return {"ok":true,"cost":current["price"],"reason":"","x":point.x,"z":point.y}


static func place(state: Dictionary,kind: String,rules: Dictionary,plan: Dictionary) -> Dictionary:
	var shrine:={"kind":kind,"id":state["next_id"],"model_id":rules["model"],"x":plan["x"],"z":plan["z"],
		"turns":0,"settlement_id":-1,"affiliation_due":0.0}
	state["next_id"]+=1
	state["props"].append(shrine)
	return shrine


static func settlement_sites(state: Dictionary,raw_height: Callable) -> Dictionary:
	var owners:={}
	for settlement: Dictionary in state["progression"]["settlements"]:
		var x:=float(settlement["x"])
		var z:=float(settlement["z"])
		var id:=int(settlement["id"])
		owners[str(id)]={"handle":owners.size(),"is_settlement":true,"settlement_id":id,"x":x,"z":z,
			"height":Terrain.surface_height(raw_height.call(x,z)),"radius":Terrain.f32(settlement["radius"])}
	return owners


static func area(shrine: Dictionary,radius: float,owners: Dictionary) -> Dictionary:
	var owner:=int(shrine.get("settlement_id",-1))
	if not owners.has(str(owner)): owner=-1
	return {"handle":0,"is_settlement":false,"settlement_id":owner,"x":float(shrine["x"]),"z":float(shrine["z"]),"height":0.0,"radius":radius}


static func advance(state: Dictionary,shrines: Array,raw_height: Callable,random: RandomNumberGenerator,tick_seconds: float) -> void:
	if shrines.is_empty(): return
	var now:=Terrain.f32(float(state["tick"])*tick_seconds)
	var owners:={}
	var loaded:=false
	for shrine: Dictionary in shrines:
		if float(shrine["affiliation_due"])>=now: continue
		if not loaded:
			owners=settlement_sites(state,raw_height)
			loaded=true
		var site:=area(shrine,0.0,owners)
		site["affiliation_due"]=shrine["affiliation_due"]
		var clock:=func(_index: int) -> float: return now
		var word:=func() -> int: return int(random.randi())&32767
		var service:=func(_name: String,_args: Array) -> void: pass
		Membership.refresh(site,owners.values(),owners,state["opening"]["definition"]["temple_membership_rules"],clock,word,service)
		shrine["settlement_id"]=site["settlement_id"]
		shrine["affiliation_due"]=site["affiliation_due"]


static func details(world: RefCounted,state: Dictionary,shrine: Dictionary,rules: Dictionary,radius: float) -> Dictionary:
	var owners:=settlement_sites(state,world.source_raw_height_at)
	var owner: Dictionary=owners.get(str(int(shrine.get("settlement_id",-1))),{})
	return {"entity":"temple","kind":"shrine","id":shrine["id"],"site_type":rules["temple_type"],"complete":true,"started":true,
		"occupants":0,"capacity":0,"belief":0,"radius":owner.get("radius",radius),
		"title_key":rules["title_key"],"description_key":rules["description_key"]}


static func valid_affiliation(shrine: Dictionary) -> bool:
	return Numbers.integer_between(shrine.get("settlement_id"),-1,2147483647) and Membership.source_float(shrine.get("affiliation_due")) and shrine["affiliation_due"]>=0
