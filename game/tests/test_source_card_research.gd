extends SceneTree

const Research = preload("res://simulation/source_card_research.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0
var events: Array=[]


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		if failures<15: push_error(message)


func service(name: String,args: Array) -> Variant:
	events.append([name,args.duplicate(true)])
	return 12345 if name=="context" else null


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_card_research.json")))
	var source := preload("res://infrastructure/card_research.gd").content(fixture["executable_sha256"],fixture["source_sha256"],"initialworldsetup6")
	check(not source.is_empty(),"Source research requires matching executable/table provenance")
	check(preload("res://infrastructure/card_research.gd").content("wrong",fixture["source_sha256"],"initialworldsetup6").is_empty(),"Mismatched research provenance must remain unavailable")
	if source.is_empty(): quit(1); return
	var rules: Dictionary=source["rules"]
	var limits := {"unregistered_limit":268435455}
	var codec := preload("res://infrastructure/world_store.gd").new()
	var transitions := 0
	for example: Dictionary in fixture["cases"]:
		transitions+=example["steps"].size()
		for with_save: bool in [false,true]:
			var state := Availability.restore(example["availability"])
			var context := {"cache_valid":example.get("cache_valid",true)}
			for i in range(example["steps"].size()):
				var step: Dictionary=example["steps"][i]
				var card: Dictionary=example["cards"][int(step.get("card",0))]
				var id := int(step.get("sticker",60))
				var value: Variant=null
				var availability_events: Array=[]
				events=[]
				match step["action"]:
					"register": value=Availability.register(state,int(step["key"]),int(step["stock"]),int(step["acquisition"]))
					"research_key": value=Research.research_key(state,card,rules)
					"combination_key": value=Research.combination_key(state,card,id,rules)
					"completion_key": value=Research.completion_key(state,card,rules)
					"completed": value=Research.completed(state,card,rules)
					"progress": value=Research.progress(state,card,rules)
					"remaining": value=Research.remaining(state,card,rules)
					"ready": value=Research.ready(state,card,rules)
					"can_assign": value=Research.can_assign(state,card,example["stickers"],id,step.get("allow_internal",false),rules)
					"assign": value=Research.assign(state,card,example["stickers"],id,step.get("allow_internal",false),rules,limits,availability_events,service,example.get("exempt",[0]))
					"complete": value=Research.complete(state,card,context,int(example.get("player",0)),rules,limits,availability_events,service,example.get("exempt",[0]))
				var actual := {"value":value,"availability":state,"events":events,"availability_events":availability_events,"cache_valid":context["cache_valid"]}
				var expected: Dictionary=example["states"][i]
				check(Numbers.canonical_numbers(actual)==Numbers.canonical_numbers(expected),"Original %s step %d %s: %s / %s"%[example["name"],i,step["action"],actual,expected])
				if with_save:
					var decoded: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"availability":state,"context":context}))))
					state=Availability.restore(decoded["availability"])
					context=decoded["context"].duplicate(true)
					check(not state.is_empty(),"Research counters must survive restoration after every mutation")
	var original := Availability.initial()
	var detached := Availability.restore(original)
	Research.remaining(detached,source["cards"][0],rules)
	check(original==Availability.initial() and detached!=original,"Detached research inspection cannot register counters in the authoritative inventory")
	check(not Research.valid_card({}) and not Research.valid_sticker({}) and not Research.valid_rules({}),"Missing source research records must remain unavailable")
	print("Original card research: %d cases, %d transitions, save continuation, %d failures"%[fixture["cases"].size(),transitions,failures])
	quit(1 if failures else 0)
