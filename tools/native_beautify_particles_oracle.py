"""Compare recovered particle curves with the original in-memory emitter loader."""
import hashlib
import json
import struct

from tools.beautify_particles import extract
from tools.native_scenery_oracle import Oracle, ROOT


class EmitterLoader(Oracle):
    CONSTRUCTOR = 0x1028c9f0
    LOAD_EMITTER = 0x1028d230
    LOAD_CURVE = 0x102c3650
    BEFORE_PRIMARY_COMPILATION = 0x102c3bac
    BEFORE_SECONDARY_COMPILATION = 0x102c3e04
    ALLOCATE = 0x10353740
    FREE = 0x103452c0
    EMITTER = Oracle.SCRATCH + 0x2000
    EMITTER_BYTES = 0x1438
    STREAM = Oracle.SCRATCH + 0x6000
    VTABLE = Oracle.SCRATCH + 0x6100
    READ = Oracle.SCRATCH + 0x6200
    PARENT = Oracle.SCRATCH + 0x7000
    EVALUATOR = Oracle.SCRATCH + 0x7300
    PARTICLE_CONTEXT = Oracle.SCRATCH + 0x7400
    DRAW_CONTEXT = Oracle.SCRATCH + 0x7500
    EFFECT = Oracle.SCRATCH + 0x7800
    EFFECT_STATE = Oracle.SCRATCH + 0x7a00
    PARTICLE = Oracle.SCRATCH + 0x7b00
    DRAW_OUTPUT = Oracle.SCRATCH + 0x7c00
    DRAW_OPACITY = Oracle.SCRATCH + 0x7d00
    DRAW_PHASE = Oracle.SCRATCH + 0x7d10
    EFFECT_INSTANCE = Oracle.SCRATCH + 0x8000
    EFFECT_PARENT = Oracle.SCRATCH + 0x8400
    SAMPLE_TIMES = (0, 0.125, 2.25, 10, 20.32085418701172, 21.782176971435547, 25,
                    33.375, 49.875, 50, 50.125, 64.67066192626953, 75, 78.7128677368164,
                    90, 99.875, 100)
    COLOR_TIMES = (*SAMPLE_TIMES, 100.00000762939453, 100.125, 125, 199.875, 200, 200.125)
    DRAW_INPUTS = tuple((remaining, lifetime, opacity, effect, parent, phase)
                        for lifetime, ticks in ((1000, (1000, 999, 980, 950, 900, 750, 500, 250, 50, 1, 0)),
                                                (137, (137, 136, 97, 60, 1, 0)))
                        for remaining in ticks
                        for opacity, effect, parent, phase in (
                            (None, 1.0, None, None), (None, 0.125, None, None),
                            (77.7, 0.5, 0.71, 39.5), (180.0, 1.0, None, None),
                            (0.0, 1.0, None, 66.0), (100.0, 0.0, None, None),
                            (89.73, 0.37, 0.13, 159.75)))

    def __init__(self, executable, library):
        super().__init__(executable)
        self.library = library
        self.next_allocation = self.POOL
        self.allocations = {}
        self.position = self.end = 0
        self.curves = []
        self.primary_keys = {}
        self.secondary_keys = {}
        self.adapters = {self.ALLOCATE: self.allocate, self.FREE: self.free, self.READ: self.read}
        self.set_integer(self.STREAM, self.VTABLE)
        self.set_integer(self.VTABLE + 0x18, self.READ)
        self.cpu.hook_add(self.hook_kind, self.hook)

    def allocate(self):
        size, = self.arguments(1)
        self.return_integer(self.reserve(size))

    def reserve(self, size):
        result = self.next_allocation
        self.next_allocation += max(16, (size + 15) & ~15)
        if size > 0x100000 or self.next_allocation > self.POOL + 0x2000000:
            raise ValueError(f"Particle allocation exceeds bounds at {self.position:#x}")
        self.allocations[result] = size
        return result

    def free(self):
        self.return_integer()

    def read(self):
        destination, count = self.arguments(2)
        end = self.position + count
        if end > self.end:
            raise ValueError(f"Particle stream read exceeds record at {self.position:#x}")
        self.cpu.mem_write(destination, self.library[self.position:end])
        self.position = end
        self.return_integer(count, 8)

    def hook(self, cpu, address, size, user):
        if address == self.LOAD_CURVE:
            curve = cpu.reg_read(self.regs.UC_X86_REG_ECX)
            self.curves.append((self.position, curve))
        elif address == self.BEFORE_PRIMARY_COMPILATION:
            curve = cpu.reg_read(self.regs.UC_X86_REG_ESI)
            self.primary_keys[curve] = self.keys(self.integer(curve + 0x14), self.integer(curve + 0x10))
        elif address == self.BEFORE_SECONDARY_COMPILATION:
            curve = cpu.reg_read(self.regs.UC_X86_REG_EDI)
            self.secondary_keys[curve] = self.keys(self.integer(curve + 0xc4), self.integer(curve + 0xc0))
        super().hook(cpu, address, size, user)

    def invoke(self, routine, instance, arguments):
        self.cpu.reg_write(self.regs.UC_X86_REG_ECX, instance)
        return self.call(routine, arguments, limit=3_000_000)

    def keys(self, pointer, count):
        if count > 256:
            raise ValueError("Native curve key count exceeds bounds")
        result = []
        for i in range(count):
            key = pointer + i * 0x5c
            time, bits, lx, ly, rx, ry = struct.unpack('<fI4f', self.cpu.mem_read(key + 4, 24))
            result.append(dict(time=time, value_bits=bits, left=[lx, ly], right=[rx, ry],
                               weight=self.float(key + 0x2c),
                               flags=[self.cpu.mem_read(key + offset, 1)[0] for offset in (0x30, 0x31, 0x58)]))
        return result

    def sample_scalar(self, field, secondary):
        self.invoke(0x102c2950, self.EVALUATOR, [])
        self.set_integer(self.EVALUATOR, 0x104f2998 if secondary else 0x104f297c)
        self.invoke(0x10287da0, self.EVALUATOR, [self.EMITTER + field])
        samples = []
        for time in self.SAMPLE_TIMES:
            argument, = struct.unpack('<I', struct.pack('<f', time))
            self.cpu.reg_write(self.regs.UC_X86_REG_ECX, self.EVALUATOR)
            samples.append(self.call(0x102c29a0, [argument], floating=True, limit=300_000))
        return samples

    def compiled_keys(self, field, secondary):
        curve = self.EMITTER + field
        count = self.integer(curve + (0xc0 if secondary else 0x10))
        keys = self.integer(curve + (0xc4 if secondary else 0x14))
        if count > 256:
            raise ValueError("Native scalar key count exceeds bounds")
        result = []
        for index in range(count):
            key = keys + index * 0x5c
            samples = self.integer(key + 0x34)
            if samples > 31:
                raise ValueError("Native scalar interval exceeds bounds")
            points = self.integer(key + 0x38)
            data = [list(struct.unpack('<2f', self.cpu.mem_read(points + i * 8, 8)))
                    for i in range(samples)]
            result.append([self.float(key + 4), self.float(key + 8), data])
        return result

    def cached_curve(self, field, secondary):
        constructor, prepare = (0x102c3480, 0x102c2c90) if secondary else (0x102c33e0, 0x102c2b60)
        self.invoke(constructor, self.EVALUATOR, [])
        self.invoke(0x10287da0, self.EVALUATOR, [self.EMITTER + field])
        self.set_integer(self.EVALUATOR + 0x28, self.EMITTER)
        self.invoke(prepare, self.EVALUATOR, [])
        active, constant = self.cpu.mem_read(self.EVALUATOR + 0x2c, 2)
        resolution = self.integer(self.EMITTER + 0x1104)
        count = 1 if constant else resolution + 1
        pointer = self.EVALUATOR + 0x30 if constant else self.integer(self.EVALUATOR + 0x34)
        data = self.cpu.mem_read(pointer, 4 * count)
        return dict(active=bool(active), count=count, sha256=hashlib.sha256(data).hexdigest())

    def cached_color(self):
        self.invoke(0x102c3520, self.EVALUATOR, [])
        self.invoke(0x10287da0, self.EVALUATOR, [self.EMITTER + 0x64])
        self.set_integer(self.EVALUATOR + 0x28, self.EMITTER)
        self.invoke(0x102c2dc0, self.EVALUATOR, [])
        active, constant = self.cpu.mem_read(self.EVALUATOR + 0x2c, 2)
        if (active, constant) != (1, 0):
            raise ValueError("Expected a sampled Beautify color cache")
        count = self.integer(self.EMITTER + 0x1104) + 1
        pointer = self.integer(self.EVALUATOR + 0x4c)
        data = bytes(self.cpu.mem_read(pointer, count * 4))
        colors = list(struct.unpack(f'<{count}I', data))
        for channel, offset in enumerate((0x48, 0x44, 0x40)):
            pointer = self.integer(self.EVALUATOR + offset)
            if bytes(self.cpu.mem_read(pointer, count)) != data[channel::4]:
                raise ValueError("Native particle color channel and packed caches disagree")
        self.set_float(self.PARTICLE_CONTEXT + 0x68, 0.0)
        samples = []
        for time in self.COLOR_TIMES:
            argument, = struct.unpack('<I', struct.pack('<f', time))
            samples.append(self.invoke(0x102c1330, self.EVALUATOR,
                                       [argument, 0, self.EMITTER, self.PARTICLE_CONTEXT]))
        return dict(cache=colors, samples=samples, time_scale=self.float(self.EMITTER + 0x4c))

    def draw_colors(self):
        # The native renderer consumes the two already-loaded evaluator wrappers.
        color = self.EMITTER + 0x1108
        opacity = self.EMITTER + 0x12e0
        self.invoke(0x10287da0, color, [self.EMITTER + 0x64])
        self.invoke(0x102c2dc0, color, [])
        self.invoke(0x10287da0, opacity, [self.EMITTER + 0xdd4])
        self.invoke(0x102c2b60, opacity, [])
        if self.cpu.mem_read(self.EMITTER + 0x54, 1)[0]:
            raise ValueError("Beautify changed to randomized color selection")

        self.set_integer(self.DRAW_CONTEXT + 0x194, self.PARTICLE_CONTEXT)
        self.set_integer(self.DRAW_CONTEXT + 0x1cc, self.DRAW_OUTPUT)
        self.set_integer(self.PARTICLE_CONTEXT + 0x08, self.EFFECT)
        self.set_integer(self.PARTICLE_CONTEXT + 0x0c, self.EMITTER)
        self.set_integer(self.PARTICLE_CONTEXT + 0x1c, self.PARTICLE)
        self.set_integer(self.EFFECT + 0x150, self.EFFECT_STATE)
        self.set_float(self.PARTICLE + 0x0c, 1.0)
        samples = []
        for remaining, lifetime, alpha, effect, parent, phase in self.DRAW_INPUTS:
            self.set_integer(self.PARTICLE + 0x1c, remaining)
            # The position is already transformed. The remaining 29 bits hold lifetime.
            self.set_integer(self.PARTICLE + 0x3c, 0x80000000 | lifetime)
            self.set_integer(self.PARTICLE_CONTEXT + 0x4c, 0 if alpha is None else self.DRAW_OPACITY)
            self.set_integer(self.PARTICLE_CONTEXT + 0x44, 0 if phase is None else self.DRAW_PHASE)
            self.set_float(self.DRAW_OPACITY, 0.0 if alpha is None else alpha)
            self.set_float(self.DRAW_PHASE, 0.0 if phase is None else phase)
            self.set_float(self.EFFECT_INSTANCE + 0x18, effect)
            self.set_integer(self.EFFECT_INSTANCE + 0x200, 0 if parent is None else self.EFFECT_PARENT)
            self.set_float(self.EFFECT_PARENT + 0x18, 0.0 if parent is None else parent)
            self.invoke(0x102a1410, self.EFFECT_STATE, [self.EFFECT_INSTANCE])
            output = self.invoke(0x1029e060, self.DRAW_CONTEXT, [])
            packed = self.integer(self.DRAW_OUTPUT + 0x18)
            if output != (self.DRAW_OUTPUT if packed >> 24 else 1):
                raise ValueError("Native draw result disagrees with the packed opacity")
            samples.append(packed)
        return samples

    def load(self, emitter):
        self.invoke(self.CONSTRUCTOR, self.EMITTER, [self.PARENT])
        self.position = emitter['definition_offset']
        self.end = emitter['end']
        self.invoke(self.LOAD_EMITTER, self.EMITTER, [self.STREAM, 0, 0])
        curves = []
        for (offset, pointer), source_curve in zip(self.curves, emitter['curves'], strict=True):
            relative = pointer - self.EMITTER
            curve = dict(offset=offset, emitter_field=relative if 0 <= relative < self.EMITTER_BYTES else None,
                         keys=self.primary_keys[pointer])
            if 'secondary_keys' in source_curve:
                curve['secondary_keys'] = self.secondary_keys[pointer]
                curve['secondary_flags'] = self.integer(pointer + 0xc8)
            if 'secondary_limits' in source_curve:
                curve['secondary_limits'] = [self.float(pointer + offset) for offset in (0xcc, 0xd0)]
            curves.append(curve)
        scalar_curves = {}
        for field, source in emitter['scalar_curves'].items():
            scalar_curves[field] = {}
            for kind in ('primary', 'secondary'):
                if kind not in source:
                    continue
                secondary = kind == 'secondary'
                scalar_curves[field][kind] = dict(keys=self.compiled_keys(int(field, 16), secondary),
                                                  values=self.sample_scalar(int(field, 16), secondary),
                                                  cache=self.cached_curve(int(field, 16), secondary))
        return dict(name=emitter['name'], end=self.position, curves=curves, scalar_curves=scalar_curves,
                    color=self.cached_color(), draw_colors=self.draw_colors(),
                    cache_resolution=self.integer(self.EMITTER + 0x1104))


class ScenePlayback(EmitterLoader):
    ROOT_EFFECT = Oracle.SCRATCH + 0x8800
    UPDATE_CONTEXT = Oracle.SCRATCH + 0x9000
    TIMESTEPS = (0, 16, 16, 33, 50, 100, 100, 100, 100, 100, 200, 300, 500)
    FRACTIONAL_TIMESTEPS = (7.25, 33.333, 0.001, 0.0, 16.6667, 33.3333, 26.5, 100.125, 100.375, 500, 500, 500)
    RECYCLE_TIMESTEPS = (0, 50, 33.333, 350.25, 120, 23, 500, 4, 350, 125, 40, 300, 500, 900)
    RELEASE_STEP = 9
    BIRTH_RETURNS = (0x102aeba5, 0x102aec0f)
    BEGIN_PARTICLE = 0x102a32a0
    INITIALIZED_PARTICLE = 0x102b95d4
    UPDATED_SIZE = 0x102ace09
    READ_RATE = 0x102aea24
    RATE_LANES = 0x102aea29
    SELECTED_RATE = 0x102aea66
    RATE_QUOTA = 0x102aea9a
    RNG_STATE = 0x1115afe0

    def __init__(self, executable, library):
        super().__init__(executable, library)
        self.births = 0
        self.rate_samples = []
        self.age_sizes = []
        self.adapters.update({0x10001020: self.allocate, 0x103571c0: self.free,
                              0x10357320: self.resize})

    def resize(self):
        old, size = self.arguments(2)
        new = self.reserve(size)
        if old:
            length = min(self.allocations[old], size)
            self.cpu.mem_write(new, bytes(self.cpu.mem_read(old, length)))
        self.return_integer(new)

    def hook(self, cpu, address, size, user):
        if address in self.BIRTH_RETURNS:
            count = cpu.reg_read(self.regs.UC_X86_REG_EAX)
            if count > 256:
                raise ValueError("Native Beautify birth count exceeds bounds")
            self.births += count
            self.rate_samples[-1]['seed_after_birth'] = self.integer(self.RNG_STATE)
        elif address == self.READ_RATE:
            evaluator = cpu.reg_read(self.regs.UC_X86_REG_ECX)
            runtime = cpu.reg_read(self.regs.UC_X86_REG_ESI)
            if self.integer(evaluator + 0x30) != self.integer(runtime + 0x14) + 0x2b8:
                raise ValueError("Native Beautify scheduler used a different rate curve")
        elif address == self.RATE_LANES:
            stack = cpu.reg_read(self.regs.UC_X86_REG_ESP)
            instance = cpu.reg_read(self.regs.UC_X86_REG_EDI)
            runtime = cpu.reg_read(self.regs.UC_X86_REG_ESI)
            self.rate_samples.append(dict(phase=self.float(instance + 0x48),
                                          rates=[self.float(stack + offset) for offset in (0xbc, 0xac)],
                                          seed_before=self.integer(self.RNG_STATE),
                                          carry_before=self.float(runtime + 0x20)))
        elif address == self.SELECTED_RATE:
            stack = cpu.reg_read(self.regs.UC_X86_REG_ESP)
            self.rate_samples[-1].update(rate=self.float(stack + 0x5c), seed_after=self.integer(self.RNG_STATE))
        elif address == self.RATE_QUOTA:
            runtime = cpu.reg_read(self.regs.UC_X86_REG_ESI)
            self.rate_samples[-1].update(quota=cpu.reg_read(self.regs.UC_X86_REG_EBX),
                                         carry_after=self.float(runtime + 0x20))
        elif address == self.BEGIN_PARTICLE:
            self.birth_seed = self.integer(self.RNG_STATE)
        elif address == self.INITIALIZED_PARTICLE:
            if not cpu.reg_read(self.regs.UC_X86_REG_EAX) & 0xff:
                raise ValueError("Original Beautify rejected a particle at birth")
            self.capture_birth(cpu)
        elif address == self.UPDATED_SIZE:
            particle = cpu.reg_read(self.regs.UC_X86_REG_EDI)
            runtime = cpu.reg_read(self.regs.UC_X86_REG_EBP)
            slot = (particle - self.integer(runtime + 0x34)) // 0x50
            self.age_sizes.append(dict(
                remaining_ms=self.integer(particle + 0x1c),
                lifetime_ms=self.integer(particle + 0x3c) & 0x1fffffff,
                base_size=self.float(self.integer(runtime + 0x44) + slot * 4),
                size=self.float(particle + 0xc)))
        super().hook(cpu, address, size, user)

    def capture_birth(self, cpu):
        runtime = cpu.reg_read(self.regs.UC_X86_REG_ESI)
        particle = cpu.reg_read(self.regs.UC_X86_REG_EDI)
        slot = cpu.reg_read(self.regs.UC_X86_REG_EBP)
        frame_bank = self.integer(runtime + 0x3c)
        variant_bank = self.integer(runtime + 0x5c)
        if not variant_bank or not 0 <= slot < 256 or particle != self.integer(runtime + 0x34) + slot * 0x50:
            raise ValueError("Unexpected Beautify particle layout at birth")
        x, y, z, size, aspect, angle = struct.unpack('<6f', self.cpu.mem_read(particle, 24))
        self.rate_samples[-1].setdefault('particles_at_birth', []).append(dict(
            slot=slot, seed_before=self.birth_seed, seed_after=self.integer(self.RNG_STATE),
            lifetime_ms=self.integer(particle + 0x3c) & 0x1fffffff,
            offset=[x, y, z], size=size, aspect=aspect, rotation_degrees=angle,
            base_size=self.float(self.integer(runtime + 0x44) + slot * 4),
            speed=self.float(particle + 0x44),
            spin=self.float(self.integer(runtime + 0x4c) + slot * 4),
            azimuth=self.float(particle + 0x40), elevation=self.float(particle + 0x48),
            frame=self.cpu.mem_read(frame_bank + slot * 2 + 1, 1)[0] if frame_bank else 0,
            texture_variant=self.cpu.mem_read(variant_bank + slot, 1)[0]))

    def particles(self, runtime):
        bank = self.integer(runtime + 0x34)
        used = self.integer(runtime + 0x30)
        if not 0 <= used <= self.integer(runtime + 0x2c) <= 256:
            raise ValueError("Native Beautify particle bank exceeds bounds")
        frame_bank = self.integer(runtime + 0x3c)
        particles = []
        for slot in range(used):
            particle = bank + slot * 0x50
            remaining = self.integer(particle + 0x1c)
            if not remaining:
                continue
            lifetime = self.integer(particle + 0x3c) & 0x1fffffff
            x, y, z, size, _, angle = struct.unpack('<6f', self.cpu.mem_read(particle, 24))
            frame = self.cpu.mem_read(frame_bank + slot * 2 + 1, 1)[0] if frame_bank else 0
            particles.append([slot, remaining, lifetime, [x, y, z], size, angle, frame])
        if len(particles) != self.integer(runtime + 0x1c):
            raise ValueError("Live Beautify particles disagree with the emitter count")
        return particles

    def capture(self, manifest, timesteps=TIMESTEPS, release_step=RELEASE_STEP):
        self.position = manifest['scene']['offset']
        self.end = manifest['emitters'][-1]['end']
        self.invoke(0x1028f680, self.PARENT, [])
        self.invoke(0x1028fee0, self.PARENT, [self.STREAM, 0])
        group_end = self.position
        count = self.integer(self.PARENT + 0x2f4)
        if count != len(manifest['emitters']):
            raise ValueError("Native Beautify child count disagrees with the directory")

        self.invoke(0x102a0ce0, self.UPDATE_CONTEXT, [])
        self.set_integer(0x1115e6ac, self.UPDATE_CONTEXT)
        # The uninitialized mode-zero transform dispatch leaves the constant
        # source track untouched. Install the executable's identity callback.
        self.set_integer(0x1061e5b8, 0x10001000)
        self.invoke(0x102a1520, self.ROOT_EFFECT, [])
        self.set_float(self.ROOT_EFFECT + 0x14, manifest['scene']['scale'])
        instances = []
        clocks = []
        for index, emitter in enumerate(manifest['emitters']):
            child = self.integer(self.integer(self.PARENT + 0x2f8) + index * 4)
            if self.integer(child + 0xcd8) != 1:
                raise ValueError("Expected one native emitter per Beautify child")
            name = self.invoke(0x102cb5e0, child + 0x10, [])
            expected = emitter['name'].encode('ascii') + b'\0'
            if bytes(self.cpu.mem_read(name, len(expected))) != expected:
                raise ValueError("Native Beautify child order disagrees with the directory")
            clocks.append(dict(duration_ms=self.integer(child + 0x1000), samples_per_second=self.integer(child + 0x1004),
                               start_percent=self.float(child + 0x1008),
                               end_percent=self.float(child + 0x100c), time_scale=self.float(child + 0x1014)))
            self.invoke(0x102aa770, self.ROOT_EFFECT, [child])
            instance = self.integer(self.integer(self.ROOT_EFFECT + 0x1fc) + index * 4)
            runtime = self.integer(self.integer(self.integer(instance + 0x80) + 0x1c))
            instances.append((instance, runtime))

        frames = []
        for step, delta in enumerate(timesteps):
            if step == release_step:
                self.invoke(0x1029eae0, self.ROOT_EFFECT, [1])
            arguments = struct.unpack('<2I', struct.pack('<d', delta))
            frame = []
            for instance, runtime in instances:
                self.births = 0
                self.rate_samples = []
                self.age_sizes = []
                self.cpu.mem_write(instance + 0x39c, b'\x01')
                status = self.invoke(0x102adf70, instance, arguments)
                frame.append(dict(births=self.births, finished=status == 0xfffffffe,
                                  phase=self.float(instance + 0x34), next_sample=self.float(instance + 0x48),
                                  seed=self.integer(instance + 0x198), rates=self.rate_samples,
                                  age_sizes=self.age_sizes,
                                  particles=self.particles(runtime)))
            frames.append(frame)
        return dict(group_end=group_end, clocks=clocks, timesteps_ms=timesteps,
                    release_step=release_step, frames=frames)


def capture():
    source = ROOT / 'data/godus2_4'
    manifest = extract(source)
    executable = (source / 'godus.s86').read_bytes()
    library = (source / manifest['source']['library']).read_bytes()
    emitters = [EmitterLoader(executable, library).load(emitter) for emitter in manifest['emitters']]
    return dict(executable_sha256=manifest['source']['executable_sha256'],
                library_sha256=manifest['source']['library_sha256'], sample_times=EmitterLoader.SAMPLE_TIMES,
                color_times=EmitterLoader.COLOR_TIMES, draw_inputs=EmitterLoader.DRAW_INPUTS, emitters=emitters,
                playback=ScenePlayback(executable, library).capture(manifest),
                fractional_playback=ScenePlayback(executable, library).capture(manifest, ScenePlayback.FRACTIONAL_TIMESTEPS),
                recycle_playback=ScenePlayback(executable, library).capture(manifest, ScenePlayback.RECYCLE_TIMESTEPS, 12))


if __name__ == '__main__':
    result = capture()
    path = ROOT / 'game/tests/fixtures/source_beautify_particles.json'
    path.write_text(json.dumps(result, indent=2) + '\n')
    print(f"Native Beautify emitter loader read {sum(len(row['curves']) for row in result['emitters'])} curves")
