extends Node3D
## The original model follows the pointer while armed and animates saved strokes.

const Actors = preload("res://presentation/world/actors.gd")
var mesh: MeshInstance3D
var stroke: Dictionary = {}
var descent_time := 0.0
var ascent_time := 0.0


func strike(event: Dictionary) -> void:
	stroke={"point":Vector2(event["x"],event["z"]),"ground":event["ground"]}
	descent_time=0.0
	ascent_time=0.0


func advance(delta: float,cast: Dictionary,rules: Dictionary,point: Vector2,world: Node3D) -> void:
	if cast.is_empty() or rules.is_empty() or (point.x<0 and stroke.is_empty()):
		hide()
		stroke.clear()
		return
	if not is_instance_valid(mesh):
		if not world.resolve_model.is_valid(): return
		var source: Dictionary=world.resolve_model.call(rules["model"])
		if source.is_empty(): return
		mesh=Actors.mesh(source)
		var rotation := Basis(Vector3.UP,-float(rules["rotation_z"]))*Basis(Vector3.RIGHT,-float(rules["rotation_x"]))
		mesh.basis=rotation.scaled(Vector3.ONE*float(rules["model_scale"]))
		add_child(mesh)
	var rest: float=rules["rest_height"]
	var height := rest
	var ground: float=world.world_position(point.x,point.y).y
	if not stroke.is_empty():
		point=stroke["point"]
		ground=stroke["ground"]
		descent_time+=delta
		height=maxf(0.0,rest-travel(descent_time,rules))
		if height==0 and cast["phase"] in ["rest","rising"]:
			ascent_time+=delta
			height=minf(rest,travel(ascent_time,rules))
			if height>=rest: stroke.clear()
	var at: Vector3=world.world_position(point.x,point.y)
	position=Vector3(at.x+float(rules["target_offset_x"]),ground+height+float(rules["hover_height"]),
		at.z+float(rules["target_offset_z"]))
	show()


func travel(seconds: float,rules: Dictionary) -> float:
	# Native travel accelerates once per update and caps both directions.
	# Interpolate those positions between display frames.
	var frames := minf(seconds*60.0,10.0)
	var whole := floori(frames)
	var acceleration: float=rules["acceleration"]
	var limit: float=rules["max_velocity"]
	var distance := 0.0
	for frame in range(1,whole+1): distance+=minf(limit,frame*acceleration)
	return distance+(frames-whole)*minf(limit,(whole+1)*acceleration)
