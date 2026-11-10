extends SceneTree

const House = preload("res://simulation/source_house_constructor.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)


func bytes(value: Variant,kind: String) -> String:
	var buffer := PackedByteArray()
	buffer.resize(2 if kind=="u16" else 4)
	if kind=="u16": buffer.encode_u16(0,int(value))
	elif kind=="float": buffer.encode_float(0,float(value))
	else: buffer.encode_u32(0,int(value)&0xffffffff)
	return buffer.hex_encode()


func fields(state: Dictionary,strings: Dictionary) -> Dictionary:
	var result := {}
	var direct := {"0x4":["priority","float"],"0x8":["capacity","u16"],"0xa":["build_capacity","u16"],
		"0x14":["timer","float"],"0x1c":["native_mode","u32"],"0x20":["profession","u32"],"0x30":["special","u32"],
		"0x38":["progress","float"],"0x50":["timer","float"],"0x88":["identity","u32"],"0x118":["angle","float"],
		"0xec":["settlement_index","u32"],
		"0x124":["update_after","float"],"0x1c0":["base_seconds","float"],"0x134":["state","u32"],
		"0x13c":["variant","u32"],"0x154":["size","u32"],"0x1d4":["rank_weight","float"],"0x1e8":["location","u32"],
		"0x1f4":["created_seconds","float"],"0x250":["beauty_fraction","float"],"0x264":["house_index","u32"],
		"0x2c0":["resource_flags","u32"],"0x2cc":["mine_value","float"]}
	for key: String in direct:
		result[key]=bytes(state[direct[key][0]],str(direct[key][1]))
	result["0x48"]=bytes(int(state["created_clock"])&0xffffffff,"u32")
	result["0x4c"]=bytes(int(state["created_clock"])>>32,"u32")
	result["0x144"]=bytes(strings[state["category"]],"u32")
	for i in range(3):
		result[["0xb0","0xb4","0xb8"][i]]=bytes(state["position"][i],"float")
		result[["0x244","0x248","0x24c"][i]]=bytes(state["nearby"][i],"u32")
	return result


func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_house_constructor.json"))
	var definition: Dictionary=preload("res://infrastructure/campaign_opening_content.gd").definition()["story"]
	var content: Dictionary=definition["house_constructor"]
	check(content["records"].size()==62 and House.valid_rules(content["rules"]),"All original core initialization inputs must be injected with source constants")
	var codec := preload("res://infrastructure/world_store.gd").new()
	for example: Dictionary in fixture["cases"]:
		var record: Dictionary=content["records"][int(example.get("index",18))]
		var request := {"position":example.get("position",[160.0,122.0,6.02,0.0]),"index":int(example.get("index",18)),
			"owner":int(example.get("owner",0)),"extra":0,"kind":int(example.get("kind",0)),"special":int(example.get("special",false)),
			"unknown_a":int(example.get("silent",0)),"unknown_b":int(example.get("identity",0)),
			"configuration":int(example.get("configuration",4294967295)),"reuse":bool(example.get("reuse",false))}
		var config := {"food_enabled":bool(example.get("food_enabled",false)),"ore_enabled":bool(example.get("ore_enabled",false)),"loc2Start":25.0,"loc3Start":36.0}
		var identities := {"counter":int(example.get("next_identity",0))}
		var samples: Array=[]
		var field := func(channel: String,x: int,z: int) -> float:
			samples.append([int(channel=="blight"),x,z])
			return float(example.get(channel,0.0))
		var mine_queries: Array=[]
		var roll := func(minimum: float,maximum: float) -> float:
			mine_queries.append([minimum,maximum])
			return float(example.get("mine_value",15.0))
		var intents: Array=[]
		var state := House.initialize(request,record,content["rules"],config,identities,int(example.get("clock",123456789)),float(example.get("seconds",12.5)),example.get("nearby",[]),field,roll,intents)
		check(not state.is_empty(),"Native %s initializer must accept source inputs"%example["name"])
		if state.is_empty(): continue
		var expected: Dictionary=example["expected"]
		var expected_fields: Dictionary=expected["fields"].duplicate()
		var observed := fields(state,expected["strings"])
		for key: String in expected_fields:
			check(observed.get(key)==expected_fields[key],"Native %s constructor field %s must match: %s / %s"%[example["name"],key,observed.get(key),expected_fields[key]])
		check(identities["counter"]==int(expected["next_identity"]),"Native %s identity consumption must match"%example["name"])
		check(Numbers.canonical_numbers(state["slots"])==Numbers.canonical_numbers(expected["slots"]),"Native %s initial source slot values must match"%example["name"])
		var hash := HashingContext.new()
		var sampled := PackedByteArray()
		sampled.resize(samples.size()*12)
		for i in range(samples.size()):
			for j in range(3): sampled.encode_s32(i*12+j*4,int(samples[i][j]))
		hash.start(HashingContext.HASH_SHA256)
		hash.update(sampled)
		check(sampled.size()/12==int(expected["field_queries"]["count"]) and hash.finish().hex_encode()==expected["field_queries"]["sha256"],"Native %s must sample the same fields in the same circular order"%example["name"])
		check(Numbers.canonical_numbers(mine_queries)==Numbers.canonical_numbers(expected["mine_queries"]),"Native %s mine random request must match"%example["name"])
		var events: Array=[]
		var spatial: Array=[]
		var rectangles: Array=[]
		var occupied: Array=[]
		for intent: Dictionary in intents:
			var item := intent.duplicate(true)
			item.erase("type")
			if intent["type"]=="source_house_event": events.append(item)
			elif intent["type"]=="source_house_spatial": spatial.append(item)
			else:
				var rectangle: Array=item["rectangle"]
				rectangles.append(rectangle)
				check(rectangle==[state["origin"][0],state["origin"][1],int(state["origin"][0])+int(state["size"]),int(state["origin"][1])+int(state["size"])],"The dirty footprint rectangle must come from authoritative building geometry")
				occupied=House.footprint_cells(state)
		# Normalize native float32 JSON spellings before comparing value arrays.
		for event: Dictionary in expected["events"]:
			for i in range(3): event["position"][i]=float(PackedFloat32Array([event["position"][i]])[0])
		check(Numbers.canonical_numbers(events)==Numbers.canonical_numbers(expected["events"]) and Numbers.canonical_numbers(spatial)==Numbers.canonical_numbers(expected["spatial"]),"Native %s must request the same source event and spatial registration"%example["name"])
		check(Numbers.canonical_numbers(rectangles)==Numbers.canonical_numbers(expected["dirty_rectangles"]) and Numbers.canonical_numbers(occupied)==Numbers.canonical_numbers(expected["occupied"]),"Native %s must occupy exactly the same clipped source footprint"%example["name"])
		var encoded: Variant=codec.encode_numbers({"house":state,"identities":identities})
		var saved: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(encoded)))
		check(Numbers.canonical_numbers(saved)==Numbers.canonical_numbers({"house":state,"identities":identities}),"Native initialized state must preserve exact source scalar values through save/load")
		var restored := House.restore(saved["house"])
		check(House.valid_state(state) and Numbers.canonical_numbers(restored)==Numbers.canonical_numbers(state),"Source initialized house must validate and normalize restored numeric identities")
		restored["slots"][0]=5
		check(state["slots"][0]==-1,"Restoring an initialized building must detach its mutable slots")
		var followup_a: Array=[]
		var followup_b: Array=[]
		var next_a := House.initialize(request,record,content["rules"],config,identities,int(example.get("clock",123456789)),float(example.get("seconds",12.5)),example.get("nearby",[]),field,roll,followup_a)
		var next_b := House.initialize(request,record,content["rules"],config,saved["identities"],int(example.get("clock",123456789)),float(example.get("seconds",12.5)),example.get("nearby",[]),field,roll,followup_b)
		check(Numbers.canonical_numbers(next_a)==Numbers.canonical_numbers(next_b) and Numbers.canonical_numbers(identities)==Numbers.canonical_numbers(saved["identities"]) and Numbers.canonical_numbers(followup_a)==Numbers.canonical_numbers(followup_b),"Creating the next source building must continue identically after save/load")
	var untouched := {"counter":17}
	var bad: Array=[]
	check(House.initialize({},content["records"][18],content["rules"],{},untouched,0,0.0,[],Callable(),Callable(),bad).is_empty() and untouched["counter"]==17 and bad.is_empty(),"Invalid initialization must reject before consuming an identity or emitting events")
	print("Original house core initialization: %d native cases, %d failures"%[fixture["cases"].size(),failures])
	quit(1 if failures else 0)
