"""Recover the original Beautify particle registration, emitters and atlas frames."""
import hashlib
import json
import math
from pathlib import PureWindowsPath
import struct

from tools.native_scenery_oracle import NativeImage, ROOT
from tools.particle_curves import cache_curve, color_cache, compile_keys, constant_curve

# Read order of the version-20 emitter at 0x1028d230. Fields without an
# emitter offset belong to nested objects loaded by the same curve reader.
CURVE_FIELDS = (0x64, 0x1e4, 0x2b8, 0x38c, 0x460, 0x534, 0x608, 0x6dc, 0x7b0, 0x87c,
                0x948, 0xa14, 0xad4, 0xb94, 0xc54, 0xd14, 0xdd4, None, None, None, None,
                None, None, None, None, None, 0xe94, 0xf60)
# These are the intervening fields in the authored Beautify records. The
# decoder checks the next curve's header after every one of these spans.
CURVE_GAPS = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34, 66, 70, 68, 69, 68, 81, 178, 176, 137, 0, 0)


class Reader:
    def __init__(self, data, offset, limit):
        self.data = data
        self.offset = offset
        self.limit = limit

    def take(self, size):
        end = self.offset + size
        if self.offset < 0 or end > self.limit:
            raise ValueError("Particle record ends unexpectedly")
        data = self.data[self.offset:end]
        self.offset = end
        return data

    def unpack(self, fmt):
        return struct.unpack(fmt, self.take(struct.calcsize(fmt)))

    def string(self):
        length, = self.unpack('<B')
        return self.take(length).decode('ascii')


def directory(reader, body_start, body_end, leaf=False, depth=0):
    toc_offset = reader.offset
    name = reader.string()
    offset, = reader.unpack('<I')
    if not body_start <= offset < body_end or depth > 8:
        raise ValueError("Invalid particle record offset or depth")
    children = []
    if not leaf:
        magic, reserved, kind, count = reader.unpack('<IIHI')
        if magic != 0x001b4da8 or reserved or kind not in (0, 1) or count > 256:
            raise ValueError("Unsupported particle directory record")
        for _ in range(count):
            tag, = reader.unpack('<B')
            if tag not in (0, 1):
                raise ValueError("Unknown particle directory entry")
            children.append(directory(reader, body_start, body_end, tag == 1, depth + 1))
    return dict(name=name, offset=offset, toc_offset=toc_offset, children=children)


def record_offsets(node):
    yield node['offset']
    for child in node['children']:
        yield from record_offsets(child)


def call_target(image, address):
    opcode, relative = struct.unpack('<Bi', image.read(address, 5))
    if opcode != 0xe8:
        raise ValueError("Expected direct particle lifecycle call")
    return address + 5 + relative


def curve_keys(reader, count):
    if not 1 <= count <= 256:
        raise ValueError("Invalid Beautify curve key count")
    keys = []
    for _ in range(count):
        time, bits, lx, ly, rx, ry, tag = reader.unpack('<fI4fB')
        if tag != 0x7f or not all(map(math.isfinite, (time, lx, ly, rx, ry))):
            raise ValueError("Unsupported Beautify curve key encoding")
        reserved, weight, *flags = reader.unpack('<If3B')
        if reserved or not math.isfinite(weight):
            raise ValueError("Unsupported Beautify key modifier")
        keys.append(dict(time=time, value_bits=bits, left=[lx, ly], right=[rx, ry],
                         weight=weight, flags=flags))
    if any(left['time'] > right['time'] for left, right in zip(keys, keys[1:])):
        raise ValueError("Beautify curve keys are out of order")
    return keys


def emitter_curves(reader):
    padding, atlas_field, f0, f1, f2, x, y = reader.unpack('<BIBBB2f')
    if (padding, atlas_field, f0, f1, f2) != (0, 4, 1, 0, 0):
        raise ValueError("Unexpected fields between the Beautify frame bank and curves")
    curves = []
    for ordinal, (field, gap) in enumerate(zip(CURVE_FIELDS, CURVE_GAPS)):
        offset = reader.offset
        magic, version, word, first_flag, factor, second_flag, count = reader.unpack('<IIIBfBI')
        if (magic, version) != (0x6289fe31, 7) or not math.isfinite(factor):
            raise ValueError(f"Unexpected version-7 Beautify curve at {offset:#x}")
        curve = dict(offset=offset, emitter_field=field, header=[word, first_flag, factor, second_flag],
                     keys=curve_keys(reader, count))
        # Tail fields at object offsets 0x30–0x90 in the version-7 reader.
        curve['options'] = reader.take(98).hex()
        if 1 <= ordinal <= 10 or ordinal >= 26:
            second_count, = reader.unpack('<I')
            curve['secondary_keys'] = curve_keys(reader, second_count)
            curve['secondary_flags'], = reader.unpack('<I')
            if ordinal <= 7:
                curve['secondary_limits'] = list(reader.unpack('<2f'))
        reader.take(gap)
        curves.append(curve)
    return [x, y], curves


def compile_emitter_curves(curves, constants, resolution):
    compiled = {}
    for curve in curves:
        field = curve['emitter_field']
        if field is None or field == 0x64:  # Nested records and the packed color curve.
            continue
        percent = constants['percent']
        conversion = [0.0, percent, 0.0]
        if 'secondary_limits' in curve:
            low, high = curve['secondary_limits']
            conversion = [0.0, (high - low) * percent, low]
        elif field in (0xa14, 0xad4, 0xb94, 0xc54):
            conversion[0] = constants['center']
        elif field in (0x7b0, 0x87c, 0xe94, 0xf60):
            conversion[1] = 1.0
        lanes = {'primary': compile_keys(curve['keys'], constants['cubic_step'])}
        if 'secondary_keys' in curve:
            lanes['secondary'] = compile_keys(curve['secondary_keys'], constants['cubic_step'])
        mask = curve.get('secondary_flags', 1)
        enabled = [keys for index, keys in enumerate(lanes.values()) if mask & (1 << index)]
        if not enabled or not curve['header'][1]:
            raise ValueError("Unsupported disabled Beautify scalar")
        # The constant predicate and value are shared by both evaluator lanes.
        initial = enabled[0][0][1]
        constant = initial if all(keys[0][1] == initial and constant_curve(keys) for keys in enabled) else None
        cache = {lane: cache_curve(keys, conversion, resolution, constants['neutral'], constant)
                 for lane, keys in lanes.items()}
        compiled[hex(field)] = {**lanes, 'conversion': conversion, 'cache': cache}
    return compiled


def constant_birth_lanes(emitter, field, mask, order=('primary', 'secondary')):
    curve, = [curve for curve in emitter['curves'] if curve['emitter_field'] == field]
    if (any(len(curve[key]) != 1 for key in ('keys', 'secondary_keys'))
            or curve['secondary_flags'] != mask):
        raise ValueError(f"Unsupported Beautify birth curve at {curve['offset']:#x}")
    cache = emitter['scalar_curves'][hex(field)]['cache']
    return [cache[lane]['values'][0] for lane in order]


def birth_shape(reader):
    # The version-16 child follows the emitter with its own tracks. Its
    # sphere ends with the dual radius track and the two 0x102b9d59 flags.
    shape = Reader(reader.data, reader.offset + 0xa26, reader.limit)
    if shape.unpack('<IIIBfBI') != (0x6289fe31, 7, 2000, 1, 1.0, 1, 1):
        raise ValueError("Expected constant Beautify outer radius")
    outer, = curve_keys(shape, 1)
    shape.take(98)
    if shape.unpack('<I') != (1,):
        raise ValueError("Expected constant Beautify inner radius")
    inner, = curve_keys(shape, 1)
    mask, link_yaw, link_pitch = shape.unpack('<I2B')
    radii = list(struct.unpack('<2f', struct.pack('<2I', outer['value_bits'], inner['value_bits'])))
    if (mask != 3 or outer['time'] != 0 or inner['time'] != 0
            or not all(map(math.isfinite, radii)) or not 0 <= radii[1] <= radii[0]
            or (link_yaw, link_pitch) not in ((0, 0), (1, 1))):
        raise ValueError("Unsupported Beautify spherical birth shape")
    return dict(radius=radii, linked_direction=bool(link_yaw))


def emitter_frames(ptc, start, end, name, atlas, size):
    header = Reader(ptc, start, end)
    if header.unpack('<i4I') != (-1, 0, 1, 0, 16):
        raise ValueError("Expected a version-16 Beautify child effect")
    if header.string() != name:
        raise ValueError("Particle directory and emitter header disagree")
    if header.unpack('<B') != (1,) or header.string() != name:
        raise ValueError("Unexpected Beautify child effect name")
    # 0x1028ee10 loads these fields into the child effect used by 0x102adf70.
    _, duration, sample_rate, start_percent, end_percent, time_scale = header.unpack('<III3f')
    if not duration or not sample_rate or not all(map(math.isfinite, (start_percent, end_percent, time_scale))):
        raise ValueError("Invalid Beautify child clock")
    if not 0 <= start_percent < end_percent <= 100 or time_scale <= 0:
        raise ValueError("Unsupported Beautify child clock range")
    clock = dict(duration_ms=duration, samples_per_second=sample_rate, start_percent=start_percent,
                 end_percent=end_percent, time_scale=time_scale)
    # The version-16 child loader reads the elevation lanes at 0x1028f085
    # and 0x1028f093, before its shape and emitter records.
    header.take(73)
    elevation = list(header.unpack('<2f'))
    if not 0 <= elevation[0] <= elevation[1] or not all(map(math.isfinite, elevation)):
        raise ValueError("Invalid Beautify birth elevation")
    signature = struct.pack('<I', 0x97492116)
    frame_offset = ptc.find(signature, header.offset, end)
    if frame_offset < 0 or ptc.find(signature, frame_offset + 4, end) >= 0:
        raise ValueError("Expected one texture-frame bank in the emitter")
    definition_header = struct.pack('<iII', -1, 1, 20)
    definition_offset = ptc.find(definition_header, header.offset, frame_offset)
    if definition_offset < 0 or ptc.find(definition_header, definition_offset + 4, frame_offset) >= 0:
        raise ValueError("Expected one version-20 emitter definition")
    definition = Reader(ptc, definition_offset + len(definition_header), frame_offset)
    definition_name = definition.string()
    if not definition_name:
        raise ValueError("Emitter definition has no name")
    # The version-20 reader copies these fields to 0x4c and 0x1104.
    definition.take(2)
    color_time_scale, = definition.unpack('<f')
    _, alternate_color = definition.unpack('<2B')  # Fields 0x59 and 0x54.
    _, _, flip_x, flip_y, _, random_frame = definition.unpack('<6B')
    frames_per_second, = definition.unpack('<I')
    definition.take(4)
    random_rotation, rotation_min, rotation_max = definition.unpack('<B2i')
    definition.take(26)
    cache_resolution, = definition.unpack('<I')
    if not math.isfinite(color_time_scale) or color_time_scale <= 0:
        raise ValueError("Invalid particle color time scale")
    if alternate_color:
        raise ValueError("Unsupported alternate Beautify color phase")
    if ((flip_x, flip_y, random_frame, random_rotation) != (1, 1, 1, 1)
            or frames_per_second or not 0 <= rotation_min < rotation_max <= 360):
        raise ValueError("Unsupported Beautify birth texture or rotation mode")
    if not 2 <= cache_resolution <= 1024:
        raise ValueError("Particle curve cache resolution is out of bounds")
    reader = Reader(ptc, frame_offset + 4, end)
    count, = reader.unpack('<I')
    if not 1 <= count <= 256:
        raise ValueError("Invalid particle frame count")
    frames = []
    for _ in range(count):
        page, original, runtime = (reader.string() for _ in range(3))
        width, height, x, y, w, h = reader.unpack('<6I')
        if page != atlas or runtime != atlas or not (0 < w <= width - x and 0 < h <= height - y):
            raise ValueError("Invalid particle frame atlas or trim")
        frames.append(dict(source_name=PureWindowsPath(original).name,
                           source_size=[width, height], trim=[x, y, w, h]))
    for frame in frames:
        u0, v0, u1, v1, w, h = reader.unpack('<4f2I')
        pixels = [u0 * size[0], v0 * size[1], u1 * size[0], v1 * size[1]]
        left, top, right, bottom = [round(value) for value in pixels]
        # The authored UV maxima identify the last texel, inclusive.
        if (pixels != [left, top, right, bottom] or frame['trim'][2:] != [w, h]
                or not (0 <= left <= right < size[0] and 0 <= top <= bottom < size[1])
                or [right - left + 1, bottom - top + 1] != [w, h]):
            raise ValueError("Particle UVs do not match the authored texel extent")
        frame.update(atlas_rect=[left, top, w, h], uv=[u0, v0, u1, v1])
    frame_parameters, curves = emitter_curves(reader)
    birth = dict(elevation=elevation, **birth_shape(reader), frame_count=count,
                 rotation_degrees=[rotation_min, rotation_max])
    return dict(name=name, offset=start, end=end, frame_bank_offset=frame_offset,
                definition_offset=definition_offset, definition_name=definition_name,
                definition_end=reader.offset, frame_parameters=frame_parameters,
                curve_cache_resolution=cache_resolution, color_time_scale=color_time_scale, clock=clock,
                sha256=hashlib.sha256(ptc[start:end]).hexdigest(), frames=frames, curves=curves, birth=birth)


def extract(source):
    executable = (source / 'godus.s86').read_bytes()
    image = NativeImage(executable)
    registration = 0x105e3764
    handle, initial, path_address = struct.unpack('<III', image.read(registration, 12))
    if initial or image.read(0x10086c3a, 5) != b'\xa1' + struct.pack('<I', handle):
        raise ValueError("Beautify contact and particle registration disagree")
    script_path = image.read(path_address, 64).split(b'\0')[0].decode('ascii')
    if script_path != 'VFX/Scripts/GOD_Beautify.txt':
        raise ValueError("Unexpected Beautify script")
    script = (source / script_path).read_bytes()
    settings = dict(line.strip().split('=', 1) for line in script.decode('ascii').splitlines() if '=' in line)
    library_name = PureWindowsPath(settings['PTC']).name
    library_path = f'VFX/Particles/{library_name}'
    ptc = (source / library_path).read_bytes()
    if ptc[:4] != b'BIU\x05' or struct.unpack_from('<I', ptc, 0x13)[0] != 6:
        raise ValueError("Unsupported particle library version")
    toc, = struct.unpack_from('<I', ptc, 0x1d)
    if not 0x5a < toc < len(ptc):
        raise ValueError("Missing particle directory")
    index = Reader(ptc, toc, len(ptc))
    root = directory(index, 0x5a, toc)
    if index.offset != len(ptc):
        raise ValueError("Unexpected data after particle directory")
    group, = [entry for entry in root['children'] if entry['name'] == 'God Powers']
    scene, = [entry for entry in group['children'] if entry['name'] == settings['SHOWPTC']]
    offsets = sorted(set(record_offsets(root)) | {toc})
    atlas_name = 'GodPowers.png'
    atlas_path = f'VFX/Textures/{atlas_name}'
    atlas = (source / atlas_path).read_bytes()
    if atlas[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
        raise ValueError("Expected PNG particle atlas")
    size = struct.unpack_from('>II', atlas, 16)
    constants = {name: struct.unpack('<d', image.read(address, 8))[0]
                 for name, address in [('cubic_step', 0x104f3990), ('percent', 0x104a3328),
                                       ('center', 0x104f2e10), ('opacity_byte_scale', 0x104f31d8)]}
    constants['neutral'] = [struct.unpack('<d', image.read(address, 8))[0] for address in (0x104f3988, 0x104f3980)]
    # Immediate operands and divisor of the random rate interpolation at 0x102868f0.
    multiply, increment = image.read(0x102868fd, 6), image.read(0x10286911, 5)
    if multiply[:2] != b'\x69\xc0' or increment[:1] != b'\x05':
        raise ValueError("Unexpected Beautify particle RNG")
    emission_rng = dict(multiplier=int.from_bytes(multiply[2:], 'little'),
                        increment=int.from_bytes(increment[1:], 'little'),
                        divisor=struct.unpack('<d', image.read(0x104f27f0, 8))[0])
    emitters = []
    for child in scene['children']:
        offset = child['offset']
        end = offsets[offsets.index(offset) + 1]
        emitter = emitter_frames(ptc, offset, end, child['name'], atlas_name, size)
        emitter['scalar_curves'] = compile_emitter_curves(emitter['curves'], constants, emitter['curve_cache_resolution'])
        rate, = [curve for curve in emitter['curves'] if curve['emitter_field'] == 0x2b8]
        if any(len(rate[key]) != 1 for key in ('keys', 'secondary_keys')) or rate['secondary_flags'] not in (1, 3):
            raise ValueError("Expected constant authored Beautify rate lanes")
        rate_cache = emitter['scalar_curves']['0x2b8']['cache']
        emitter['birth_rates'] = [rate_cache['secondary']['values'][0], rate_cache['primary']['values'][0]]
        size_curve, = [curve for curve in emitter['curves'] if curve['emitter_field'] == 0x948]
        if size_curve['secondary_flags'] != 2:
            raise ValueError("Unsupported Beautify size and aspect at birth")
        vertical_speed, = constant_birth_lanes(emitter, 0x534, 1, ('primary',))
        emitter['birth'].update(
            lifetime=constant_birth_lanes(emitter, 0x1e4, 3),
            size=constant_birth_lanes(emitter, 0x38c, 3),
            speed=constant_birth_lanes(emitter, 0x460, 3),
            vertical_speed=vertical_speed,
            spin=constant_birth_lanes(emitter, 0x608, 3, ('secondary', 'primary')),
            azimuth_degrees=constant_birth_lanes(emitter, 0xe94, 3))
        color, = [curve for curve in emitter['curves'] if curve['emitter_field'] == 0x64]
        emitter['color_cache'] = color_cache(color['keys'], emitter['curve_cache_resolution'])
        emitters.append(emitter)
    lifecycle = {name: dict(call=address, target=call_target(image, address))
                 for name, address in [('create', 0x10086c46), ('move', 0x10086c5a), ('stop', 0x1008653b)]}
    return dict(version=1, source=dict(script=script_path, library=library_path, atlas=atlas_path,
                script_sha256=hashlib.sha256(script).hexdigest(), library_sha256=hashlib.sha256(ptc).hexdigest(),
                atlas_sha256=hashlib.sha256(atlas).hexdigest(), executable_sha256=hashlib.sha256(executable).hexdigest()),
                registration=dict(address=registration, handle=handle, contact_load=0x10086c3a),
                lifecycle=lifecycle,
                curve_constants=constants, emission_rng=emission_rng,
                scene=dict(name=scene['name'], offset=scene['offset'], toc_offset=scene['toc_offset'],
                           scale=float(settings['SCALE']), offset_xyz=[float(x) for x in settings['OFFSET'].split(',')],
                           infinite=bool(int(settings['INFINITE'])), random=bool(int(settings['RANDOM']))),
                atlas_size=list(size), emitters=emitters)


if __name__ == '__main__':
    manifest = extract(ROOT / 'data/godus2_4')
    output = ROOT / 'game/assets/original/beautify_particles.json'
    output.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f"Original Beautify frames and curves recovered for {len(manifest['emitters'])} emitters")
