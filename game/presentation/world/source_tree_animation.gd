extends RefCounted
## Native 0x10155f20 scale curve for the initial scenery's null growth record.
## Presentation only: this cannot enable trees or change plot occupancy.


static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func scale_at(config: Dictionary,enabled: bool,now: float,changed_ms: float,base: float=1.0,encouragement: float=0.0) -> float:
	if not enabled: return 0.0
	var elapsed := f32((f32(now)*1000.0-f32(changed_ms))/1000.0)
	var size := f32(base)
	if elapsed<float(config["duration"]):
		var time := f32(elapsed/float(config["duration"]))
		var shape: float
		if time<f32(0.3): shape=time/float(f32(0.3))
		elif time<f32(0.6): shape=(float(f32(0.6))-time)*0.75*3.3333332008785725+0.25
		else: shape=(time-float(f32(0.6)))*0.75*2.500000149011621+0.25
		shape=f32(shape)
		var smooth := f32(shape*shape*(3.0-2.0*shape))
		size=f32(base+1.0-smooth)
	var multiplier := 1.0+(float(config["encouragement_scale"])-1.0)*f32(encouragement)
	return f32(float(config["vertical_scale"])*f32(size*multiplier+(1.0-size)*float(config["minimum_scale"])))
