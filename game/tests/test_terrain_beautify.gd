extends SceneTree

const World = preload("res://simulation/world.gd")
const WorldView = preload("res://presentation/world/world_view.gd")
const EffectTexture = preload("res://presentation/world/land_effect_texture.gd")
const MapFields = preload("res://simulation/source_map_fields.gd")

var failures := 0


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)


func frame(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func run() -> void:
	var definition := preload("res://tests/fixtures/campaign_economy.gd").definition()
	definition["followers"]=[{"x":8,"z":8}]
	definition["progression_rules"]["config"]["LE_TIMER_TICK_LENGTH"]=0.125
	definition["progression_rules"]["config"]["BEAUTIFY_TIMEOUT"]=0.5
	definition["progression_rules"]["chests"]=[{"id":"beautify","type":"treasure1","x":8,"z":8,"depth":0,"source_height":4,"card":"Card_GodPower_Beautify","rotation":0}]
	var world := World.new()
	var random := RandomNumberGenerator.new()
	random.seed=26
	world.initialize({"campaign_data":definition},random)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(256,256)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := WorldView.new()
	var palette: Texture2D=load("res://assets/extracted/sprites/colours_DNA.png")
	view.terrain.colors=[palette.get_image().get_pixel(54,41)]
	viewport.add_child(view)
	view.apply_snapshot(world.snapshot())
	view.set_process(false)
	view.camera.position=Vector3(0.5,20,0.5)
	view.camera.rotation=Vector3(-PI/2,0,0)
	view.camera.size=10.0
	var mesh: Mesh=view.terrain.mesh
	var material: ShaderMaterial=view.terrain.terrain_material()
	var render := DisplayServer.get_name()!="headless"
	var before: Image=await frame(viewport) if render else null
	var command := {"type":"use_power","power":"GodPower_Beautify","x":32,"z":32}
	world.step([{"type":"open_chest","id":"beautify"}])
	check(world.inspect(command)["ok"],"The reward and source progression must enable the paid cast")
	world.step([command])
	var painted := world.snapshot()
	view.apply_snapshot(painted)
	var field := EffectTexture.image_for(64,EffectTexture.fields_for(painted))
	check(field!=null,"A paid cast must produce a visible terrain field")
	if field==null:
		quit(1)
		return
	var bytes := field.get_data()
	check(bytes[31*64+31]==128 and bytes[32*64+32]==128 and bytes[33*64+33]==128 and bytes[32*64+29]==0,"The paint must project at the correct coordinates across tile boundaries")
	var texture: ImageTexture=view.terrain.land_effect_texture
	check(texture!=null and material.get_shader_parameter("beautify_enabled")==true and view.terrain.mesh==mesh,"A paid cast must bind the effect without rebuilding terrain geometry")
	view.apply_snapshot(world.snapshot())
	check(view.terrain.land_effect_texture==texture,"Unchanged field snapshots must keep the texture")
	if render:
		var painted_frame := await frame(viewport)
		var bright := 0
		for z in range(75,182):
			for x in range(75,182):
				if painted_frame.get_pixel(x,z).get_luminance()>before.get_pixel(x,z).get_luminance()+0.01:
					bright+=1
		check(bright>0 and painted_frame.get_pixel(16,16)==before.get_pixel(16,16),"The original shader must brighten only the painted area")
		await create_timer(0.15).timeout
		var animated := await frame(viewport)
		check(animated.get_data()!=painted_frame.get_data(),"The source mask must animate while the simulation is held")
	var clone := World.new()
	check(clone.restore(world.export_state(),RandomNumberGenerator.new()),"The painted campaign must restore")
	var restored := WorldView.Terrain.new()
	restored.apply_land_effects(clone.snapshot(false))
	check(restored.land_effect_texture!=null,"A fresh view must render an already painted save")
	restored.free()
	var blocked: Dictionary=painted.duplicate(true)
	MapFields.write_byte(blocked["map_fields"],3,32,32,128)
	var conflict := EffectTexture.image_for(64,EffectTexture.fields_for(blocked))
	check(conflict.get_data()[32*64+32]==0 and field.get_data()[32*64+32]==128,"Blight can mask beauty without altering the detached campaign fields")
	for tick in range(5): clone.step()
	var expired := clone.snapshot()
	view.apply_snapshot(expired)
	check(view.terrain.land_effect_texture==null and material.get_shader_parameter("beautify_enabled")==false and view.terrain.mesh==mesh,"The view must remove expired beauty without rebuilding terrain geometry")
	if render:
		var after := await frame(viewport)
		check(after.get_data()==before.get_data(),"Expiry must restore the original rendered surface")
		print("Rendered Beautify changes only its terrain and clears on expiry")
	viewport.queue_free()
	await process_frame
	print("Original terrain Beautify, reload and expiry: %d failures"%failures)
	quit(1 if failures else 0)
