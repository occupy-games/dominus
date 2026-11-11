extends RefCounted
## Original house-pool order, linked clump merging and first-largest tie rule.

const Terrain = preload("res://simulation/source_terrain.gd")


static func valid_rules(rules: Variant) -> bool:
	return rules is Dictionary and rules.get("complete_state")==1 and rules.get("include_unfinished_default")==true


static func biggest(houses: Array,kind: int,radius: float,rules: Dictionary,include_unfinished: bool=true) -> Array:
	var members: Array=[]
	var links: Array[int]=[]
	var children: Array[bool]=[]
	for index in range(houses.size()-1,-1,-1):
		var house: Dictionary=houses[index]
		if house["type"]!=kind or not include_unfinished and house["state"]!=rules["complete_state"]:
			continue
		members.append(house)
		links.append(-1)
		children.append(false)
	var reach := Terrain.f32(Terrain.f32(radius)*Terrain.f32(radius))
	for index in range(1,members.size()):
		var matched := -1
		for root in range(index):
			if children[root]: continue
			var current := root
			while current>=0:
				var dx := Terrain.f32(Terrain.f32(members[current]["x"])-Terrain.f32(members[index]["x"]))
				var dz := Terrain.f32(Terrain.f32(members[current]["z"])-Terrain.f32(members[index]["z"]))
				if Terrain.f32(dx*dx+dz*dz)<reach: break
				current=links[current]
			if current<0: continue
			children[index]=true
			if matched<0:
				links[index]=links[root]
				links[root]=index
			else:
				var tail := matched
				while links[tail]>=0: tail=links[tail]
				links[tail]=links[root]
				links[root]=matched
				children[matched]=true
			matched=root
	var largest: Array=[]
	for root in range(members.size()):
		if children[root]: continue
		var group: Array=[]
		var current := root
		while current>=0:
			group.append(members[current]["id"])
			current=links[current]
		if group.size()>largest.size(): largest=group
	return largest
