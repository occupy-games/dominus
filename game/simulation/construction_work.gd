extends RefCounted
## Original 0x100bdaa2 building work accumulator. Count/skill inputs are explicit;
## routing, builder assignment, completion and animation remain separate owners.


static func advance(progress: float,delta: float,count: int,contributors: int,skill_sum: float,exponent: float,rate: float=1.0) -> float:
	if count<=0 or contributors<=0 or delta<=0 or skill_sum<=0 or rate<=0: return progress
	var power := pow(float(count),f32(exponent))
	var increment := power*f32(delta)
	return f32(f32(progress)+(f32(skill_sum)/float(contributors))*increment*f32(rate))


static func f32(value: float) -> float:
	return float(PackedFloat32Array([value])[0])


static func valid_exponent(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=8
