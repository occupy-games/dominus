extends SceneTree

const Content = preload("res://infrastructure/game_content.gd")
const Campaign = preload("res://infrastructure/campaign_content.gd")
const World = preload("res://simulation/world.gd")
const Glints = preload("res://presentation/world/chest_glints.gd")
const Emission = preload("res://presentation/world/beautify_emission.gd")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func check_native_sample(asset: Dictionary) -> void:
	var playback := Emission.new(asset["emitter"],asset["emission_rng"],asset["curve_constants"]["percent"],0)
	playback.advance(0.0)
	for step in range(9):
		playback.advance(33.0)
	check(playback.particles.size()==1,"The original chest emission sample must create one live particle")
	var particle: Dictionary = playback.particles.get(0,{})
	if particle.is_empty():
		return
	# Source effect update 0x102adf70, seed zero, initial 0 ms and nine 33 ms frames.
	check(particle["remaining_ms"]==2483 and particle["lifetime_ms"]==2549,"Match the original particle clock")
	check(particle["offset"].distance_to(Vector3(-2.53780937,-12.63161659,-3.15354013))<0.00002,"Match the original particle motion")
	check(is_equal_approx(particle["size"],2.1051302) and is_equal_approx(particle["aspect"],2.1656249),"Match both original size axes")
	check(is_equal_approx(particle["rotation_degrees"],300.6741638) and is_equal_approx(particle["color_phase"],71.9560471),"Match the original spin and fixed particle color phase")


func run() -> void:
	var asset := Content.new().chest_glint()
	check(not asset.is_empty(),"The original buried chest atlas and emitter must load")
	if failures:
		quit(1)
		return
	check(asset["timing"]["delay"]==[4.0,8.0] and asset["scene"]["offset_xyz"]==[0.0,0.0,0.5],"Use the original surface offset and glint interval")
	check_native_sample(asset)
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026
	world.initialize({"campaign_data":Campaign.homeworld()},random)
	var snapshot := world.snapshot(false)
	var chests: Array = snapshot["progression"]["chests"]
	var buried: Array = chests.filter(func(chest: Dictionary) -> bool: return chest.get("glint",{}).get("depth",0.0)>0.0)
	check(not buried.is_empty(),"The original Homeworld start must describe a buried chest in actionable land")
	check(world._state["progression"]["chests"].all(func(chest: Dictionary) -> bool: return not chest.has("glint")),"Surface positions belong to detached presentation data")
	if buried.is_empty():
		quit(1)
		return
	var chest: Dictionary = buried[0]
	check(world.can_act_at(chest["x"],chest["z"]) and not world.inspect({"type":"open_chest","id":chest["id"]})["ok"],"A cue must identify a buried chest while excavation is still required")
	var glints := Glints.new()
	glints.configure(asset)
	glints._random.seed = 2026
	root.add_child(glints)
	var camera := Camera3D.new()
	root.add_child(camera)
	var width := int(snapshot["width"])
	var center := (width-1)*0.5
	var surface := Vector3(chest["x"]-center,chest["glint"]["height"],chest["z"]-center)
	camera.position = surface+Vector3(0,8,12)
	camera.look_at(surface)
	camera.make_current()
	var region := Rect2i(Vector2i(int(chest["x"]),int(chest["z"]))-Vector2i.ONE,Vector2i(3,3))
	glints.sync([chest],width,snapshot["tick"],region)
	glints.advance(3.9,camera)
	check(glints.multimesh.visible_instance_count==0,"The glint must wait for the source interval")
	var visible := false
	for frame in range(300):
		glints.advance(0.033,camera)
		if glints.multimesh.visible_instance_count>0:
			visible = true
			break
	check(visible,"The actual buried chest must emit source particles at the terrain surface")
	if visible:
		var active: Dictionary = glints._chests[chest["id"]]["emitters"][0]
		check(active["origin"].is_equal_approx(surface+Vector3(0,0.5,0)),"A glint must start at the authored surface offset")
		var material: StandardMaterial3D = glints.multimesh.mesh.material
		check(material.albedo_texture==asset["texture"] and material.uv1_offset.is_equal_approx(Vector3(0.3125,0.478515625,0)),"Sample the original atlas frame")
	glints.sync([chest],width,snapshot["tick"],Rect2i(-20,-20,3,3))
	check(glints.multimesh.visible_instance_count==0,"Culling a chest must clear its particles from the draw")
	glints.sync([],width,snapshot["tick"]+1,region)
	check(glints._chests.is_empty() and glints.multimesh.visible_instance_count==0,"A removed chest must drop its visual state")
	var exposed := chest.duplicate(true)
	exposed["glint"]["depth"]=0.0
	glints.sync([exposed],width,snapshot["tick"]+2,region)
	glints.advance(8.1,camera)
	check(glints._chests[chest["id"]]["emitters"].is_empty(),"Exposed terrain must not start a new buried chest cue")
	glints.free()
	camera.free()
	print("Original buried chest glints: %d failures"%failures)
	quit(1 if failures else 0)
