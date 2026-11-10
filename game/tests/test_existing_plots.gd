extends SceneTree

const Existing = preload("res://simulation/source_existing_plots.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_existing_plots.json"))
	for example: Dictionary in fixture["cases"]:
		var plot: Dictionary=fixture["plot"].duplicate(true)
		plot["origin_byte"]=int(example["origin_byte"])
		plot["biome_allowed"]=int(example["biome_mask"])==1
		var candidate := Vector2i(int(example["cell"][0]),int(example["cell"][1]))
		var cell_at := func(x: int,z: int) -> Dictionary:
			var is_candidate := Vector2i(x,z)==candidate
			var owner := {"id":1,"claimed":false} if x>=160 and x<164 and z>=120 and z<124 else {}
			if is_candidate:
				match example["owner"]:
					"none": owner={}
					"self": owner={"id":1,"claimed":false}
					"unclaimed": owner={"id":2,"claimed":false}
					"claimed": owner={"id":2,"claimed":true}
			return {"owner":owner,"flat":example["flat"] if is_candidate else true,
				"scenery":example["scenery"] if is_candidate else false,"blocked":example["blocked"] if is_candidate else false,
				"map_byte":int(example["origin_byte"]) if x==160 and z==120 else (int(example["cell_byte"]) if is_candidate else 0),
				"blight":float(example["blight"]) if is_candidate else 0.0}
		var expected: Dictionary=example["expected"]
		check(Existing.cell_valid(plot,cell_at.call(candidate.x,candidate.y))==expected["cell"],"Native existing-plot cell eligibility must match: %s"%example)
		check(Existing.owned_footprint_valid(plot,cell_at)==expected["whole"],"Native whole-footprint ownership and eligibility must match: %s"%example)
		check(Existing.owned_footprint_valid(plot,cell_at,true)==expected["interior"],"Native interior ownership and eligibility must match: %s"%example)
	print("Original existing plot validation: %d cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
