extends SceneTree

const Clumps = preload("res://simulation/source_abode_clumps.gd")


func _initialize() -> void:
	var capture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../build/native-abode-clumps.json"))
	var failures := 0
	for record: Dictionary in capture["cases"]:
		var houses: Array=record["houses"].duplicate(true)
		for index in range(houses.size()): houses[index]["id"]=index
		var actual := Clumps.biggest(houses,2,record["radius"],capture["rules"],record["include_unfinished"])
		var expected: Array=record["expected"].map(func(value: Variant) -> int: return int(value))
		if actual!=expected:
			failures+=1
			push_error("Original clump callback order differs: %s expected %s for %s"%[actual,expected,record])
	for record: Dictionary in capture["fills"]:
		if maxf(record["stored"],record["maximum"])!=record["expected"]:
			failures+=1
			push_error("Original fill must preserve an existing balance above capacity")
	print("Original abode clumps and fill: %d cases, %d failures"%[capture["cases"].size()+capture["fills"].size(),failures])
	quit(1 if failures else 0)
