extends SceneTree

const Catalog = preload("res://simulation/source_reward_catalog.gd")
const Availability = preload("res://simulation/source_availability.gd")
const Numbers = preload("res://simulation/progression.gd")
var failures := 0


func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		if failures<10: push_error(message)


func _initialize() -> void:
	var fixture: Dictionary=Numbers.canonical_numbers(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_reward_catalog.json")))
	var source := preload("res://infrastructure/reward_catalog.gd").content(fixture["executable_sha256"],fixture["source_sha256"],"initialworldsetup6")
	check(not source.is_empty(),"Fresh source catalog requires matching native/table provenance")
	var opening := preload("res://infrastructure/campaign_opening_content.gd").definition()
	check(opening.get("story",{}).get("reward_catalog",{})==source,"The private campaign must receive its matching complete reward catalog")
	check(preload("res://infrastructure/reward_catalog.gd").content("wrong",fixture["source_sha256"],"initialworldsetup6").is_empty(),"Mismatched catalog provenance must reject")
	check(preload("res://infrastructure/reward_catalog.gd").content(fixture["executable_sha256"],fixture["source_sha256"],"initialworldsetup").is_empty(),"A startup catalog with unresolved source types must remain unavailable")
	if source.is_empty(): quit(1); return
	var rules: Dictionary=source["rules"]
	var codec := preload("res://infrastructure/world_store.gd").new()
	var bindings := 0
	for example: Dictionary in fixture["cases"]:
		bindings+=int(example["steps"])
		for with_save: bool in [false,true]:
			var available := Availability.restore(example["availability"])
			var records: Dictionary=example["records"].duplicate(true)
			for i in range(int(example["steps"])):
				var bound := Catalog.bind(available,records,example["details"],rules)
				check(not bound.is_empty(),"Controlled catalog must bind: "+example["name"])
				if bound.is_empty(): break
				var actual := bound.duplicate(true)
				actual["availability"]=available
				var expected: Dictionary=example["states"][i]
				if Numbers.canonical_numbers(actual)!=Numbers.canonical_numbers(expected):
					var fields: Array=[]
					for field: String in actual:
						if Numbers.canonical_numbers(actual[field])!=Numbers.canonical_numbers(expected[field]): fields.append(field)
					if failures==0:
						var output := FileAccess.open("res://../build/reward-catalog-mismatch.json",FileAccess.WRITE)
						output.store_string(JSON.stringify({"case":example["name"],"step":i,"actual":actual,"expected":expected},"  "))
					check(false,"Original catalog %s binding %d differs in %s"%[example["name"],i,fields])
				records=bound["records"]
				if with_save:
					var stored: Dictionary=codec.decode_numbers(JSON.parse_string(JSON.stringify(codec.encode_numbers({"availability":available,"records":records}))))
					available=Availability.restore(stored["availability"])
					records=Numbers.canonical_numbers(stored["records"])
	var original: Dictionary=source["records"].duplicate(true)
	var available := Availability.initial()
	var bound := Catalog.bind(available,source["records"],source["details"],rules)
	check(not bound.is_empty() and source["records"]==original,"Binding must detach supplied definitions before setting detail references")
	bound["records"]["cards"][0]["name"]="Detached"
	check(source["records"]==original,"Returned catalog rows cannot mutate infrastructure definitions")
	var before := available.duplicate(true)
	var invalid: Dictionary=source["records"].duplicate(true)
	invalid["cards"][0]["max_collectable"]=2147483648
	check(Catalog.bind(available,invalid,source["details"],rules).is_empty() and available==before,"Invalid limits must reject before any capacity writes")
	var rewards := preload("res://simulation/source_rewards.gd").initial()
	var prepared := preload("res://simulation/source_rewards.gd").prepare_catalog(rewards,source,[])
	check(not prepared.is_empty() and prepared["registry"]==bound["registry"] and prepared["detail_registry"]==bound["details"],"Prepared rewards must retain original registry and detail identities")
	var malformed := source.duplicate(true)
	malformed["records"]["packs"][0]["slots"][0].merge({"reward":malformed["records"]["packs"][0]["id"],"count":1},true)
	var fresh := preload("res://simulation/source_rewards.gd").initial()
	var unchanged := fresh.duplicate(true)
	check(preload("res://simulation/source_rewards.gd").prepare_catalog(fresh,malformed,[]).is_empty() and fresh==unchanged,"A cyclic pack must reject before any startup limits register")
	print("Original reward catalog: %d cases, %d bindings, save continuation, %d failures"%[fixture["cases"].size(),bindings,failures])
	quit(1 if failures else 0)
