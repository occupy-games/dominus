extends RefCounted
## Editable CSV values are parsed completely before simulation receives changes.
var path := "res://../config/Update.csv"
var tables := preload("res://infrastructure/unit_tables.gd").new()
var definitions: Dictionary = {}


func initialize(source_rules: Dictionary) -> void:
	definitions.clear()
	tables.directory=path.get_base_dir()
	tables.configure(source_rules)
	var active_config := ["belief_Totem","belief_TotemActivate","belief_TotemActivate_Deactivate","belief_Beautify","belief_FingerOfGod","InitialTotemCapacity","tapsToDestroyRock","GiveFirstCardDelay","FirstCardIndex","Cards_PercentChanceToGetCardYouNeed","Cards_PercentChanceToGetOtherUsefulCard","Cards_PercentChanceToGetRandomCard","BeautifyLength","BEAUTIFY_RADIUS","maxBeautifyBeautyFactor","FingerOfGodLength","templeFixerFalloff"]
	for key: String in source_rules["config"]:
		if key in active_config:
			var text_: String = str(source_rules["config"][key])
			if text_.is_valid_float(): add("Config."+key,"Unit and power values",float(text_),{"category":"config","key":key})
	for index in range(source_rules["influence_areas"].size()):
		var area: Dictionary = source_rules["influence_areas"][index]
		for field: String in ["x","z","radius"]:
			add("Influence.%d.%s" % [index,field],"Influence: "+str(area["unlock"]),float(area[field]),{"category":"influence","index":index,"field":field,"unlock":area["unlock"],"reference_offset":source_rules.get("registration_offset",[0,0]).duplicate()})
	for id: String in source_rules["cards"]:
		var card: Dictionary = source_rules["cards"][id]
		add("Card."+id+".age","Cards: "+str(card["title"]),float(card["age"]),{"category":"card","id":id,"field":"age"})
		add("Card."+id+".number","Cards: "+str(card["title"]),float(card["number"]),{"category":"card","id":id,"field":"number"})
		for resource: String in card["requirements"]: add("Requirement."+id+"."+resource,"Card requirements",float(card["requirements"][resource]),{"category":"requirement","id":id,"resource":resource})
	for shrine: Dictionary in source_rules["shrines"]:
		add("Shrine."+shrine["id"]+".build_seconds","Shrine repair",float(shrine["build_ticks"])/10,
			{"category":"shrine","id":shrine["id"],"registered_scope":source_rules.get("registered_scope","")})
	var runtime := {"sheep_speed":1.0,"build_rate":1.0,"birth_rate":1.0,"belief_rate":1.0,"sculpt_cost":1.0,"home_search_radius":4.0}
	for key: String in runtime: add("Unit."+key,"Units",runtime[key],{"category":"runtime","key":key})


func add(name: String,group: String,value: float,binding: Dictionary) -> void:
	definitions[name]={"group":group,"default":value,"binding":binding}


func ensure_file() -> Dictionary:
	tables.directory=path.get_base_dir()
	var units := tables.ensure_files()
	if not units.get("ok",false): return units
	if FileAccess.file_exists(path): return ensure_temple_work_constant()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {"ok":false,"message":"Could not create constants CSV."}
	file.store_csv_line(PackedStringArray(["Group","Name","Value","Default"]))
	for name: String in definitions:
		var entry: Dictionary = definitions[name]
		file.store_csv_line(PackedStringArray([entry["group"],name,str(entry["default"]),str(entry["default"])]))
	file.close()
	return {"ok":true}


func ensure_temple_work_constant() -> Dictionary:
	# Append the new live temple value without rewriting the user's existing
	# spreadsheet rows, delimiter, column order or edited values.
	var name := "Config.templeFixerFalloff"
	if not definitions.has(name): return {"ok":true}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return {"ok":false,"message":"Could not read constants CSV."}
	var first := file.get_line().trim_prefix("\ufeff")
	var separator := ";" if first.count(";")>first.count(",") else ","
	if first.count("\t")>first.count(separator): separator="\t"
	file.seek(0)
	var header := file.get_csv_line(separator)
	if not header.is_empty(): header[0]=header[0].trim_prefix("\ufeff")
	var name_column := header.find("Name")
	var value_column := header.find("Value")
	if name_column<0 or value_column<0: return {"ok":true} # read() reports the malformed header.
	while not file.eof_reached():
		var row := file.get_csv_line(separator)
		if row.size()>name_column and str(row[name_column]).strip_edges()==name: return {"ok":true}
	file.close()
	file=FileAccess.open(path,FileAccess.READ_WRITE)
	if file==null: return {"ok":false,"message":"Could not append the source temple value."}
	var length := file.get_length()
	var needs_line := false
	if length>0:
		file.seek(length-1)
		needs_line=not file.get_8() in [10,13]
	file.seek_end()
	if needs_line: file.store_string("\n")
	var entry: Dictionary=definitions[name]
	var row := PackedStringArray()
	row.resize(header.size())
	row[name_column]=name
	row[value_column]=str(entry["default"])
	if header.has("Default"): row[header.find("Default")]=str(entry["default"])
	if header.has("Group"): row[header.find("Group")]=str(entry["group"])
	file.store_csv_line(row,separator)
	file.close()
	return {"ok":true}


func read() -> Dictionary:
	var created := ensure_file()
	if not created["ok"]: return created
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return {"ok":false,"message":"Could not read constants CSV."}
	var header_text := file.get_line().trim_prefix("\ufeff")
	var separator := ";" if header_text.count(";")>header_text.count(",") else ","
	if header_text.count("\t")>header_text.count(separator): separator="\t"
	file.seek(0)
	var header := file.get_csv_line(separator)
	if not header.is_empty(): header[0]=header[0].trim_prefix("\ufeff")
	var name_column := header.find("Name")
	var value_column := header.find("Value")
	if name_column<0 or value_column<0: return {"ok":false,"message":"CSV requires Name and Value columns."}
	var changes: Array = []
	var seen := {}
	var line := 1
	while not file.eof_reached():
		line+=1
		var row := file.get_csv_line(separator)
		if row.size()==1 and str(row[0]).strip_edges().is_empty(): continue
		if row.size()<=maxi(name_column,value_column): return {"ok":false,"message":"Incomplete CSV row %d." % line}
		var name: String = str(row[name_column]).strip_edges()
		if name.begins_with("Runtime."): name=name.replace("Runtime.","Unit.")
		if not definitions.has(name) or seen.has(name): return {"ok":false,"message":"Unknown or duplicate constant on row %d: %s" % [line,name]}
		var number: String = str(row[value_column]).strip_edges()
		if number.count(",")==1 and not "." in number: number=number.replace(",",".")
		if not number.is_valid_float() or not is_finite(float(number)): return {"ok":false,"message":"Invalid number on row %d: %s" % [line,name]}
		var change: Dictionary = definitions[name]["binding"].duplicate(true)
		change["value"]=float(number)
		if change["category"]=="influence":
			var reference := float(definitions[name]["default"])
			var default_column := header.find("Default")
			if default_column>=0 and row.size()>default_column:
				var text_: String=str(row[default_column]).strip_edges()
				if text_.count(",")==1 and not "." in text_: text_=text_.replace(",",".")
				if text_.is_valid_float() and is_finite(float(text_)): reference=float(text_)
			change["offset_from_default"]=float(number)-reference
			var group_column := header.find("Group")
			if group_column>=0 and row.size()>group_column and str(row[group_column]).begins_with("Influence: "): change["unlock"]=str(row[group_column]).trim_prefix("Influence: ")
		changes.append(change)
		seen[name]=true
	var units := tables.read()
	if not units.get("ok",false): return units
	changes.append_array(units["changes"])
	return {"ok":true,"changes":changes,"count":changes.size(),"path":ProjectSettings.globalize_path(path)}


func open_editor(table: String = "Adobes.csv") -> Dictionary:
	var created := ensure_file()
	if not created.get("ok",false): return created
	if not table in ["Adobes.csv","Followers.csv","Update.csv"]: return {"ok":false,"message":"Unknown unit table."}
	var filename := ProjectSettings.globalize_path(path.get_base_dir().path_join(table))
	if DirAccess.dir_exists_absolute("/Applications/OpenOffice.app"):
		var process := OS.create_process("/usr/bin/open",PackedStringArray(["-a","OpenOffice",filename]))
		return {"ok":process>=0,"message":"Editing unit values in OpenOffice." if process>=0 else "Could not open OpenOffice."}
	if DirAccess.dir_exists_absolute("/Applications/LibreOffice.app"):
		var process := OS.create_process("/usr/bin/open",PackedStringArray(["-a","LibreOffice",filename]))
		return {"ok":process>=0,"message":"Editing unit values in LibreOffice." if process>=0 else "Could not open LibreOffice."}
	var code := OS.shell_open(filename)
	return {"ok":code==OK,"message":"Opened unit values CSV." if code==OK else "Could not open the unit values CSV."}
