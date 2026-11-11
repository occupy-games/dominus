extends Node3D
## Complete source buildings share draw calls; lifecycle/detail nodes stay intact.
var signature := 0
var builds := 0
var crop_bindings: Dictionary = {}


func update_crops(state: Dictionary) -> void:
	for home: Dictionary in state["homes"]:
		if not crop_bindings.has(int(home["id"])): continue
		var ripeness := clampf(float(home.get("harvest_accumulator",0))/maxf(1,float(home.get("max_belief",1))),0,1)
		for binding: Dictionary in crop_bindings[int(home["id"])]: binding["multi"].set_instance_custom_data(binding["index"],Color(ripeness,0,0,1))


func update(state: Dictionary,nodes: Dictionary) -> void:
	var key: Array=[]
	for home: Dictionary in state["homes"]:
		if not nodes.has(home["id"]): continue
		key.append([home["id"],home.get("model_id",""),nodes[home["id"]].transform,home["progress"]>=int(home.get("build_ticks",state.get("build_ticks",60)))])
	var next := key.hash()
	if next==signature:
		update_crops(state)
		return
	signature=next
	var groups := {}
	for home: Dictionary in state["homes"]:
		if not nodes.has(home["id"]) or home["progress"]<int(home.get("build_ticks",state.get("build_ticks",60))): continue
		var building: Node3D=nodes[home["id"]]
		if not building.has_method("set_stage"): continue
		for component: Dictionary in building.components:
			var node: MeshInstance3D=component["node"]
			if not node.visible: continue
			var id: String=node.get_meta("source_model_id")
			if not groups.has(id): groups[id]={"mesh":node.mesh,"material":node.material_override,"transforms":[],"homes":[],"crop":node.get_meta("crop_shader",false)}
			groups[id]["transforms"].append(building.transform*node.transform)
			groups[id]["homes"].append(int(home["id"]))
	for child: Node in get_children(): child.queue_free()
	crop_bindings.clear()
	for group: Dictionary in groups.values():
		var multi := MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.use_custom_data=group["crop"]
		multi.mesh=group["mesh"]
		multi.instance_count=group["transforms"].size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i,group["transforms"][i])
			if group["crop"]:
				var id: int = group["homes"][i]
				if not crop_bindings.has(id): crop_bindings[id]=[]
				crop_bindings[id].append({"multi":multi,"index":i})
		var batch := MultiMeshInstance3D.new()
		batch.multimesh=multi
		batch.material_override=group["material"]
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	builds+=1
	update_crops(state)
