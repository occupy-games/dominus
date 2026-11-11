extends RefCounted
## Deterministic observer/player for the authored opening. Emits ordinary commands;
## hypothetical route planning cannot edit terrain, move followers or advance story.

const DIRECTIONS := [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]
var last_sculpt_tick := -100
var camera_center := Vector2.INF
var planned_edits := 0
var diagnostic := ""
var serial := 0
var growth_site := Vector3i(-1,-1,-1)
var growth_idle_ticks := 0
var last_growth_search := -100
var rejected_sites := {}


func commands(world: RefCounted) -> Array:
	var state: Dictionary = world.snapshot(false)
	if not state.has("opening"): return []
	var opening: Dictionary = state["opening"]
	if not opening["error"].is_empty(): diagnostic=opening["error"]; return []
	var output: Array = []
	var center := Vector2.ZERO
	for follower: Dictionary in state["followers"]: center+=Vector2(follower["x"],follower["z"])
	center/=maxi(1,state["followers"].size())
	if preload("res://simulation/campaign_opening.gd").supports_first_chest(opening):
		var chest: Dictionary=opening["definition"]["first_chest"]
		center=Vector2(chest["x"],chest["z"])
	if camera_center==Vector2.INF or not opening["camera_locked"] and center.distance_to(camera_center)>5:
		camera_center=center
		output.append({"type":"campaign_view","projection":[1.0/32,0,0,0.5-center.x/32,0,1.0/32,0,0.5-center.y/32],"center":[center.x,center.y],"ended":true})
	for message: Dictionary in opening["messages"]:
		var group: String=opening["definition"]["messages"].get(str(int(message["id"])),{}).get("group","")
		if group in opening.get("hidden_tables",[]) or int(message.get("visible_tick",0))>int(state["tick"]): continue
		if message["callback"]!=null or int(message["id"])==4:
			var acknowledge := {"type":"campaign_ack","id":int(message["id"])}
			if world.inspect(acknowledge)["ok"]: output.append(acknowledge)
	if opening["phase"]=="discovery":
		var command := discovery_command(world,state)
		if not command.is_empty(): output.append(command)
		return output
	if opening["phase"]=="belief":
		var command := {}
		match int(opening["belief_step"]):
			0: command={"type":"campaign_show_level_card"}
			1: command={"type":"campaign_dismiss_level_card"}
			2:
				var houses: Dictionary=opening["globals"].get("beliefAbodes",{})
				for index in range(1,preload("res://simulation/voyage_script.gd").table_length(houses)+1):
					var collect := {"type":"collect","home_id":preload("res://simulation/voyage_script.gd").table_get(houses,index)}
					if world.inspect(collect)["ok"]: command=collect; break
			3:
				if opening["globals"].get("waitingForGrassSculpt",false):
					var position: Dictionary=opening["definition"]["constants"]["SCULPT_GRASS_POS"]
					var layer := roundi(float(position["z"])/0.3)-19
					var edge: Dictionary=world.find_edge(position["x"],position["y"],layer)
					if edge.get("ok",false):
						command=edge.duplicate(true)
						command.merge({"type":"sculpt_drag","distance":-1,"radius":0},true)
		if not command.is_empty() and world.inspect(command)["ok"]: output.append(command)
		return output
	if opening["phase"]=="shrine":
		var command := {}
		match int(opening["shrine_step"]):
			0: command={"type":"campaign_show_level_card"}
			1: command={"type":"campaign_dismiss_level_card"}
			2,3:
				command={"type":"campaign_activate_shrine","id":opening["definition"]["first_shrine_id"]}
				if not world.inspect(command)["ok"]:
					command={}
					for home_id: int in opening.get("sprog_homes",[]):
						var release := {"type":"sprog","home_id":home_id}
						if world.inspect(release).has("shrine_plan"):
							command=release
							break
					if command.is_empty() and opening["shrine_step"]==2: command=connect_shrine(world,state)
			4:
				if not state["source_influence"]["changed"]: command=grow_promised_land(world,state)
		if not command.is_empty() and world.inspect(command)["ok"]: output.append(command)
		return output
	if opening["phase"]=="timeline":
		var command := {}
		match int(opening.get("timeline_step",-1)):
			0: command={"type":"campaign_timeline_open"}
			2: command={"type":"research_card","card":opening["level_card"],"sticker":"Sticker_Tools_1"}
			3: command={"type":"campaign_timeline_close"}
			4,5:
				if opening["handoff"]["available"]: command=grow_promised_land(world,state)
		if not command.is_empty() and world.inspect(command)["ok"]: output.append(command)
		return output
	if opening["phase"]=="rescue":
		var rescue := {"type":"sculpt_drag","x":166,"z":58,"nx":0,"nz":-1,"layer":1,"distance":5,"dx":-3,"dz":-5,"radius":1}
		if world.inspect(rescue)["ok"]: output.append(rescue)
	elif opening["phase"]=="promised_land" and int(opening.get("promised_step",-1))==1:
		var cell := int(opening["activity_exception"])-preload("res://simulation/campaign_opening.gd").ROCK_ID_BASE
		var tap := {"type":"tap_object","cell":cell}
		if world.inspect(tap)["ok"]: output.append(tap)
	elif opening["phase"]=="promised_land" and int(opening.get("promised_step",-1))==2 and state["homes"].is_empty() and not opening.has("selected_plot"):
		var drag := {"type":"sculpt_drag","x":160,"z":120,"nx":1,"nz":0,"layer":1,"distance":1,"radius":0}
		if world.inspect(drag)["ok"]: output.append(drag)
	elif opening["phase"]=="promised_land" and int(opening.get("promised_step",-1)) in [3,4,5] and state["homes"].size()==1:
		var command := expand_promised_land(world,state)
		if not command.is_empty(): output.append(command)
	elif opening["phase"]=="promised_land" and opening["promised_step"]==6:
		var command := grow_promised_land(world,state)
		if not command.is_empty(): output.append(command)
	elif opening["phase"]=="promised_land" and int(opening["promised_step"]) in [7,8]:
		var command := {"type":"campaign_show_level_card" if opening["promised_step"]==7 else "campaign_dismiss_level_card"}
		if world.inspect(command)["ok"]: output.append(command)
	elif preload("res://simulation/campaign_opening.gd").supports_first_chest(opening):
		for chest: Dictionary in state["progression"]["chests"]:
			var command := {"type":"open_chest","id":chest["id"]}
			if world.inspect(command)["ok"]: output.append(command)
	elif opening["phase"]=="trail" and not opening["movement_paused"] and int(state["tick"])-last_sculpt_tick>=10:
		var entry: Dictionary = opening["entries"][int(opening["checkpoint"])]
		var target := Vector2(entry["Target"]["x"],entry["Target"]["y"])
		var leader: Dictionary = state["followers"][0]
		for follower: Dictionary in state["followers"]:
			if Vector2(follower["x"],follower["z"]).distance_squared_to(target)<=Vector2(leader["x"],leader["z"]).distance_squared_to(target): leader=follower
		if leader["state"]=="waiting":
			var start := Vector2i(roundi(leader["x"]),roundi(leader["z"]))
			var destination := Vector2i(roundi(target.x),roundi(target.y))
			var path := sculpt_route(world,state,start,destination,8)
			if path.is_empty(): path=sculpt_route(world,state,start,destination,16)
			var gesture := route_gesture(world,path)
			if not gesture.is_empty():
				output.append(gesture)
				last_sculpt_tick=int(state["tick"])
				planned_edits+=1
			else: diagnostic="No legal terrain gesture for checkpoint %d from %s to %s (%d planned cells)."%[opening["checkpoint"],start,destination,path.size()]
	return output


func expand_promised_land(world: RefCounted,state: Dictionary) -> Dictionary:
	for z in [127,128]:
		var drag := {"type":"sculpt_drag","x":160,"z":z,"nx":1,"nz":0,"layer":2,"distance":-1,"radius":0}
		if world.inspect(drag)["ok"]: return drag
	for z in range(124,131):
		for x in range(159,166):
			var tap := {"type":"tap_object","cell":z*int(state["width"])+x}
			if world.inspect(tap)["ok"]: return tap
	var release := {"type":"sprog","home_id":state["homes"][0]["id"]}
	return release if world.inspect(release)["ok"] else {}


func discovery_command(world: RefCounted,state: Dictionary) -> Dictionary:
	var opening: Dictionary=state["opening"]
	if opening["pit_step"]>=1:
		if opening.get("leash_mission_pending",false): return {}
		if opening.get("leash_step")==0: return {"type":"campaign_show_level_card"}
		if opening.get("leash_step")==1: return {"type":"campaign_dismiss_level_card"}
		if not opening.has("leash_step") and opening["definition"].has("leash_population_card"): return grow_promised_land(world,state)
		if opening.get("events_step")==1 and opening["definition"].has("farming_population_card"):
			var beacons: Array=opening.get("shrine_claims",[])
			if not beacons.is_empty(): return {"type":"campaign_activate_shrine","id":beacons[0]}
			var research:=housing_research(world,state)
			if not research.is_empty(): return research
			var mining:=mining_command(world,state)
			if not mining.is_empty(): return mining
			for advance: String in ["rock_belief","belief_collector","cliff_sculpt"]:
				var rules: Dictionary=opening["definition"].get(advance,{})
				if rules.is_empty(): continue
				research=research_advance(world,state,rules["card"])
				if not research.is_empty(): return research
			var fountain:=fountain_command(world,state)
			if not fountain.is_empty(): return fountain
			var builder:=builder_settlement_command(world,state)
			if not builder.is_empty(): return builder
			var command:=farming_command(world,state)
			if not command.is_empty(): return command
			if not opening.has("farming_step") or opening.get("superfast_step")==5:
				if state["belief"]==0:
					var collect:=collect_belief(world,state)
					if not collect.is_empty(): return collect
				return grow_promised_land(world,state)
		return {}
	if opening.get("pit_card_open",false): return {"type":"campaign_dismiss_level_card"}
	var site: Dictionary=world.source_shrine_site()
	var claim := {"type":"campaign_activate_shrine","id":site["id"]}
	if world.inspect(claim)["ok"]: return claim
	var homes: Array=state["homes"].filter(func(home: Dictionary) -> bool:
		return home["id"] in opening.get("sprog_homes",[]))
	var center := Vector2(site["x"],site["z"])
	homes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return center.distance_squared_to(Vector2(a["anchor_x"],a["anchor_z"]))<center.distance_squared_to(Vector2(b["anchor_x"],b["anchor_z"])))
	for home: Dictionary in homes:
		var release := {"type":"sprog","home_id":home["id"]}
		if world.inspect(release).has("shrine_plan"): return release
	if site["started"]: return {}
	for follower: Dictionary in state["followers"]:
		if follower.get("seeking_plot",false) or follower.get("entering_home",-1)>=0: return {}
	for home: Dictionary in state["homes"]:
		if home["progress"]<home["build_ticks"]: return {}
	if world.plot_obstruction(int(site["x"]),int(site["z"]))!="":
		var tap := {"type":"tap_tree" if world.plot_obstruction(int(site["x"]),int(site["z"]))=="tree" else "tap_object","cell":int(site["z"])*int(state["width"])+int(site["x"])}
		if world.inspect(tap)["ok"]: return tap
	var best := INF
	var move := {}
	for home: Dictionary in homes:
		var origin := Vector2i(home["work_x"],home["work_z"])
		for plot: Dictionary in world.growth_plots_from(Vector2(origin)):
			if not world.promised_plot_reachable(plot,origin): continue
			var position := Vector2(plot["x"],plot["z"])+Vector2.ONE*float(plot["size"])*0.5
			var distance := center.distance_squared_to(position)
			if distance<best:
				best=distance
				move={"type":"sprog","home_id":home["id"]}
			break
	if not move.is_empty(): return move
	return grow_promised_land(world,state)


func fountain_command(world: RefCounted,state: Dictionary) -> Dictionary:
	var opening: Dictionary=state["opening"]
	var rules: Dictionary=opening["definition"].get("fountain",{})
	if rules.is_empty() or opening.get("fountain_tutorial_done",false): return {}
	if opening.get("fountain_card_open",false): return {"type":"campaign_dismiss_level_card"}
	var claim:={"type":"claim_card","card":rules["card"]}
	if world.inspect(claim)["ok"]: return claim
	if not rules["power"] in state["progression"]["powers"]: return {}
	if opening.has("first_fountain"):
		var tap:={"type":"campaign_fountain_tap","id":opening["first_fountain"]}
		return tap if world.inspect(tap)["ok"] else {}
	if int(state.get("gems",0))<int(rules["gems"]):
		if state["followers"].any(func(follower: Dictionary) -> bool: return follower.get("leash_sacrifice",false)): return {}
		var pit: Dictionary=world.source_shrine_site()
		for id: int in opening.get("leash_homes",[]):
			var leash:={"type":"leash","home_id":id,"followers":[],"x":pit["x"],"z":pit["z"]}
			if world.inspect(leash)["ok"]: return leash
		for home: Dictionary in state["homes"]:
			if not str(home.get("kind","")).is_empty(): continue
			var collect:={"type":"collect","home_id":home["id"]}
			if world.inspect(collect)["ok"]: return collect
		return {}
	for home: Dictionary in state["homes"]:
		if not str(home.get("kind","")).is_empty() or home["progress"]<home["build_ticks"]: continue
		for z in range(int(home["z"])-3,int(home["z"])+int(home["span"])+3):
			for x in range(int(home["x"])-3,int(home["x"])+int(home["span"])+3):
				var cast:={"type":"use_power","power":rules["power"],"x":x,"z":z}
				if world.inspect(cast)["ok"]: return cast
	return {}


func farming_command(world: RefCounted,state: Dictionary) -> Dictionary:
	var opening: Dictionary=state["opening"]
	match int(opening.get("farming_step",-1)):
		-1,2:
			var cost: int=opening["definition"]["constants"]["FARM_BELIEF_COST"]
			if state["belief"]<cost:
				for home: Dictionary in state["homes"]:
					if home.get("stored",0)<home.get("min_belief",1): continue
					var collect:={"type":"collect","home_id":home["id"]}
					if world.inspect(collect)["ok"]: return collect
			elif opening.get("farming_step")==2: return {"type":"campaign_farm_select"}
		0: return {"type":"campaign_farm_card"}
		1: return {"type":"campaign_dismiss_level_card"}
		3:
			if opening.has("farming_preview"):
				var confirm:={"type":"campaign_farm_confirm"}
				return confirm if world.inspect(confirm)["ok"] else {"type":"campaign_farm_cancel"}
			var best:={}
			var capacity:=0
			for home: Dictionary in state["homes"]:
				var point:=Vector2(home.get("anchor_x",home["x"]),home.get("anchor_z",home["z"])).round()
				var preview:={"type":"campaign_farm_preview","x":int(point.x),"z":int(point.y)}
				var plan: Dictionary=world.inspect(preview)
				if not plan["ok"] or plan["capacity"]<=capacity: continue
				capacity=plan["capacity"]
				best=preview
			return best
		4,5:
			if opening.get("superfast_step")==0:
				var claim:={"type":"claim_card","card":"Card_GrainToBuild"}
				if world.inspect(claim)["ok"]: return claim
			if opening.get("superfast_step")==1: return {"type":"campaign_dismiss_level_card"}
			if opening.get("superfast_step",-1)>=2:
				var rain: Dictionary=opening["definition"].get("rain",{})
				if not rain.is_empty():
					var claim:={"type":"claim_card","card":rain["card"]}
					if world.inspect(claim)["ok"]: return claim
				for home: Dictionary in state["homes"]:
					if not home.get("direct_harvest",false): continue
					var harvest:={"type":"collect","home_id":home["id"]}
					if world.inspect(harvest)["ok"]: return harvest
				if opening["superfast_step"]!=5: return {}
				var advances: Array=opening["definition"].get("grain_advances",[])
				var target: int=rain.get("fields",0) if advances.is_empty() else advances.back()["fields"]
				if preload("res://simulation/campaign_farming.gd").field_count(state)>=target: return {}
			for settlement: Dictionary in state["progression"]["settlements"]:
				if settlement["role"]!="farmer": continue
				var deploy:={"type":"deploy_worker","id":settlement["id"]}
				if world.inspect(deploy)["ok"]: return deploy
	return {}


func builder_settlement_command(world: RefCounted,state: Dictionary) -> Dictionary:
	var opening: Dictionary=state["opening"]
	var builder: Dictionary=opening["definition"].get("builder_settlement",{})
	if builder.is_empty() or not builder["power"] in state["progression"]["powers"]: return {}
	if opening.has("builder_preview"):
		var confirm:={"type":"campaign_builder_confirm"}
		return confirm if world.inspect(confirm)["ok"] else {"type":"campaign_builder_cancel"}
	if state["belief"]<int(builder["cost"]): return {}
	for settlement: Dictionary in state["progression"]["settlements"]:
		if settlement["role"]=="builder": return {}
	for home: Dictionary in state["homes"]:
		if home.has("settlement_id") or not str(home.get("kind","")).is_empty() or home["progress"]<home["build_ticks"]: continue
		var preview:={"type":"campaign_builder_preview","x":roundi(home["anchor_x"]),"z":roundi(home["anchor_z"])}
		if world.inspect(preview)["ok"]: return preview
	return {}


func housing_research(world: RefCounted,state: Dictionary) -> Dictionary:
	for key: String in ["housing_advances","grain_advances","ore_advances"]:
		for level: Dictionary in state["opening"]["definition"].get(key,[]):
			var command:=research_advance(world,state,level["id"])
			if not command.is_empty(): return command
	return {}


func mining_command(world: RefCounted,state: Dictionary) -> Dictionary:
	var opening: Dictionary=state["opening"]
	var mining: Dictionary=opening["definition"].get("mining_settlement",{})
	if mining.is_empty() or not mining["power"] in state["progression"]["powers"]: return {}
	for item: Dictionary in state["progression"]["settlements"]:
		if item["role"]!="miner": continue
		if item["ore"]>0:
			var harvest:={"type":"collect_settlement","id":item["id"]}
			if world.inspect(harvest)["ok"]: return harvest
		var deploy:={"type":"deploy_worker","id":item["id"]}
		if world.inspect(deploy)["ok"]: return deploy
	if opening.has("mining_preview"):
		var confirm:={"type":"campaign_mining_confirm"}
		return confirm if world.inspect(confirm)["ok"] else {"type":"campaign_mining_cancel"}
	if state["belief"]<int(mining["cost"]): return collect_belief(world,state)
	var spec: Dictionary=state["progression"]["rules"]["economy"]["settlements"][mining["power"]]
	var registry: Dictionary=state["source_plots"]
	var plots: Array=[]
	for id: int in registry["active"]:
		var plot: Dictionary=registry["slots"][id]
		if not world.source_house_for_plot(plot["x"],plot["z"],plot["size"],2).is_empty(): plots.append(plot)
	for home: Dictionary in state["homes"]:
		if home.has("settlement_id") or not str(home.get("kind","")).is_empty() or home["progress"]<home["build_ticks"]: continue
		var center:=Vector2(home["anchor_x"],home["anchor_z"]).round()
		for plot: Dictionary in plots:
			var at:=Vector2(plot["x"],plot["z"])+Vector2.ONE*float(plot["size"])*0.5
			if center.distance_squared_to(at)>float(spec["radius"])*float(spec["radius"]): continue
			var footprint:=Rect2i(plot["x"],plot["z"],plot["size"],plot["size"])
			if not world.promised_plot_reachable(plot,Vector2i(home["work_x"],home["work_z"])) or footprint.has_point(Vector2i(center)): continue
			var preview:={"type":"campaign_mining_preview","x":int(center.x),"z":int(center.y)}
			if world.inspect(preview)["ok"]: return preview
	return {}


func collect_belief(world: RefCounted,state: Dictionary) -> Dictionary:
	for item: Dictionary in state["progression"]["settlements"]:
		var collect:={"type":"collect_settlement","id":item["id"]}
		if world.inspect(collect).get("belief",0)>0: return collect
	for home: Dictionary in state["homes"]:
		if home.get("kind","")!="" or home.get("stored",0)<home.get("min_belief",1): continue
		var collect:={"type":"collect","home_id":home["id"]}
		if world.inspect(collect)["ok"]: return collect
	return {}


func research_advance(world: RefCounted,state: Dictionary,card: String) -> Dictionary:
	var p: Dictionary=state["progression"]
	if not card in p["discovered"] or card in p["completed"]: return {}
	var definition: Dictionary=p["rules"]["research_cards"].get(card,{})
	if definition.is_empty(): return {}
	var claim:={"type":"claim_card","card":card}
	if world.inspect(claim)["ok"]: return claim
	for sticker: String in p["inventory"]:
		var assign:={"type":"research_card","card":card,"sticker":sticker}
		if world.inspect(assign)["ok"]: return assign
	var chests: Array=p["chests"]
	if chests.is_empty() and state["opening"].has("chests"):
		var authored:=preload("res://simulation/authored_chests.gd").new()
		authored.configure(world,state,[])
		chests=authored.snapshot()
	var fallback: Dictionary={}
	for chest: Dictionary in chests:
		if chest["opened"] or chest["opening"] or not world.can_act_at(chest["x"],chest["z"]): continue
		var open:={"type":"open_chest","id":chest["id"]}
		if chest["card"].is_empty() and chest.get("native",false):
			if fallback.is_empty() and chest["exposed"] and world.inspect(open)["ok"]: fallback=open
			continue
		if int(p["rules"]["stickers"].get(chest["card"],{}).get("contributions",{}).get(definition["research_type"],0))<=0: continue
		if world.inspect(open)["ok"]: return open
		var height:=maxi(0,floori(chest["height"]+0.01))
		var gesture:=route_gesture(world,[Vector3i(roundi(chest["x"]),roundi(chest["z"]),height)])
		if not gesture.is_empty(): return gesture
	return fallback


func connect_shrine(world: RefCounted,state: Dictionary) -> Dictionary:
	var location: Dictionary=state["opening"]["definition"]["constants"]["FIRST_SHRINE"]
	var anchor := Vector2i(location["x"],location["y"])
	var homes: Array=state["homes"].duplicate()
	homes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return Vector2i(a["work_x"],a["work_z"]).distance_squared_to(anchor)<Vector2i(b["work_x"],b["work_z"]).distance_squared_to(anchor))
	for home: Dictionary in homes:
		var origin := Vector2i(home["work_x"],home["work_z"])
		if home["residents"]<=home.get("breeder_count",1): continue
		for direction: Vector2i in DIRECTIONS:
			var gesture := route_gesture(world,sculpt_route(world,state,origin,anchor+direction,5))
			if not gesture.is_empty(): return gesture
	diagnostic="No legal sculpt gesture connects a Builder to the Shrine of Expansion."
	return {}


func grow_promised_land(world: RefCounted,state: Dictionary) -> Dictionary:
	for follower: Dictionary in state["followers"]:
		if follower["state"]!="waiting" or int(follower["job"])<0 or not follower.has("work_x"): continue
		var start := Vector2i(roundi(follower["x"]),roundi(follower["z"]))
		var target := Vector2i(follower["work_x"],follower["work_z"])
		var path := sculpt_route(world,state,start,target,8)
		if path.is_empty(): path=sculpt_route(world,state,start,target,16)
		var connection := route_gesture(world,path)
		if not connection.is_empty(): return connection
	var next_release: Dictionary={}
	for home_id: int in state["opening"].get("sprog_homes",[]):
		var release := {"type":"sprog","home_id":home_id}
		var plan: Dictionary=world.inspect(release)
		if not plan["ok"]: continue
		if plan.has("shrine_plan"):
			next_release=release
			break
		if next_release.is_empty(): next_release=release
	if not next_release.is_empty():
		growth_site=Vector3i(-1,-1,-1)
		growth_idle_ticks=0
		return next_release
	if not world.has_room_for_growth(): return {}
	if growth_site.x<0:
		if int(state["tick"])-last_growth_search<20: return {}
		last_growth_search=int(state["tick"])
		growth_site=choose_growth_site(world,state)
	if growth_site.x<0: diagnostic="No reachable abode plot can be prepared."; return {}
	var edits: Array=[]
	for z in range(growth_site.y,growth_site.y+5):
		for x in range(growth_site.x,growth_site.x+5):
			if x<growth_site.x+4 and z<growth_site.y+4:
				var obstacle: String=world.plot_obstruction(x,z)
				if not obstacle.is_empty():
					var tap := {"type":"tap_tree" if obstacle=="tree" else "tap_object","cell":z*int(state["width"])+x}
					if world.inspect(tap)["ok"]: return tap
			if world.height_at(x,z)!=growth_site.z: edits.append(Vector3i(x,z,growth_site.z))
	var gesture := route_gesture(world,edits)
	if not gesture.is_empty(): growth_idle_ticks=0; return gesture
	growth_idle_ticks+=1
	if not edits.is_empty() or growth_idle_ticks>=20:
		rejected_sites[growth_site]=true
		growth_site=Vector3i(-1,-1,-1)
		growth_idle_ticks=0
	return {}


func choose_growth_site(world: RefCounted,state: Dictionary) -> Vector3i:
	var best := Vector3i(-1,-1,-1)
	var best_score := INF
	var bounds := Rect2i(146,108,31,34)
	var discovery: bool=state["opening"]["phase"]=="discovery"
	var after_shrine: bool=state["opening"]["phase"]=="shrine" or discovery
	var toward_pit: bool=discovery and state["opening"]["pit_step"]==0
	var pit: Dictionary=world.source_shrine_site() if discovery else {}
	var dock: Dictionary=world.source_dock_site() if discovery else {}
	if after_shrine:
		for home: Dictionary in state["homes"]: bounds=bounds.expand(Vector2i(home["x"],home["z"]))
		bounds=bounds.grow(23)
	if toward_pit: bounds=Rect2i(Vector2i(pit["x"],pit["z"])-Vector2i.ONE*12,Vector2i.ONE*24)
	var shrine: Dictionary=state["opening"]["definition"]["constants"].get("FIRST_SHRINE",{})
	var limits: Dictionary=world.source_plot_limits()
	var config: Dictionary=state["opening"]["definition"]["plot_environment"]["configuration"]
	for z in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var cell := Vector2i(x,z)
			if not world._source_fresh_plot_cell(x,z,limits["biomes"]) or not after_shrine and Vector2(cell+Vector2i(2,2)).distance_to(Vector2(161,123))>20: continue
			var area := Rect2i(x,z,4,4)
			if discovery and area.intersects(world.source_shrine_bounds(pit)): continue
			if not dock.is_empty() and area.intersects(world.source_shrine_bounds(dock)): continue
			if not shrine.is_empty() and area.has_point(Vector2i(shrine["x"],shrine["y"])): continue
			if state["opening"].get("growth_plots",[]).any(func(plot: Dictionary) -> bool: return area.intersects(Rect2i(plot["x"],plot["z"],plot["size"],plot["size"]))): continue
			var heights: Array=[]
			var obstacles := 0
			for dz in range(5):
				for dx in range(5):
					var point := cell+Vector2i(dx,dz)
					if world._occupied(point.x,point.y) or not world.can_act_at(point.x,point.y): continue
					if dx<4 and dz<4 and world.plot_obstruction(point.x,point.y)!="": obstacles+=1
					heights.append(world.height_at(point.x,point.y))
			if heights.size()!=25: continue
			var proximity := INF
			for home: Dictionary in state["homes"]: proximity=minf(proximity,Vector2(cell).distance_to(Vector2(home["x"],home["z"])))
			if toward_pit: proximity+=Vector2(cell+Vector2i(2,2)).distance_to(Vector2(pit["x"],pit["z"]))*5.0
			for height in range(1,6 if toward_pit or not discovery else 11):
				var band:=preload("res://simulation/source_biomes.gd").band(height+19,config)
				if int(limits["sizes"][band][0])>4: continue
				var candidate := Vector3i(x,z,height)
				if rejected_sites.has(candidate) or not height in heights: continue
				var score := proximity*0.1+obstacles*0.5
				for index in range(25):
					var actual := int(heights[index])
					if actual==height: continue
					if not editable(world,state,cell+Vector2i(index%5,index/5),actual,height): score=INF; break
					score+=absi(actual-height)
				if score>=best_score: continue
				var reachable: bool=state["homes"].any(func(home: Dictionary) -> bool: return home.get("kind","")=="" and world.promised_plot_reachable({"x":x,"z":z,"size":4},Vector2i(home["work_x"],home["work_z"])))
				if reachable: best=candidate; best_score=score
	return best


func sculpt_route(world: RefCounted,state: Dictionary,start: Vector2i,target: Vector2i,margin: int) -> Array:
	var bounds := Rect2i(start.min(target)-Vector2i.ONE*margin,(start-target).abs()+Vector2i.ONE*(margin*2+1))
	var first := Vector3i(start.x,start.y,world.height_at(start.x,start.y))
	if first.z<=0: return []
	var heap: Array = []
	push(heap,[0.0,0,first])
	var previous := {first:first}
	var costs := {first:0.0}
	var closed := {}
	var cursor := 0
	while not heap.is_empty() and cursor<15000:
		var current: Vector3i = pop(heap)[2]
		if closed.has(current): continue
		closed[current]=true
		cursor+=1
		if Vector2i(current.x,current.y)==target:
			var path: Array = []
			while current!=first:
				path.push_front(current)
				current=previous[current]
			return path
		for direction: Vector2i in DIRECTIONS:
			var cell := Vector2i(current.x,current.y)+direction
			if not bounds.has_point(cell) or cell.x<1 or cell.y<1 or cell.x>=int(state["width"])-1 or cell.y>=int(state["width"])-1: continue
			if world._occupied(cell.x,cell.y): continue
			var actual: int = world.height_at(cell.x,cell.y)
			var minimum := maxi(1,current.z-1)
			var maximum := mini(63,current.z+1)
			for height in range(minimum,maximum+1):
				if actual!=height and not editable(world,state,cell,actual,height): continue
				var next := Vector3i(cell.x,cell.y,height)
				var cost: float = costs[current]+1+absi(actual-height)*6
				if cost>=float(costs.get(next,INF)): continue
				costs[next]=cost
				previous[next]=current
				serial+=1
				push(heap,[cost+absi(cell.x-target.x)+absi(cell.y-target.y),serial,next])
	return []


func editable(world: RefCounted,state: Dictionary,cell: Vector2i,actual: int,height: int) -> bool:
	if not world.can_act_at(cell.x,cell.y): return false
	var opening: Dictionary = state["opening"]
	var band: Dictionary = opening["definition"]["coastal_free_band"]
	var index := cell.y*int(state["width"])+cell.x
	var raw: int = 19+actual if actual>0 else int(opening["submerged_levels"].get(str(index),opening["definition"]["raw_floor"][index]))
	if opening.get("events_step")==1 and state["belief"]>0: return true
	return mini(raw,19+height)>=int(band["min"]) and maxi(raw,19+height)<=int(band["max"])


func route_gesture(world: RefCounted,path: Array) -> Dictionary:
	for cell: Vector3i in path:
		var actual: int = world.height_at(cell.x,cell.y)
		if actual==cell.z: continue
		for direction: Vector2i in DIRECTIONS:
			var neighbor := Vector2i(cell.x,cell.y)+direction
			var command: Dictionary
			if cell.z>actual and world.height_at(neighbor.x,neighbor.y)>=cell.z:
				command={"type":"sculpt_drag","x":neighbor.x,"z":neighbor.y,"nx":-direction.x,"nz":-direction.y,"layer":cell.z,"distance":1,"radius":0}
			elif cell.z<actual and world.height_at(neighbor.x,neighbor.y)<=cell.z:
				command={"type":"sculpt_drag","x":cell.x,"z":cell.y,"nx":direction.x,"nz":direction.y,"layer":cell.z+1,"distance":-1,"radius":0}
			else: continue
			if world.inspect(command)["ok"]: return command
	return {}


func push(heap: Array,item: Array) -> void:
	heap.append(item)
	var index := heap.size()-1
	while index>0:
		var parent := (index-1)/2
		if not before(heap[index],heap[parent]): break
		var swap: Array = heap[index]; heap[index]=heap[parent]; heap[parent]=swap
		index=parent


func pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return result
	heap[0]=last
	var index := 0
	while index*2+1<heap.size():
		var child := index*2+1
		if child+1<heap.size() and before(heap[child+1],heap[child]): child+=1
		if not before(heap[child],heap[index]): break
		var swap: Array = heap[index]; heap[index]=heap[child]; heap[child]=swap
		index=child
	return result


func before(a: Array,b: Array) -> bool:
	return a[0]<b[0] or a[0]==b[0] and a[1]<b[1]
