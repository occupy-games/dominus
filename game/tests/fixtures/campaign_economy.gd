extends RefCounted

const Content = preload("res://infrastructure/campaign_content.gd")


static func definition() -> Dictionary:
	# Source rules on a controlled flat map isolate economy from map registration.
	var data := Content.homeworld()
	# The economy fixture also covers the older source's nonzero master research.
	data["research_scope"]="initialworldsetup"
	data["progression_rules"]=preload("res://infrastructure/progression_content.gd").rules(data)
	# Keep explicit legacy recipes in these older-schema regression fixtures.
	# The actual Homeworld typed-resource flow has its own end-to-end check.
	for id: String in ["Card_MaxRank_2","Card_AbodeType_2","Card_Spirituality","Card_DoubleClick","Card_TotemCapacity"]: data["progression_rules"]["research_cards"].erase(id)
	data["progression_rules"].erase("reward_cards")
	data["width"]=64
	data["terrain"]=PackedByteArray()
	data["terrain"].resize(64*64)
	data["terrain"].fill(4)
	data["tree_field"]=PackedByteArray()
	data["rock_field"]=PackedByteArray()
	data["rock_field"].resize(64*64)
	data["objects"]={"tree":[],"rock":[]}
	data["followers"]=[]
	for index in range(245):
		var start: Vector2i = [Vector2i(16,16),Vector2i(42,42),Vector2i(16,42)][index%3]
		data["followers"].append({"x":start.x+index%2,"z":start.y+index%4})
	data["configuration"]["InitialBelief"]=100000
	data["automatic_settlement"]=false
	data["progression_rules"]["influence_enabled"]=false
	data["progression_rules"]["chests"]=[]
	data["progression_rules"]["shrines"]=[]
	data["progression_rules"]["objects"]=[]
	return data

