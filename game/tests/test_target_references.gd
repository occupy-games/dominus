extends SceneTree

const References = preload("res://simulation/source_target_references.gd")
const Numbers = preload("res://simulation/progression.gd")
const Terrain = preload("res://simulation/source_terrain.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func reference(spec: Dictionary,context: Dictionary) -> Dictionary:
	var kind := int(spec.get("kind",1))
	var entity := int(spec.get("entity",0))
	var identity := int(context["houses"][str(entity)]["identity"]) if kind==1 and entity>=0 else kind<<24
	var position: Array=spec.get("position",[-1.0,-1.0]).duplicate()
	if kind==7 and entity>=0 and not spec.has("position"):
		var plot: Dictionary=context["plots"][str(entity)]
		position=[float(plot["x"])+int(plot["size"])*0.5,float(plot["z"])+int(plot["size"])*0.5]
	return {"identity":int(spec.get("identity",identity)),"entity":entity,"position":[Terrain.f32(float(position[0])),Terrain.f32(float(position[1]))],"flag":bool(spec.get("flag",true))}


func execute(example: Dictionary,rules: Dictionary,resume: bool) -> Array:
	var context := {"houses":{},"plots":{}}
	var houses: Array=example.get("houses",[{"identity":16777217}])
	for i in range(houses.size()): context["houses"][str(i)]={"identity":int(houses[i].get("identity",16777217+i)),"settlement_index":int(houses[i].get("settlement_index",-1)),"profession":int(houses[i].get("profession",0))}
	var plots: Array=example.get("plots",[{"x":158.0,"z":120.0,"size":4}])
	for i in range(plots.size()): context["plots"][str(i)]=plots[i].duplicate(true)
	var follower := {} if example.get("no_actor",false) else {"home":int(example.get("home",-1)),"settlement_index":int(example.get("settlement_index",-1)),"profession":int(example.get("profession",0)),"owner":int(example.get("owner",0))}
	var target := References.initial(rules)
	if example.has("initial_target"): target=reference(example["initial_target"],context)
	var counters := References.counters_initial()
	for group: String in ["houses","plots","settlements"]: counters[group]=example.get("counters",{}).get(group,{}).duplicate(true)
	for group: String in ["houses","plots"]:
		for row: Array in counters[group].values(): row[2]=Terrain.f32(float(row[2]))
	var calls := {"skill":0}
	var skill := func() -> float:
		calls["skill"]+=1
		return float(example["skills"][int(calls["skill"])-1]) if example.has("skills") else float(example.get("skill",1.0))
	var states: Array=[]
	for step: Dictionary in example["steps"]:
		if resume:
			var codec := preload("res://infrastructure/world_store.gd").new()
			var encoded: Variant=codec.encode_numbers({"target":target,"follower":follower,"context":context,"counters":counters})
			var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(encoded)))
			target=References.restore(saved["target"])
			follower=saved["follower"]
			context=saved["context"]
			counters=References.restore_counters(saved["counters"])
			check(not target.is_empty() and References.valid_counters(counters),"Source target and worker state must restore before the next transition")
		if step.get("type","assign")=="clear": References.clear(target,follower,context,counters,rules,skill)
		else:
			var incoming := reference(step,context)
			var original := incoming.duplicate(true)
			References.assign(target,incoming,follower,context,counters,rules,int(step.get("action",250)),skill,int(example.get("local_owner",0)))
			check(incoming==original,"Native pass-by-value validation must not mutate the caller's incoming target")
		var professions: Array=[]
		for i in range(houses.size()): professions.append(context["houses"][str(i)]["profession"])
		var flags: Array=[]
		for i in range(plots.size()): flags.append(bool(context["plots"][str(i)].get("claimed",false)))
		states.append({"target":target.duplicate(true),"home":int(follower.get("home",example.get("home",-1))),"settlement_index":int(follower.get("settlement_index",example.get("settlement_index",-1))),"house_professions":professions,"plot_claimed":flags,"counters":counters.duplicate(true),"skill_calls":int(calls["skill"])})
	return states


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: quit(1))
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_target_references.json"))
	var rules: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()["story"]["target_reference_rules"]
	check(References.valid_rules(rules),"Target rules must be injected from the original executable")
	var transitions := 0
	for example: Dictionary in fixture["cases"]:
		var expected: Array=example["states"].duplicate(true)
		for state: Dictionary in expected:
			for i in range(2): state["target"]["position"][i]=Terrain.f32(float(state["target"]["position"][i]))
			for group: String in ["houses","plots"]:
				for row: Array in state["counters"][group].values(): row[2]=Terrain.f32(float(row[2]))
		var observed := execute(example,rules,false)
		check(Numbers.canonical_numbers(observed)==Numbers.canonical_numbers(expected),"Native %s target assignment/clear and every counter must match: %s / %s"%[example["name"],observed,expected])
		check(Numbers.canonical_numbers(observed)==Numbers.canonical_numbers(execute(example,rules,true)),"Source %s transitions must preserve exact save-codec continuation"%example["name"])
		transitions+=observed.size()
	var malformed := References.counters_initial()
	malformed["houses"]["0"]=[0,1,NAN]
	check(not References.valid_counters(malformed) and References.restore_counters(malformed).is_empty(),"Non-finite worker skill aggregates must not restore")
	var original := References.initial(rules)
	var restored := References.restore(original)
	restored["position"][0]=4.0
	check(original["position"][0]==-1.0,"Restoring a reference must detach its mutable position")
	print("Original target references: %d cases, %d transitions, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
