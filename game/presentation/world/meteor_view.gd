extends Node3D
## Displays the original streak texture on its source strip and plays the impact flare.

const TEXTURES := "res://assets/extracted/"
const TICK_SECONDS := 0.1
const STRIP_TRIANGLES := [0,1,2,1,3,2,2,3,4,3,5,4]
var rules: Dictionary={}
var streak := MeshInstance3D.new()
var strip := ImmediateMesh.new()
var streak_material: StandardMaterial3D
var flare_mesh: QuadMesh
var flare_material: StandardMaterial3D
var tracks: Dictionary={}
var flares: Array=[]
var last_tick := -1
var center := 0.0
var sea_height := 0.0


func _ready() -> void:
	streak.mesh=strip
	streak.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak.hide()
	add_child(streak)


func material_for(asset: Dictionary) -> StandardMaterial3D:
	var path: String=TEXTURES+str(asset["path"])
	if not ResourceLoader.exists(path): return null
	var material:=StandardMaterial3D.new()
	material.albedo_texture=load(path) as Texture2D
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return material


func configure(source: Dictionary) -> void:
	rules=source.get("visuals",{})
	sea_height=float(source.get("sea_height",0.0))
	if rules.is_empty(): return
	streak_material=material_for(rules["streak"])
	flare_material=material_for(rules["flare"])
	if flare_material==null: return
	flare_material.albedo_color=Color.html(rules["flare"]["color"])
	flare_material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	flare_mesh=QuadMesh.new()
	flare_mesh.size=Vector2.ONE*float(rules["flare"]["size"])


func apply_snapshot(state: Dictionary) -> void:
	var opening: Dictionary=state.get("opening",{})
	var source: Dictionary=opening.get("definition",{}).get("meteor",{})
	if rules.is_empty() and source.has("visuals"): configure(source)
	if streak_material==null or last_tick==int(state["tick"]): return
	last_tick=int(state["tick"])
	center=(float(state["width"])-1.0)*0.5
	var next: Dictionary={}
	for flight: Dictionary in opening.get("meteor_flights",[]):
		if flight["phase"]!="flight": continue
		var id: int=flight["id"]
		var velocity: Array=flight["velocity"]
		var motion:=Vector3(velocity[0],velocity[1],velocity[2])
		var position_: Array=flight["position"]
		var target:=world_position(position_[0],position_[1],position_[2])
		var previous: Dictionary=tracks.get(id,{})
		var start:=target-motion*TICK_SECONDS if previous.is_empty() else current_position(previous)
		next[id]={"from":start,"to":target,"heading":motion.normalized(),"elapsed":0.0}
	tracks=next
	if tracks.is_empty(): streak.hide()


func world_position(x: float,y: float,z: float) -> Vector3:
	return Vector3(x-center,y-sea_height,z-center)


func current_position(track: Dictionary) -> Vector3:
	var from: Vector3=track["from"]
	return from.lerp(track["to"],minf(1.0,float(track["elapsed"])/TICK_SECONDS))


func impact(event: Dictionary) -> void:
	if flare_material==null: return
	var node:=MeshInstance3D.new()
	node.mesh=flare_mesh
	node.material_override=flare_material.duplicate()
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position=world_position(event["x"],event["y"],event["z"])
	add_child(node)
	flares.append({"node":node,"elapsed":0.0})
	set_flare_alpha(node,0.0)


func set_flare_alpha(node: MeshInstance3D,elapsed: float) -> void:
	var keys: Array=rules["flare"]["alpha"]
	var alpha: float=keys[0][1]
	for i in range(1,keys.size()):
		if elapsed<=float(keys[i][0]):
			alpha=lerpf(keys[i-1][1],keys[i][1],clampf(inverse_lerp(keys[i-1][0],keys[i][0],elapsed),0.0,1.0))
			break
		alpha=keys[i][1]
	var material: StandardMaterial3D=node.material_override
	var color:=material.albedo_color
	color.a=alpha
	material.albedo_color=color


func advance(delta: float,camera: Camera3D) -> void:
	if not tracks.is_empty():
		strip.clear_surfaces()
		strip.surface_begin(Mesh.PRIMITIVE_TRIANGLES,streak_material)
		for track: Dictionary in tracks.values():
			track["elapsed"]+=delta
			append_strip(current_position(track),track["heading"],camera)
		strip.surface_end()
		streak.show()
	for flare: Dictionary in flares.duplicate():
		flare["elapsed"]+=delta
		if float(flare["elapsed"])>=float(rules["flare"]["lifetime"]):
			flare["node"].queue_free()
			flares.erase(flare)
		else: set_flare_alpha(flare["node"],flare["elapsed"])


func append_strip(head: Vector3,heading: Vector3,camera: Camera3D) -> void:
	var length: float=rules["streak"]["length"]
	var tail:=head-heading*length
	var neck:=head-heading*length*float(rules["streak"]["head_ratio"])
	var side:=heading.cross((head+tail)*0.5-camera.global_position).normalized()
	if side.is_zero_approx(): side=camera.global_basis.x
	var vertices:=[tail-side,tail+side,neck-side,neck+side,head-side,head+side]
	var v:=[1.0,float(rules["streak"]["head_v"]),0.0]
	for index: int in STRIP_TRIANGLES:
		@warning_ignore("integer_division")
		strip.surface_set_uv(Vector2(index%2,v[index/2]))
		strip.surface_add_vertex(vertices[index])
