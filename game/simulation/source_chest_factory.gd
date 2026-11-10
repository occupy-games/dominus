extends RefCounted
## Original storm chest allocation/constructor/reward protocol (0x10152ed0).
## Allocation, core construction and reward resolution belong to explicit
## simulation services. This protocol cannot substitute for those services.

const Terrain = preload("res://simulation/source_terrain.gd")
const Placement = preload("res://simulation/source_chest_placement.gd")


static func valid_rules(rules: Variant) -> bool:
	if not rules is Dictionary: return false
	for key: String in ["second_level","third_level","rotation","story_odds","random_divisor","inverse_height_scale","sea_level"]:
		if not Placement.finite(rules.get(key)): return false
	for key: String in ["story_reward","normal_reward"]:
		if not rules.get(key) is String or rules[key].is_empty(): return false
	return rules["random_divisor"]>0 and rules["inverse_height_scale"]>0


static func spawn(x: float,z: float,depth: float,rules: Dictionary,allocate: Callable,ground: Callable,random_word: Callable,construct: Callable,reward: Callable,notify: Callable) -> Dictionary:
	if not valid_rules(rules) or not Placement.finite(x) or not Placement.finite(z) or not Placement.finite(depth): return {}
	var handle: Variant=allocate.call()
	if handle==null: return {}
	var px := Terrain.f32(x)
	var pz := Terrain.f32(z)
	var burial := Terrain.f32(depth)
	var sampled: Variant=ground.call(px,pz)
	if not Placement.finite(sampled): return {}
	# The source computes depth after converting sampled world height back to
	# original steps; the whole expression has one float32 storage boundary.
	var height := Terrain.f32(Terrain.f32(float(sampled))*float(rules["inverse_height_scale"])-burial)
	var kind := 3 if height<=float(rules["sea_level"]) else (0 if height<Terrain.f32(float(rules["second_level"])) else (1 if height<Terrain.f32(float(rules["third_level"])) else 2))
	var normalized := Terrain.f32(float(random_word.call())/float(rules["random_divisor"]))
	var story := Terrain.f32(float(rules["story_odds"]))>normalized
	if story: kind=4
	var request := {"position":[px,pz,0.0],"depth":burial,"rotation":Terrain.f32(float(rules["rotation"])),"kind":kind}
	# Core construction samples the final buried/clamped height. Notification
	# reads its stored position, which may differ from the constructor input.
	var position: Variant=construct.call(handle,request.duplicate(true))
	if not position is Array or position.size()!=3: return {}
	for value: Variant in position:
		if not Placement.finite(value): return {}
	var stored: Array=[]
	for value: Variant in position: stored.append(Terrain.f32(float(value)))
	var name: String=rules["story_reward"] if story else rules["normal_reward"]
	# Native source ID is zero for generated chests, before reward assignment
	# and notification. Opening phase is separately initialized by the core.
	reward.call(handle,0,name)
	notify.call(handle,stored.duplicate(true))
	return {"handle":handle,"constructor":request,"position":stored,"source_id":0,"reward":name}
