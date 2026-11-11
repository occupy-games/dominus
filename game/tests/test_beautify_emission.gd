extends SceneTree

const Emission = preload("res://presentation/world/beautify_emission.gd")

var failures := 0
var tested_births := 0
var tested_sizes := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func same_float(value: float, expected: float) -> bool:
	return value == PackedFloat32Array([expected])[0]


func check_birth(scheduler: RefCounted, expected: Dictionary, label: String) -> void:
	check(scheduler.seed == int(expected["seed_before"]), label + " seed before birth")
	var particle: Dictionary = scheduler.spawn_particle()
	check(scheduler.seed == int(expected["seed_after"]), label + " seed after birth")
	for field: String in ["lifetime_ms", "frame", "texture_variant", "rotation_degrees"]:
		check(particle[field] == int(expected[field]), label + " " + field)
	for field: String in ["base_size", "size", "aspect", "speed", "spin", "azimuth", "elevation"]:
		check(same_float(particle[field], expected[field]), label + " " + field)
	var xyz: Array = expected["offset"]
	var offset: Vector3 = particle["offset"]
	# The source uses x87 transcendental routines. Allow two f32 units at
	# the largest authored radius for platform sine/cosine differences.
	check(offset.distance_to(Vector3(xyz[0], xyz[1], xyz[2])) <= 0.00002, label + " spawn position")
	tested_births += 1


func replay(manifest: Dictionary, playback: Dictionary) -> int:
	var tested := 0
	for emitter_index in range(manifest["emitters"].size()):
		var emitter: Dictionary = manifest["emitters"][emitter_index]
		var scheduler := Emission.new(emitter, manifest["emission_rng"], manifest["curve_constants"]["percent"], 0)
		for frame_index in range(playback["frames"].size()):
			var label := "%s update %d" % [emitter["name"], frame_index]
			var expected: Dictionary = playback["frames"][frame_index][emitter_index]
			if frame_index == int(playback["release_step"]):
				scheduler.stop()
			scheduler.begin_update(float(playback["timesteps_ms"][frame_index]))
			check(same_float(scheduler.phase, expected["phase"]), label + " effect phase")
			for sample: Dictionary in expected["age_sizes"]:
				var size := scheduler.particle_size(sample["base_size"], sample["remaining_ms"], sample["lifetime_ms"])
				check(same_float(size, sample["size"]), label + " size after aging")
				tested_sizes += 1
			var samples: Array = expected["rates"]
			var births := 0
			for sample: Dictionary in samples:
				check(scheduler.has_sample() and same_float(scheduler.next_sample, sample["phase"]), label + " sample phase")
				check(scheduler.seed == int(sample["seed_before"]), label + " seed before rate")
				check(same_float(scheduler.carry, sample["carry_before"]), label + " incoming carry")
				var quota := scheduler.next_birth_quota()
				check(same_float(scheduler.rate, sample["rate"]) and scheduler.seed == int(sample["seed_after"]),
					label + " selected rate and seed")
				check(quota == int(sample["quota"]) and same_float(scheduler.carry, sample["carry_after"]),
					label + " quota and remaining carry")
				births += quota
				tested += 1
				var particles: Array = sample.get("particles_at_birth", [])
				check(particles.size() == quota, label + " native birth records")
				for particle: Dictionary in particles:
					check_birth(scheduler, particle, label)
				if quota > 0:
					check(scheduler.seed == int(sample["seed_after_birth"]), label + " ending batch seed")
			check(not scheduler.has_sample() and same_float(scheduler.next_sample, expected["next_sample"]),
				label + " next due sample")
			check(births == int(expected["births"]) and scheduler.seed == int(expected["seed"]),
				label + " total births and ending seed")
	return tested


func replay_motion(manifest: Dictionary, playback: Dictionary) -> int:
	var observations := 0
	for emitter_index in range(manifest["emitters"].size()):
		var emitter: Dictionary = manifest["emitters"][emitter_index]
		var scheduler := Emission.new(emitter, manifest["emission_rng"], manifest["curve_constants"]["percent"], 0)
		for frame_index in range(playback["frames"].size()):
			if frame_index == int(playback["release_step"]):
				scheduler.stop()
			scheduler.advance(float(playback["timesteps_ms"][frame_index]))
			var expected: Dictionary = playback["frames"][frame_index][emitter_index]
			var label := "%s motion update %d" % [emitter["name"], frame_index]
			check(scheduler.seed == int(expected["seed"]), label + " ending seed")
			check(scheduler.is_finished() == expected["finished"], label + " completion")
			check(scheduler.particles.size() == expected["particles"].size(), label + " live count")
			for row: Array in expected["particles"]:
				var slot := int(row[0])
				var particle: Dictionary = scheduler.particles.get(slot, {})
				check(not particle.is_empty(), label + " live slot %d" % slot)
				if particle.is_empty():
					continue
				var xyz: Array = row[3]
				var offset: Vector3 = particle["offset"]
				check(offset.distance_to(Vector3(xyz[0], xyz[1], xyz[2])) <= 0.00004, label + " position slot %d" % slot)
				check(particle["remaining_ms"] == int(row[1]) and particle["lifetime_ms"] == int(row[2]),
					label + " lifetime slot %d" % slot)
				check(same_float(particle["size"], row[4]), label + " size slot %d" % slot)
				check(same_float(particle["rotation_degrees"], row[5]), label + " spin slot %d" % slot)
				check(particle["frame"] == int(row[6]), label + " texture frame slot %d" % slot)
				observations += 1
	return observations


func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/beautify_particles.json"))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_beautify_particles.json"))
	var tested := replay(manifest, fixture["playback"]) + replay(manifest, fixture["fractional_playback"])
	check(tested == 78, "Expected all original rate samples")
	check(tested_births == 47, "Expected all original particle births")
	check(tested_sizes == 113, "Expected all original particle size updates")
	var observations := 0
	for playback: Dictionary in [fixture["playback"], fixture["fractional_playback"], fixture["recycle_playback"]]:
		observations += replay_motion(manifest, playback)
	print("Original Beautify particle initialization: %d native births" % tested_births)
	print("Original Beautify particle size: %d native age updates" % tested_sizes)
	print("Original Beautify playback: %d live particle observations" % observations)
	print("Original Beautify emission: %d native samples, %d failures" % [tested, failures])
	quit(1 if failures else 0)
