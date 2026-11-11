extends RefCounted
## Bounded interpreter for offline-parsed original voyage scripts. Plain data only.

var program: Dictionary
var globals: Dictionary
var api: Callable
var remaining := 30000
var depth := 0
var error := ""
var cosmetic_depth := 0


static func table_key(owner: Dictionary,key: Variant) -> Variant:
	# JSON preserves table indices as strings; Lua treats integral numbers alike.
	if key is int or key is float:
		if key==int(key):
			if owner.has(int(key)): return int(key)
			if owner.has(str(int(key))): return str(int(key))
			return int(key)
	return key


static func table_get(owner: Variant,key: Variant) -> Variant:
	return owner.get(table_key(owner,key)) if owner is Dictionary else null


static func table_length(value: Variant) -> int:
	if value is Array: return value.size()
	if not value is Dictionary: return 0
	var length := 0
	while table_get(value,length+1)!=null: length+=1
	return length


func initialize(code: Dictionary, variables: Dictionary, builtins: Callable) -> void:
	program=code
	globals=variables
	api=builtins


static func truth(value: Variant) -> bool:
	return value!=null and not (value is bool and not value)


static func first_result(value: Variant) -> Variant:
	if value is Dictionary and value.has("multiple"):
		return value["multiple"][0] if not value["multiple"].is_empty() else null
	return value


func run() -> void:
	block(program.get("body",[]),{})


func hook(name: String, args: Array = []) -> Variant:
	return invoke(globals[name],args) if globals.has(name) else null


func invoke(function: Variant, args: Array = []) -> Variant:
	if function is String: return hook(function,args) if globals.has(function) else api.call(function,args)
	if not function is Dictionary: return null
	if function.has("builtin"): return api.call(str(function["builtin"]),args)
	if not function.has("function") or not program.get("functions",{}).has(str(function["function"])): return null
	if depth>=32 or remaining<=0:
		error="Voyage script exceeded its execution budget."
		return null
	depth+=1
	var data: Dictionary = program["functions"][str(function["function"])]
	var scope: Dictionary = function.get("scope",{}).duplicate(true)
	var self_name: String=program.get("local_function_names",{}).get(str(function["function"]),"")
	if not self_name.is_empty(): scope[self_name]=function
	for i in range(data["params"].size()): scope[str(data["params"][i])]=args[i] if i<args.size() else null
	var returned := block(data["body"],scope)
	depth-=1
	return returned.get("value")


func assign(target: Array, value: Variant, scope: Dictionary, local: bool = false) -> void:
	if target[0]=="var":
		if local or scope.has(str(target[1])): scope[str(target[1])]=value
		else: globals[str(target[1])]=value
	elif target[0]=="index":
		var owner: Variant = expression(target[1],scope)
		var key: Variant = expression(target[2],scope)
		if owner is Dictionary: owner[table_key(owner,key)]=value


func block(statements: Array, scope: Dictionary) -> Dictionary:
	for statement: Array in statements:
		remaining-=1
		if remaining<=0:
			error="Voyage script exceeded its instruction budget."
			return {}
		match statement[0]:
			"assign","local": assign(statement[1],expression(statement[2],scope),scope,statement[0]=="local")
			"assign_many","local_many":
				var multi: Variant = expression(statement[2],scope)
				var values: Array = multi.get("multiple",[]) if multi is Dictionary else [multi]
				for i in range(statement[1].size()): assign(statement[1][i],values[i] if i<values.size() else null,scope,statement[0]=="local_many")
			"expr": expression(statement[1],scope)
			"return": return {"value":expression(statement[1],scope)}
			"break": return {"break":true}
			"if":
				var selected: Array = statement[2]
				for branch: Array in statement[1]:
					if truth(expression(branch[0],scope)):
						selected=branch[1]
						break
				var returned := block(selected,scope)
				if returned.has("value") or returned.has("break"): return returned
			"for":
				var first := float(expression(statement[2],scope))
				var last := float(expression(statement[3],scope))
				var increment := float(expression(statement[4],scope))
				if increment==0: return {}
				var count := mini(1000,maxi(0,floori((last-first)/increment)+1))
				for index in range(count):
					scope[str(statement[1])]=first+increment*index
					var returned := block(statement[5],scope)
					if returned.has("value"): return returned
					if returned.has("break"): break
	return {}


func expression(node: Array, scope: Dictionary) -> Variant:
	remaining-=1
	if remaining<=0: return null
	match node[0]:
		"literal": return node[1]
		"var":
			var name: String = node[1]
			if scope.has(name): return scope[name]
			if globals.has(name): return globals[name]
			return {"builtin":name} if name in program.get("builtins",[]) else null
		"function": return {"function":node[1],"scope":scope.duplicate(true)}
		"table":
			var table := {}
			for pair: Array in node[1]: table[table_key(table,expression(pair[0],scope))]=expression(pair[1],scope)
			return table
		"index":
			var owner: Variant = expression(node[1],scope)
			var key: Variant = expression(node[2],scope)
			return table_get(owner,key)
		"method_call":
			var owner: Variant = expression(node[1],scope)
			var arguments: Array = [owner]
			for argument: Array in node[3]: arguments.append(expression(argument,scope))
			return invoke(table_get(owner,node[2]),arguments)
		"call":
			var function: Variant = expression(node[1],scope)
			var cosmetic: bool = function is Dictionary and str(function.get("builtin","")).begins_with("TriggerTip")
			if cosmetic: cosmetic_depth+=1
			var arguments: Array = []
			for argument: Array in node[2]: arguments.append(expression(argument,scope))
			if cosmetic: cosmetic_depth-=1
			return invoke(function,arguments)
		"unary":
			var value: Variant = expression(node[2],scope)
			if node[1]=="not": return not truth(value)
			if node[1]=="#": return table_length(value)
			return -float(value) if value is int or value is float else 0
		"binary":
			var left: Variant = first_result(expression(node[2],scope))
			if node[1]=="and": return expression(node[3],scope) if truth(left) else left
			if node[1]=="or": return left if truth(left) else expression(node[3],scope)
			var right: Variant = first_result(expression(node[3],scope))
			match node[1]:
				"==": return left==right
				"~=": return left!=right
				"..": return str(left)+str(right)
			if not (left is float or left is int) or not (right is float or right is int):
				if cosmetic_depth==0: error="Non-numeric arithmetic in supplied voyage script."
				return 0
			match node[1]:
				"<": return left<right
				">": return left>right
				"<=": return left<=right
				">=": return left>=right
				"+": return left+right
				"-": return left-right
				"*": return left*right
				"/": return float(left)/float(right) if right!=0 else 0
				"%": return fmod(float(left),float(right)) if right!=0 else 0
				"^": return pow(float(left),float(right))
	return null
