extends RefCounted
## Deterministic player for repeatable campaign runs; emits ordinary commands.

var last_sculpt_tick := -1000
var sculpted_inward := false


func commands(world: RefCounted) -> Array:
	var state: Dictionary = world.snapshot(false)
	var result: Array = []
	if world.inspect({"type":"collect"})["ok"]: result.append({"type":"collect"})
	var clearing := clear_for_plot(world,state)
	if not clearing.is_empty(): result.append(clearing)
	if state.has("progression"):
		if not "Card_Spirituality" in state["progression"]["discovered"] and int(state["progression"]["first_card_tick"])<0:
			var start: Dictionary = state["camera_start"]
			var tapped := false
			for z in range(int(start["z"])-6,int(start["z"])+7):
				for x in range(int(start["x"])-6,int(start["x"])+7):
					var tap := {"type":"tap_object","cell":z*int(state["width"])+x}
					if not tapped and world.height_at(x,z)>0 and world.inspect(tap)["ok"]:
						result.append(tap)
						tapped=true
		var resource_command := gather_component(world,state)
		if not resource_command.is_empty(): result.append(resource_command)
	for card: String in ["Card_Spirituality","Card_MaxRank_2","Card_DoubleClick","Card_AbodeType_2"]:
		var claim := {"type":"claim_card","card":card}
		if world.inspect(claim)["ok"]: result.append(claim)
		elif card in state.get("progression",{}).get("discovered",[]):
			for resource: String in state["progression"].get("inventory",{}):
				var assign := {"type":"research_card","card":card,"sticker":resource}
				if world.inspect(assign).get("ok",false): result.append(assign); break
	# Exercise both directions through the same validated sculpt command as UI.
	if int(state["tick"])-last_sculpt_tick >= 150 and state["belief"] >= 10:
		var areas: Array = state.get("progression",{}).get("influence",[])
		var min_x := int(state["camera_start"]["x"])-12
		var max_x := min_x+24
		var min_z := int(state["camera_start"]["z"])-12
		var max_z := min_z+24
		for area: Dictionary in areas:
			min_x=mini(min_x,floori(float(area["x"])-float(area["radius"])))
			max_x=maxi(max_x,ceili(float(area["x"])+float(area["radius"])))
			min_z=mini(min_z,floori(float(area["z"])-float(area["radius"])))
			max_z=maxi(max_z,ceili(float(area["z"])+float(area["radius"])))
		var found := false
		for layer: int in [1,2]:
			for z in range(maxi(1,min_z),mini(int(state["width"])-1,max_z)):
				for x in range(maxi(1,min_x),mini(int(state["width"])-1,max_x)):
					if found: break
					if world.height_at(x,z)<layer or not world.can_act_at(x,z): continue
					for normal: Vector2i in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
						if world.height_at(x+normal.x,z+normal.y)>=layer: continue
						var inward: bool = layer==2 or (not sculpted_inward and int(state["tick"])>0)
						for radius in [1,0]:
							var distance: int = 3 if radius==1 else 1
							var command := {"type":"sculpt_drag","x":x,"z":z,"nx":normal.x,"nz":normal.y,"layer":layer,"distance":-distance if inward else distance,"radius":radius}
							if world.inspect(command)["ok"]:
								result.append(command)
								sculpted_inward=sculpted_inward or inward
								last_sculpt_tick=int(state["tick"])
								found=true
								break
						if found: break
				if found: break
			if found: break
	return result


func clear_for_plot(world: RefCounted,state: Dictionary) -> Dictionary:
	for agent: Dictionary in state["followers"]:
		if agent["job"]!=-1 or agent.has("workplace"): continue
		for dz in range(-4,5):
			for dx in range(-4,5):
				var candidate := {"type":"home","x":roundi(agent["x"])+dx,"z":roundi(agent["z"])+dz}
				var blockage: Dictionary = world.inspect(candidate).get("obstruction",{})
				if blockage.is_empty(): continue
				var tap := {"type":"tap_tree" if blockage["kind"]=="tree" else "tap_object","cell":int(blockage["z"])*int(state["width"])+int(blockage["x"])}
				if world.inspect(tap)["ok"]: return tap
		# Other idle followers at the same gathering spot share these candidates.
		break
	return {}


func gather_component(world: RefCounted, state: Dictionary) -> Dictionary:
	var p: Dictionary = state["progression"]
	var needed := false
	for id: String in ["Card_MaxRank_2","Card_DoubleClick","Card_AbodeType_2"]:
		if id in p["discovered"] and not id in p["completed"] and not world.inspect({"type":"claim_card","card":id}).get("ok",false): needed=true
	if not needed: return {}
	for chest: Dictionary in p["chests"]:
		var command := {"type":"open_chest","id":chest["id"]}
		if world.inspect(command)["ok"]: return command
	for chest: Dictionary in p["chests"]:
		if chest["opened"] or chest["height"]<0: continue
		if not world.can_act_at(chest["x"],chest["z"]): continue
		var x: int = chest["x"]
		var z: int = chest["z"]
		var layer: int = world.height_at(x,z)
		if layer<=int(chest["height"]): continue
		var digging := {"type":"dig","x":x,"z":z}
		if world.inspect(digging)["ok"]: return digging
		for dz in range(-10,11):
			for dx in range(-10,11):
				var ex := x+dx
				var ez := z+dz
				if world.height_at(ex,ez)<layer: continue
				for normal: Vector2i in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
					if world.height_at(ex+normal.x,ez+normal.y)>=layer: continue
					var delta := Vector2i(x-ex-normal.x,z-ez-normal.y)
					if delta.x*normal.x+delta.y*normal.y>=0 or maxi(absi(delta.x),absi(delta.y))>12: continue
					var edge := {"type":"sculpt_drag","x":ex,"z":ez,"nx":normal.x,"nz":normal.y,"layer":layer,"distance":-maxi(absi(delta.x),absi(delta.y)),"dx":delta.x,"dz":delta.y,"radius":0}
					if world.inspect(edge)["ok"]: return edge
	return {}
