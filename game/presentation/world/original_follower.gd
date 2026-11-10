extends Node3D
## Source geometry, skin weights and sampled source animation transforms.

var assets: Dictionary
var variant := 0
var animation_state := "idle"
var playback_speed := 1.0
var visual_scale := 0.003
var rig := Skeleton3D.new()
var clip_time := 0.0
var last_clip := ""
var cue_audio: Node
var looped := true
var animation_interval := 0.0
var animation_elapsed := 0.0
var previous_interval := -1.0
static var mesh_cache: Dictionary = {}
static var skin_cache: Dictionary = {}
static var material_cache: Dictionary = {}


func _ready() -> void:
	if not assets.get("audio_events", {}).is_empty():
		cue_audio = preload("res://presentation/world/source_audio.gd").new()
		cue_audio.assets = assets["audio_events"]
		add_child(cue_audio)
	scale = Vector3.ONE * visual_scale
	rig.name = "Rig"
	add_child(rig)
	var bones: Array = assets["bones"]
	for bone: Dictionary in bones:
		rig.add_bone(bone["name"])
	for i in range(bones.size()):
		var bone: Dictionary = bones[i]
		rig.set_bone_parent(i, int(bone["parent"]))
		var transform := Transform3D(Basis(source_quaternion(bone["rotation"])), vector(bone["position"]))
		rig.set_bone_rest(i, transform)
		rig.set_bone_pose_position(i, transform.origin)
		rig.set_bone_pose_rotation(i, transform.basis.get_rotation_quaternion())
	var data: Dictionary = assets["models"][variant % assets["models"].size()]
	install_part(data)
	for part: Dictionary in assets.get("attachments",[]): install_part(part)
	# Source walk clips advance along +Z; presentation actors face -Z.
	rig.rotation.y = PI
	apply_animation(0.0)


func install_part(data: Dictionary) -> void:
	var bones: Array = assets["bones"]
	var cache_key: String=data.get("descriptor",{}).get("id","")
	if cache_key.is_empty(): cache_key=str(assets.get("source",""))+":"+str(data.get("name",data.get("resource_id",variant)))
	if not mesh_cache.has(cache_key):
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		var bone_indices := PackedInt32Array()
		var weights := PackedFloat32Array()
		for vertex: Array in data["vertices"]:
			vertices.append(vector(vertex))
		for normal: Array in data["normals"]:
			normals.append(vector(normal).normalized())
		for uv: Array in data["uvs"]:
			uvs.append(Vector2(uv[0], uv[1]))
		for index: int in data["indices"]:
			indices.append(index)
		for binding: Dictionary in data["bindings"]:
			for i in range(4):
				bone_indices.append(int(binding["bones"][i]) if i < binding["bones"].size() else 0)
				weights.append(float(binding["weights"][i]) if i < binding["weights"].size() else 0.0)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		arrays[Mesh.ARRAY_BONES] = bone_indices
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var skin := Skin.new()
		for i in range(bones.size()):
			skin.add_bind(i, rig.get_bone_global_rest(i).affine_inverse())
		mesh_cache[cache_key]=mesh
		skin_cache[cache_key]=skin
	var instance := MeshInstance3D.new()
	instance.name = "OriginalSourceMesh"
	instance.mesh = mesh_cache[cache_key]
	instance.skin = skin_cache[cache_key]
	instance.skeleton = NodePath("../Rig")
	if not material_cache.has(cache_key):
		var material := StandardMaterial3D.new()
		material.albedo_texture = data.get("texture_resource")
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_cache[cache_key]=material
	instance.material_override=material_cache[cache_key]
	instance.rotation.y=PI
	instance.set_meta("visible_states",data.get("visible_states",[]))
	add_child(instance)


static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


static func source_quaternion(values: Array) -> Quaternion:
	return Quaternion(values[1], values[2], values[3], values[0]).normalized()


func apply_animation(delta: float) -> void:
	for child: Node in get_children():
		if child is MeshInstance3D:
			var states: Array = child.get_meta("visible_states",[])
			child.visible=states.is_empty() or animation_state in states
	var key := animation_state if assets["clips"].has(animation_state) else "idle"
	var before := clip_time
	if key != last_clip:
		clip_time = 0.0
		before = -0.00001
		if is_instance_valid(cue_audio): cue_audio.stop_effects()
		last_clip = key
	var clip: Dictionary = assets["clips"][key]
	clip_time = fmod(clip_time + delta * playback_speed, float(clip["duration"])) if looped else minf(clip_time+delta*playback_speed,float(clip["duration"]))
	if delta > 0 and is_instance_valid(cue_audio):
		var cues: Array = assets.get("audio_cues", {}).get(key, [])
		if clip_time < before:
			cue_audio.advance(cues, before, float(clip["duration"]))
			before = -0.00001
		cue_audio.advance(cues, before, clip_time)
	var frames: Array = clip["frames"]
	var index := 0
	while index + 1 < frames.size() - 1 and float(frames[index + 1]["time"]) <= clip_time:
		index += 1
	var a: Dictionary = frames[index]
	var b: Dictionary = frames[index + 1]
	var blend := inverse_lerp(float(a["time"]), float(b["time"]), clip_time)
	for i in range(rig.get_bone_count()):
		var from: Array = a["poses"][i]
		var to: Array = b["poses"][i]
		var position := vector(from).lerp(vector(to), blend)
		if i == 0:
			position.x = 0
			position.z = 0
		var rotation := Quaternion(from[4], from[5], from[6], from[3]).normalized().slerp(Quaternion(to[4], to[5], to[6], to[3]).normalized(), blend)
		rig.set_bone_pose_position(i, position)
		rig.set_bone_pose_rotation(i, rotation)


func _process(delta: float) -> void:
	if animation_interval!=previous_interval:
		previous_interval=animation_interval
		animation_elapsed=fposmod(variant*0.61803398875,1.0)*animation_interval
	animation_elapsed+=delta
	if animation_elapsed+0.000001<animation_interval: return
	apply_animation(animation_elapsed)
	animation_elapsed=0.0
