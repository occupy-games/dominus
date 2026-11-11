extends RefCounted
## Homeworld6's authored Astari festival and Ark construction tutorial.

const Astari = preload("res://simulation/campaign_astari.gd")
const Progression = preload("res://simulation/progression.gd")
const Unlocks = preload("res://simulation/source_unlocks.gd")


static func hull(state: Dictionary,site_id: String) -> Dictionary:
	for home: Dictionary in state["homes"]:
		if home.get("shrine_id")==site_id and home.has("ark_crew"): return home
	return {}


static func board(home: Dictionary,follower: Dictionary) -> void:
	if home.is_empty() or home["residents"]>=home["capacity"]: return
	home["ark_crew"][str(follower["id"])]=true
	home["residents"]+=1
	for key: String in ["away_home","entering_home","repair_site","leash_goal","ark_boarding","workplace","profession","settlement_id","carrying"]:
		follower.erase(key)
	follower.merge({"state":"indoors","indoors_home":home["id"],"x":float(home["work_x"]),"z":float(home["work_z"]),"path":[],"job":-1},true)


static func advance(world: RefCounted,state: Dictionary,tutorial: RefCounted,events: Array) -> void:
	var opening: Dictionary=state["opening"]
	var rules: Dictionary=opening["definition"].get("ark",{})
	if not rules.has("model_id"): return
	var p: Dictionary=state["progression"]
	var status: Dictionary=opening.get("ark_progress",{})
	var tick: int=state["tick"]
	var beacon: Array=rules["beacon"]
	if not world.source_plot_eligible(beacon[0],beacon[1]):
		var approach: Array=rules["approach"]
		if not world.source_plot_eligible(approach[0]+rules["approach_offset"],approach[1]): return
		if not status.has("next_scan"):
			opening["ark_progress"]=status
			status["next_scan"]=tick
			tutorial.show_ark_message(5707,rules["beacon_id"])
		if not Unlocks.enabled(p,"InfluenceTakeover") and not state.get("astari_village",{}).get("forced",false) and tick>=int(status["next_scan"]):
			status["next_scan"]=tick+roundi(float(rules["scan_seconds"])*10)
			var statue: Array=rules["astari"]
			var center:=Vector2(statue[0],statue[1])
			for follower: Dictionary in state["followers"]:
				if follower.get("allegiance",0)!=0 or not follower.get("profession","") in ["","builder"] or follower["state"]=="indoors": continue
				if center.distance_to(Vector2(follower["x"],follower["z"]))>float(statue[2]): continue
				Astari.force_festival(world,state,world._random,events)
				break
		return
	if not status.get("conquered",false):
		opening["ark_progress"]=status
		status["conquered"]=true
		tutorial.clear_message(5707)
		tutorial.show_ark_message(5708,rules["beacon_id"])
		Progression.reward(state,rules["card"])
		events.append({"type":"campaign_show_card","card":rules["card"]})
	var position: Array=rules["position"]
	if not world.source_plot_eligible(position[0],position[1]): return
	tutorial.clear_message(5708)
	var site: Dictionary=world.source_shrine_site(rules["site_id"])
	if site.is_empty(): return
	if site["complete"]:
		tutorial.clear_message(5701)
		tutorial.clear_message(5702)
		tutorial.clear_message(5703)
		if not status.get("complete",false):
			status["complete"]=true
			tutorial.show_ark_message(5704)
			tutorial.show_ark_message(5705,site["id"])
			events.append({"type":"campaign_ark_completed","site":site["id"]})
		return
	if not status.get("building_hint",false):
		status["building_hint"]=true
		tutorial.show_ark_message(5702)
		if not site["started"]: tutorial.show_ark_message(5701,site["id"])
	if not site["started"]: return
	tutorial.clear_message(5701)
	if status.has("halfway_until"):
		if tick>=int(status["halfway_until"]):
			status.erase("halfway_until")
			tutorial.clear_message(5703)
		return
	if status.get("halfway_shown",false) or tick<int(status.get("next_build_poll",0)): return
	status["next_build_poll"]=tick+roundi(float(rules["halfway_poll_seconds"])*10)
	for home: Dictionary in state["homes"]:
		if home.get("shrine_id")!=site["id"]: continue
		if int(home["progress"])*2>int(home["build_ticks"]):
			status["halfway_shown"]=true
			status["halfway_until"]=tick+roundi(float(rules["halfway_hint_seconds"])*10)
			tutorial.show_ark_message(5703,site["id"])
		break
