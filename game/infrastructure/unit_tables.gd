extends RefCounted
## Wide OpenOffice unit tables. Source columns are preserved, never UI settings.
var directory := "res://../config"
var house_columns := {"Capacity":"capacity","Vision Radius":"vision_radius","Build Capacity":"build_capacity","Build Time":"build_ticks","Build Priority":"build_priority","Birth Rate":"birth_ticks","Breeder Count":"breeder_count","Collectable Belief":"min_belief","Max Belief":"max_belief","Belief Modifier":"belief_modifier","Belief Multiplier Per Peep In House":"belief_multiplier","New Builder Contribution":"new_builder_contribution"}
var follower_columns := PackedStringArray(["MaxHealth","RouteSpeed","Vision","Stamina","Strength","JobSkill","ReactionSkill","StaminaGainAtHome","StaminaGainSitting","MinReactionPriority","FireDamage","SwampDamage","DrownDamage","BlightedDamage","SwimDamage","StaminaDecay","Scale","FullScorchedSpeedMult","FullBeautifySpeedMult","BasketCapacity"])
var houses: Dictionary = {}
var followers: Dictionary = {}

func configure(rules: Dictionary) -> void:
	houses.clear()
	for source: Dictionary in rules["houses"]:
		var id := "%d:%d" % [source["family"],source["rank"]]
		var row := {"Unit ID":id,"House Rank":source["name"]}
		for column: String in house_columns:
			var field: String=house_columns[column]
			var value: Variant=source.get(field,"default")
			if field.ends_with("_ticks"): value=float(value)/10
			row[column]=value
		houses[id]=row
	var reference: Variant={"rows":preload("res://infrastructure/reference_unit_values.gd").rows()}
	if reference is Dictionary:
		var ordered := {}
		for entry: Dictionary in reference["rows"]:
			var id: String=entry["Unit ID"]
			var row: Dictionary=houses.get(id,{}).duplicate(true)
			if row.is_empty():
				for column: String in house_columns: row[column]="default"
			row.merge(entry,true)
			ordered[id]=row
		for id: String in houses:
			if not ordered.has(id): ordered[id]=houses[id]
		houses=ordered
	followers.clear()
	for race: String in ["Brown Head","Red Head","Champion","Astari"]:
		var row := {"Race":race}
		for column: String in follower_columns: row[column]="default"
		row.merge({"MaxHealth":100,"RouteSpeed":1.3,"Vision":7,"JobSkill":1,"Scale":1},true)
		followers[race]=row

func ensure_files() -> Dictionary:
	var columns := PackedStringArray(["House Rank"])
	for column: String in house_columns: columns.append(column)
	columns.append("Unit ID")
	var result := write_missing("Adobes.csv",columns,houses.values())
	if not result["ok"]: return result
	var fields := PackedStringArray(["Race"])
	fields.append_array(follower_columns)
	return write_missing("Followers.csv",fields,followers.values())

func write_missing(name: String,headers: PackedStringArray,rows: Array) -> Dictionary:
	var path := directory.path_join(name)
	if FileAccess.file_exists(path): return {"ok":true}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {"ok":false,"message":"Could not create "+name}
	file.store_csv_line(headers)
	for row: Dictionary in rows:
		var fields := PackedStringArray()
		for column: String in headers: fields.append(str(row[column]))
		file.store_csv_line(fields)
	return {"ok":true}

func read() -> Dictionary:
	var created := ensure_files()
	if not created["ok"]: return created
	var changes: Array=[]
	for table: String in ["Adobes.csv","Followers.csv"]:
		var file := FileAccess.open(directory.path_join(table),FileAccess.READ)
		if file==null: return {"ok":false,"message":"Could not read "+table}
		var line := file.get_line().trim_prefix("\ufeff")
		var delimiter := ";" if line.count(";")>line.count(",") else ","
		if line.count("\t")>line.count(delimiter): delimiter="\t"
		file.seek(0)
		var headers := file.get_csv_line(delimiter)
		for index in range(headers.size()): headers[index]=headers[index].strip_edges().trim_prefix("\ufeff")
		var abode := table=="Adobes.csv"
		var key_column := headers.find("Unit ID" if abode else "Race")
		if key_column<0: return {"ok":false,"message":table+" is missing its unit identifier column."}
		var definitions: Dictionary=houses if abode else followers
		var seen := {}
		var number := 1
		while not file.eof_reached():
			number+=1
			var row := file.get_csv_line(delimiter)
			if row.size()==1 and row[0].strip_edges().is_empty(): continue
			if row.size()!=headers.size(): return {"ok":false,"message":"Wrong column count in %s row %d." % [table,number]}
			var id: String=row[key_column].strip_edges()
			if not definitions.has(id) or seen.has(id): return {"ok":false,"message":"Unknown or duplicate unit in %s row %d." % [table,number]}
			seen[id]=true
			if abode:
				changes.append({"category":"house_name","unit":id,"label":row[headers.find("House Rank")]})
			for index in range(headers.size()):
				var column: String=headers[index].strip_edges()
				if column in ["House Rank","Unit ID","Race"]: continue
				if (abode and not house_columns.has(column)) or (not abode and not column in follower_columns): return {"ok":false,"message":"Unknown unit column: "+column}
				var text_: String=row[index].strip_edges()
				if text_.to_lower()=="default" or text_.is_empty(): continue
				if text_.count(",")==1 and not "." in text_: text_=text_.replace(",",".")
				if not text_.is_valid_float() or not is_finite(float(text_)): return {"ok":false,"message":"Invalid number in %s, row %d, %s." % [table,number,column]}
				var value := float(text_)
				if abode:
					var parts := id.split(":")
					changes.append({"category":"house","family":int(parts[0]),"rank":int(parts[1]),"field":house_columns[column],"value":value})
				else: changes.append({"category":"follower","race":id,"field":column,"value":value})
	return {"ok":true,"changes":changes,"count":changes.size()}
