extends RefCounted
## Recursively seal plain, immutable configuration before sharing snapshots.


static func freeze(value: Variant) -> Variant:
	if value is Dictionary:
		for child: Variant in value.values(): freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: freeze(child)
		value.make_read_only()
	return value
