extends RefCounted
## Original particle playback for one authored emitter.

const UINT32_MASK := 0xffffffff

var phase := 0.0
var next_sample := 0.0
var carry := 0.0
var rate := 0.0
var seed: int
var particles: Dictionary = {}

var _started := false
var _emitting := true
var _duration_ms: float
var _time_scale: float
var _end_phase: float
var _sample_period: float
var _rate_samples: Array
var _rate_index := 0
var _multiplier: int
var _increment: int
var _divisor: float
var _birth: Dictionary
var _vertical_speed: Array
var _yaw_drift: Array
var _texture_variants: bool
var _random_color_phase: bool
var _size_cache: PackedFloat32Array
var _aspect_cache := PackedFloat32Array()
var _speed_cache := PackedFloat32Array([1.0])
var _vertical_speed_cache: PackedFloat32Array
var _spin_cache: PackedFloat32Array
var _curve_index_scale: float
var _curve_resolution: int
var _float_buffer := PackedByteArray()
var _free_slots: Array[int] = []
var _next_slot := 0


func _init(emitter: Dictionary, random_constants: Dictionary, percent: float, initial_seed: int) -> void:
	_float_buffer.resize(4)
	var clock: Dictionary = emitter["clock"]
	_rate_samples = emitter.get("rate_samples", [emitter.get("birth_rates", [0.0, 0.0])])
	_birth = emitter["birth"]
	var vertical_speed: Variant = _birth["vertical_speed"]
	_vertical_speed = vertical_speed if vertical_speed is Array else [vertical_speed, vertical_speed]
	_yaw_drift = _birth.get("yaw_drift", [0.0, 0.0])
	_texture_variants = _birth.get("texture_variants", true)
	_random_color_phase = _birth.get("random_color_phase", false)
	var curves: Dictionary = emitter["scalar_curves"]
	var size_curves: Dictionary = curves["0x948"]["cache"]
	_size_cache = PackedFloat32Array(size_curves["primary" if emitter.get("size_axes", false) else "secondary"]["values"])
	if emitter.get("size_axes", false):
		_aspect_cache = PackedFloat32Array(size_curves["secondary"]["values"])
	if curves.has("0xa14") and curves["0xa14"]["cache"]["primary"]["active"]:
		_speed_cache = PackedFloat32Array(curves["0xa14"]["cache"]["primary"]["values"])
	_vertical_speed_cache = PackedFloat32Array(curves["0xad4"]["cache"]["primary"]["values"])
	_spin_cache = PackedFloat32Array(curves["0xb94"]["cache"]["primary"]["values"])
	_curve_resolution = int(emitter["curve_cache_resolution"])
	_curve_index_scale = _curve_resolution * percent
	_duration_ms = float(clock["duration_ms"])
	_time_scale = float(clock["time_scale"])
	phase = _f32(float(clock["start_percent"]))
	_end_phase = float(clock["end_percent"])
	_sample_period = _f32(100000.0 / float(clock["samples_per_second"]) / _duration_ms)
	_multiplier = int(random_constants["multiplier"])
	_increment = int(random_constants["increment"])
	_divisor = float(random_constants["divisor"])
	seed = initial_seed & UINT32_MASK
	next_sample = phase


func _f32(value: float) -> float:
	_float_buffer.encode_float(0, value)
	return _float_buffer.decode_float(0)


func begin_update(delta_ms: float) -> void:
	if _started:
		seed = (seed + 1) & UINT32_MASK
		if _emitting:
			# 0x102ae16b rounds the increment before adding it to the running phase.
			var increment := _f32(delta_ms * _time_scale * 100.0 / _duration_ms)
			phase = _f32(phase + increment)
	_started = true


func has_sample() -> bool:
	return _started and _emitting and phase < _end_phase and next_sample <= phase


func _random_unit() -> float:
	seed = (seed * _multiplier + _increment) & UINT32_MASK
	return float(seed) / _divisor


func _random_between(first: float, second: float) -> float:
	return _f32(first + _f32(second - first) * _random_unit())


func _sample_lanes(lanes: Array) -> float:
	var first := _f32(float(lanes[0]))
	var second := _f32(float(lanes[1]))
	return first if first == second else _random_between(first, second)


func _random_integer(first: int, last: int) -> int:
	return mini(last, int(first + (last - first + 1) * _random_unit()))


func next_birth_quota() -> int:
	rate = _sample_lanes(_rate_samples[mini(_rate_index, _rate_samples.size() - 1)])
	_rate_index += 1
	var whole := int(rate)
	var accumulated := _f32(rate - whole + carry)
	var extra := int(accumulated)
	carry = _f32(accumulated - extra)
	next_sample = _f32(next_sample + _sample_period)
	return whole + extra


func _age_index(remaining_ms: int, lifetime_ms: int) -> int:
	# The age update rounds the remaining percentage before subtracting it.
	var age := _f32(100.0 - _f32(remaining_ms * 100.0 / lifetime_ms))
	return clampi(int(age * _curve_index_scale), 0, _curve_resolution)


func particle_size(base_size: float, remaining_ms: int, lifetime_ms: int) -> float:
	return _f32(base_size * _size_cache[_age_index(remaining_ms, lifetime_ms)])


func particle_aspect(age: int) -> float:
	if _aspect_cache.is_empty():
		return 1.0
	var width := _size_cache[age]
	return _f32(_aspect_cache[age] / width) if width != 0.0 else 0.0


func spawn_particle() -> Dictionary:
	# 0x102a32a0 initializes lifetime, size, motion and texture selection.
	var lifetime_ms := maxi(1, int(_sample_lanes(_birth["lifetime"]) * 1000.0))
	var base_size := _sample_lanes(_birth["size"])
	var size := particle_size(base_size, lifetime_ms, lifetime_ms)
	var speed := _sample_lanes(_birth["speed"])
	var vertical_speed := _sample_lanes(_vertical_speed)
	var spin := _sample_lanes(_birth["spin"])
	var yaw_drift := _sample_lanes(_yaw_drift)
	var frame_count := int(_birth["frame_count"])
	var frame := _random_integer(0, frame_count - 1) if frame_count > 1 else 0
	var texture_variant := _random_integer(0, 3) if _texture_variants else 0
	var color_phase := _random_between(0.0, 100.0) if _random_color_phase else 0.0

	# 0x102b8d70 samples the position and movement directions in that order.
	var linked: bool = _birth["linked_direction"]
	var position_yaw := _sample_lanes(_birth["azimuth_degrees"])
	var movement_yaw := position_yaw if linked else _sample_lanes(_birth["azimuth_degrees"])
	var elevation: Array = _birth["elevation"]
	var movement_pitch := _random_between(float(elevation[0]), float(elevation[1]))
	var position_pitch := movement_pitch if linked else _random_between(float(elevation[0]), float(elevation[1]))
	var azimuth := _f32(_f32(_f32(movement_yaw + 90.0) * PI) / 180.0)
	var pitch := _f32(movement_pitch * PI * 0.5)
	var offset_yaw := _f32(_f32(_f32(position_yaw * PI) / 180.0) + PI * 0.5)
	var offset_pitch := -_f32(position_pitch * PI * 0.5)

	# The spherical sampler draws the radius subdivision first. These
	# ordered radius bounds and one subdivision preserve the full interval.
	_random_unit()
	var radii: Array = _birth["radius"]
	var radius := _random_between(float(radii[0]), float(radii[1]))
	var horizontal := radius * _f32(cos(offset_pitch))
	var offset := Vector3(sin(offset_yaw) * horizontal, sin(offset_pitch) * radius, -cos(offset_yaw) * horizontal)
	var rotation: Array = _birth["rotation_degrees"]
	var rotation_degrees := posmod(_random_integer(int(rotation[0]), int(rotation[1])), 360)
	return {"lifetime_ms": lifetime_ms, "base_size": base_size, "size": size, "aspect": particle_aspect(0),
		"speed": speed, "vertical_speed": vertical_speed, "spin": spin, "yaw_drift": yaw_drift, "yaw_offset": 0.0,
		"frame": frame, "texture_variant": texture_variant, "color_phase": color_phase,
		"offset": offset, "azimuth": azimuth, "elevation": pitch, "rotation_degrees": rotation_degrees}


func advance(delta_ms: float) -> void:
	begin_update(delta_ms)
	var allow_initial_update := not _emitting or phase >= next_sample
	var elapsed_ms := delta_ms * _time_scale
	var whole_ms := int(elapsed_ms)
	var seconds := _f32(elapsed_ms * 0.001)
	for slot: int in particles.keys():
		var particle: Dictionary = particles[slot]
		var remaining := int(particle["remaining_ms"]) - whole_ms
		if remaining <= 0:
			particles.erase(slot)
			_free_slots.append(slot)
			continue
		particle["remaining_ms"] = remaining
		# The birth hook marks particles for one deferred motion update.
		# The next due sample (or release) clears that flag after aging.
		if particle["awaiting_sample"]:
			particle["awaiting_sample"] = not allow_initial_update
			continue
		_move_particle(particle, seconds)
	while has_sample():
		var quota := next_birth_quota()
		for i in range(quota):
			var particle := spawn_particle()
			particle["remaining_ms"] = particle["lifetime_ms"]
			particle["awaiting_sample"] = true
			var slot := _next_slot
			if _free_slots.is_empty():
				_next_slot += 1
			else:
				slot = _free_slots.pop_back()
			particles[slot] = particle


func _move_particle(particle: Dictionary, seconds: float) -> void:
	var age := _age_index(particle["remaining_ms"], particle["lifetime_ms"])
	var pitch: float = particle["elevation"]
	var yaw_offset := _f32(float(particle["yaw_offset"]) + _f32(float(particle["yaw_drift"]) * seconds))
	particle["yaw_offset"] = yaw_offset
	var yaw := _f32(float(particle["azimuth"]) + yaw_offset)
	var travel := _f32(float(particle["speed"]) * seconds * _speed_cache[mini(age, _speed_cache.size() - 1)])
	var horizontal := _f32(cos(pitch) * travel)
	var vertical := _f32(float(particle["vertical_speed"]) * _vertical_speed_cache[mini(age, _vertical_speed_cache.size() - 1)])
	var rise := _f32(_f32(sin(pitch) * travel) + _f32(vertical * seconds))
	var displacement := Vector3(sin(yaw) * horizontal, rise, -cos(yaw) * horizontal)
	particle["offset"] += displacement
	var spin := _f32(float(particle["spin"]) * _spin_cache[mini(age, _spin_cache.size() - 1)])
	var angle := _f32(float(particle["rotation_degrees"]) + _f32(spin * seconds))
	while angle >= 360.0:
		angle = _f32(angle - 360.0)
	while angle < 0.0:
		angle = _f32(angle + 360.0)
	particle["rotation_degrees"] = angle
	particle["size"] = _f32(float(particle["base_size"]) * _size_cache[age])
	particle["aspect"] = particle_aspect(age)


func is_finished() -> bool:
	return (not _emitting or phase >= _end_phase) and particles.is_empty()


func stop() -> void:
	_emitting = false
