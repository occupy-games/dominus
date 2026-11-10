extends SceneTree

const World = preload("res://simulation/world.gd")
var failures := 0


func _initialize() -> void:
	create_timer(15).timeout.connect(func() -> void: quit(1))
	run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func fixture() -> RefCounted:
	var world := World.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	world.initialize({}, rng)
	var data := world.export_state()
	for z in range(34):
		for x in range(34):
			data["state"]["terrain"][z * 34 + x] = 4 if x >= 12 and x <= 18 and z >= 12 and z <= 18 else (3 if x >= 8 and x <= 22 and z >= 8 and z <= 22 else 0)
	check(world.restore(data, RandomNumberGenerator.new()), "Layer fixture must restore")
	return world


func run() -> void:
	var flat := PackedByteArray()
	flat.resize(128*128)
	flat.fill(4)
	var palette: Array[Color] = [Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE]
	var arrays: Array = preload("res://presentation/world/terrain_geometry.gd").build({"width":128,"terrain":flat},Rect2i(16,16,64,64),palette)
	check(not arrays.is_empty() and not arrays[Mesh.ARRAY_VERTEX].is_empty(),"A completely flat streamed tile must render its cap even when it has no terrace edges")
	if not arrays.is_empty():
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: check(is_equal_approx(vertex.y,1.2),"Flat caps must keep the authoritative terrain height")
	var world := fixture()
	var before: Dictionary = world.snapshot()
	var drag := {"type": "sculpt_drag", "x": 22, "z": 15, "nx": 1, "nz": 0, "layer": 3, "distance": 3, "dx": 3, "dz": 2, "radius": 1}
	var preview: Dictionary = world.inspect(drag)
	check(preview.get("ok", false), "A diagonal layer extension must be valid")
	world.step([drag])
	check(world.height_at(25, 17) == 3, "A free-direction drag must extend geometry along both axes")
	check(world.height_at(16, 16) == 4, "Extending a lower layer must preserve unrelated higher terrain")
	check(world.snapshot()["belief"] == before["belief"] - preview["cost"], "Overlapping sweep samples must not double-charge cells")
	# Check that every edited cell connects to the original layer by orthogonal steps.
	var reached: Dictionary = {Vector2i(22, 15): true}
	var frontier: Array[Vector2i] = [Vector2i(22, 15)]
	var cursor := 0
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = current + direction
			if not reached.has(next) and world.height_at(next.x, next.y) >= 3:
				reached[next] = true
				frontier.append(next)
	for edit: Dictionary in preview["edits"]:
		check(reached.has(Vector2i(edit["cell"] % 34, int(edit["cell"] / 34))), "Diagonal layer drags must not leave disconnected cells")
	world = fixture()
	drag = {"type": "sculpt_drag", "x": 22, "z": 15, "nx": 1, "nz": 0, "layer": 3, "distance": -7, "radius": 0}
	world.step([drag])
	check(world.height_at(16, 15) == 2 and world.height_at(16, 16) == 4, "Retraction must remove the grabbed layer and overlying columns only inside the sweep")
	world = fixture()
	world.step([{"type": "home", "x": 20, "z": 14}])
	check(world.snapshot()["homes"].size() == 1, "Protected-plot fixture must reserve a home")
	before = world.snapshot()
	world.step([{"type": "sculpt_drag", "x": 22, "z": 15, "nx": 1, "nz": 0, "layer": 3, "distance": -3, "radius": 0}])
	check(world.snapshot()["terrain"] == before["terrain"] and world.snapshot()["belief"] == before["belief"], "A sweep intersecting a home must reject every edit without spending belief")
	var poor: Dictionary = world.export_state()
	poor["state"]["belief"] = 0
	check(world.restore(poor, RandomNumberGenerator.new()), "Zero-belief state must restore")
	before = world.snapshot()
	world.step([{"type": "sculpt_drag", "x": 22, "z": 10, "nx": 1, "nz": 0, "layer": 3, "distance": 2, "radius": 0}])
	check(world.snapshot()["terrain"] == before["terrain"], "Unaffordable drags must not modify geometry")
	for i in range(30): world.step()
	check(world.snapshot()["belief"] > 0, "Passive belief must recover a world after overspending")
	print("Terrain layer geometry: %d failures" % failures)
	quit(1 if failures else 0)
