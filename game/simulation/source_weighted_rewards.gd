extends RefCounted
## Original reward weighted bag and era conversion helpers. The caller supplies
## a seeded CRT-word stream; a nonzero override consumes no random word.

const Schedule = preload("res://simulation/source_plot_schedule.gd")
const MASK := 4294967295


static func era_bucket(era: int) -> int:
	var value := era&MASK
	if value<=1: return 0
	if value==2: return 1
	return 2 if value==3 else 3


static func bucket_era(bucket: int) -> int:
	var value := bucket&MASK
	return value+1 if value<=3 else 1


static func valid(entries: Variant,total: Variant,override: Variant) -> bool:
	if not entries is Array or entries.size()>256 or not Schedule.integer_between(total,0,MASK) or not Schedule.integer_between(override,0,MASK): return false
	for entry: Variant in entries:
		if not entry is Dictionary or not Schedule.integer_between(entry.get("weight"),0,MASK) or not entry.has("value"): return false
		if not entry["value"] is String and not Schedule.integer_between(entry["value"],0,MASK): return false
	return true


static func choose(entries: Array,total: int,override: int,random_word: Callable) -> Variant:
	if not valid(entries,total,override) or (override==0 and not random_word.is_valid()): return 0
	# IMUL retains only the low 32 bits before the unsigned right shift.
	# Even an empty bag consumes a word when override is zero.
	var word := (override&65535) if override!=0 else (int(random_word.call())&32767)
	var roll := ((word*total)&MASK)>>(16 if override!=0 else 15)
	for entry: Dictionary in entries:
		var weight := int(entry["weight"])
		if roll<weight: return entry["value"]
		roll=(roll-weight)&MASK
	return 0
