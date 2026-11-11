extends MultiMeshInstance3D
## Original surface particles, grouped into one draw for the visible chests.

const Emission = preload("res://presentation/world/beautify_emission.gd")

var _asset: Dictionary = {}
var _chests: Dictionary = {}
var _visible: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()
var _colors: Array[Color] = []
var _offset := Vector3.ZERO
var _scale := 0.0
var _tick := -1


func configure(asset: Dictionary) -> void:
	if asset.is_empty():
		return
	_asset = asset
	var emitter: Dictionary = asset["emitter"]
	var uv: Array = emitter["frames"][0]["uv"]
	var offset: Array = asset["scene"]["offset_xyz"]
	_offset = Vector3(offset[0],offset[2],offset[1])
	_scale = float(asset["scene"]["scale"])
	_colors.clear()
	var opacity: float = emitter["scalar_curves"]["0xdd4"]["cache"]["primary"]["values"][0]
	var alpha := clampi(int(100.0*opacity*float(asset["curve_constants"]["opacity_byte_scale"])),0,255)
	for argb: int in emitter["color_cache"]:
		_colors.append(Color.hex(((argb&0xffffff)<<8)|alpha))
	var material := StandardMaterial3D.new()
	material.albedo_texture = asset["texture"]
	material.uv1_offset = Vector3(uv[0],uv[1],0)
	material.uv1_scale = Vector3(uv[2]-uv[0],uv[3]-uv[1],1)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func sync(chests: Array, width: int, tick: int, region: Rect2i, water_height: float = 0.0) -> void:
	if _asset.is_empty():
		return
	if tick<_tick:
		_chests.clear()
	_tick = tick
	_visible.clear()
	var current := {}
	var center := (width-1)*0.5
	var delay: Array = _asset["timing"]["delay"]
	var threshold: float = _asset["timing"]["height_threshold"]
	for chest: Dictionary in chests:
		var surface: Dictionary = chest.get("glint",{})
		if surface.is_empty():
			continue
		var id: String = chest["id"]
		var entry: Dictionary = _chests.get(id,{})
		if entry.is_empty():
			var interval := float(surface["initial_delay"]) if surface.has("initial_delay") else _random.randf_range(delay[0],delay[1])
			entry = {"remaining":interval,"emitters":[]}
		entry["position"] = Vector3(float(chest["x"])-center,maxf(surface["height"],water_height),float(chest["z"])-center)+_offset
		entry["buried"] = float(surface["depth"])+threshold>0.0
		current[id] = entry
		if region.has_point(Vector2i(int(chest["x"]),int(chest["z"]))):
			_visible.append(entry)
		else:
			entry["emitters"].clear()
	_chests = current
	if _visible.is_empty():
		multimesh.visible_instance_count = 0


func advance(seconds: float, camera: Camera3D) -> void:
	if _visible.is_empty() or seconds<=0.0:
		return
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var axes := camera.global_transform.basis
	var delay: Array = _asset["timing"]["delay"]
	var percent: float = _asset["curve_constants"]["percent"]
	var color_scale: float = _asset["emitter"]["color_time_scale"]
	for entry: Dictionary in _visible:
		var emitters: Array = entry["emitters"]
		if not camera.is_position_in_frustum(entry["position"]):
			emitters.clear()
			continue
		entry["remaining"] -= seconds
		if entry["remaining"]<0.0:
			entry["remaining"] = _random.randf_range(delay[0],delay[1])
			if entry["buried"]:
				var playback := Emission.new(_asset["emitter"],_asset["emission_rng"],percent,_random.randi())
				emitters.append({"playback":playback,"origin":entry["position"]})
		for effect_index in range(emitters.size()-1,-1,-1):
			var effect: Dictionary = emitters[effect_index]
			var playback: RefCounted = effect["playback"]
			playback.advance(seconds*1000.0)
			if playback.is_finished():
				emitters.remove_at(effect_index)
				continue
			for particle: Dictionary in playback.particles.values():
				var size := float(particle["size"])*_scale
				var height := size*float(particle["aspect"])
				if size<=0.0 or height<=0.0:
					continue
				var angle := deg_to_rad(float(particle["rotation_degrees"]))
				var sine := sin(angle)
				var cosine := cos(angle)
				var basis := Basis((axes.x*cosine+axes.y*sine)*size,(axes.y*cosine-axes.x*sine)*height,axes.z)
				var particle_position: Vector3 = effect["origin"]+particle["offset"]*_scale
				transforms.append(Transform3D(basis,particle_position))
				var phase := float(particle["color_phase"])*color_scale
				phase -= 100.0*int(phase*percent)
				var index := clampi(int(phase*float(_colors.size()-1)*percent),0,_colors.size()-1)
				colors.append(_colors[index])
	var capacity := maxi(1,multimesh.instance_count)
	while capacity<transforms.size():
		capacity *= 2
	if capacity>multimesh.instance_count and not transforms.is_empty():
		multimesh.instance_count = capacity
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index,transforms[index])
		multimesh.set_instance_color(index,colors[index])
	multimesh.visible_instance_count = transforms.size()
