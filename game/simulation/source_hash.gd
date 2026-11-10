extends RefCounted
## Source case-sensitive byte hash, distinct from the lowercase asset hash.

const MASK := 4294967295


static func bytes_(bytes: PackedByteArray) -> int:
	var value := 0
	for byte: int in bytes:
		value=((value+byte)*1025)&MASK
		value=value^(value>>6)
	value=(value*9)&MASK
	return ((value^(value>>11))*32769)&MASK


static func text(value: String) -> int:
	return bytes_(value.to_utf8_buffer())


static func pair(first: int,second: int) -> int:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(0,first)
	bytes.encode_u32(4,second)
	return bytes_(bytes)


static func coordinate(x: float,z: float,salt: int,minimum: int,maximum: int) -> int:
	var data := PackedByteArray()
	data.resize(12)
	data.encode_float(0,x)
	data.encode_float(4,z)
	data.encode_u32(8,salt)
	return minimum+((((bytes_(data)&65535)*(maximum-minimum))&MASK)>>16)
