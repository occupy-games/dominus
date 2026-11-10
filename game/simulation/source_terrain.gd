extends RefCounted
## Original default discrete terrain query, 0x1025b8f0 (no sculpt overrides).

const HEIGHT_SCALE := 0.30000001192092896 # Original double at 0x104a0c78.


static func f32(value: float) -> float:
	return float(PackedFloat32Array([value])[0])


static func middle(a: int,b: int,c: int) -> int:
	return a+b+c-mini(a,mini(b,c))-maxi(a,maxi(b,c))


static func quad(corners: Vector4i,x: float,z: float) -> int:
	var fx := f32(x)
	var fz := f32(z)
	var ix := f32(1.0-fx)
	var iz := f32(1.0-fz)
	if fx+fz<0.5: return corners.x
	if fx+iz<0.5: return corners.z
	if ix+fz<0.5: return corners.y
	if ix+iz<0.5: return corners.w
	# Central diamond: the nearest corner and its two adjacent corners.
	# The diagonally opposite height does not participate in this median.
	if fx<0.5: return middle(corners.x,corners.y,corners.z) if fz<0.5 else middle(corners.z,corners.x,corners.w)
	return middle(corners.y,corners.x,corners.w) if fz<0.5 else middle(corners.w,corners.y,corners.z)


static func raw_at(vertex: Callable,width: int,x: float,z: float) -> int:
	var px := f32(x)
	var pz := f32(z)
	if not is_finite(px) or not is_finite(pz): return 0
	if px<=-1.0 or pz<=-1.0 or px>=width-1 or pz>=width-1: return 0
	# The native float-to-int operation truncates, including negative fractions.
	var ix := int(px)
	var iz := int(pz)
	if ix<0 or iz<0 or ix+1>=width or iz+1>=width: return 0
	var corners := Vector4i(int(vertex.call(ix,iz)),int(vertex.call(ix+1,iz)),int(vertex.call(ix,iz+1)),int(vertex.call(ix+1,iz+1)))
	return quad(corners,f32(px-ix),f32(pz-iz))


static func surface_height(raw: int) -> float:
	return f32(raw*HEIGHT_SCALE)


static func script_step(raw: int) -> float:
	# Original Lua GetStepAtPoint converts the stored world height back to a
	# step, preserving both float32 storage boundaries in that wrapper.
	return f32(surface_height(raw)/HEIGHT_SCALE)
