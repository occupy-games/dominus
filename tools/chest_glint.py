"""Recover the original buried treasure cue, frame, and particle curves."""

import hashlib
import json
import struct

from tools.beautify_particles import (
    Reader, compile_emitter_curves, constant_birth_lanes, directory,
    emitter_frames, playback_constants, record_offsets,
)
from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage, ROOT
from tools.particle_curves import color_cache, float32, sample_curve


REGISTRATION = 0x105E3890
DRAW_LOAD = 0x10152E1E
SCRIPT = 'VFX/Scripts/UI_TreasureCards_Spot.txt'
LIBRARY = 'VFX/Particles/Misc.ptc'
ATLAS = 'VFX/Textures/Misc.png'
BALANCE = 'received/godussteamrel/balance.datz'


def timing(image, files):
    threshold_slot = 0x10C97E14
    if image.read(0x1041C9B0, 6) != b'\xd9\x05' + struct.pack('<I', threshold_slot):
        raise ValueError("Treasure effect threshold has moved")
    # The supplied desktop PE declares this default in its zero-filled tail.
    if not any(start + backed <= threshold_slot and threshold_slot + 4 <= start + size
               for start, _, backed, size in image.sections):
        raise ValueError("Unexpected storage for the treasure effect threshold")
    values = {'TreasureEffectHeightThreshold': 0.0}
    for name, address in (('TimeBetweenBuriedTreasureVFXMin', 0x105D809C),
                          ('TimeBetweenBuriedTreasureVFXMax', 0x105D8478)):
        values[name], = struct.unpack('<f', image.read(address, 4))
    for path in ('config.csv', 'balance/config.csv'):
        for row in rows(files, path):
            if len(row) > 1 and row[0] in values:
                values[row[0]] = float(row[1])
    return dict(height_threshold=values['TreasureEffectHeightThreshold'],
                delay=[values['TimeBetweenBuriedTreasureVFXMin'],
                       values['TimeBetweenBuriedTreasureVFXMax']])


def rates(clock, curve):
    # The source scheduler reads both lanes at each due sample, before
    # interpolating with the presentation RNG and carrying fractional births.
    phase = float32(clock['start_percent'])
    step = float32(100000.0 / clock['samples_per_second'] / clock['duration_ms'])
    result = []
    while phase < clock['end_percent']:
        result.append(sorted(sample_curve(curve[lane], curve['conversion'], phase)
                             for lane in ('primary', 'secondary')))
        phase = float32(phase + step)
    return result


def extract(source):
    executable = (source / 'godus.s86').read_bytes()
    image = NativeImage(executable)
    handle, initial, script_pointer = struct.unpack('<III', image.read(REGISTRATION, 12))
    if initial or image.read(DRAW_LOAD, 5) != b'\xa1' + struct.pack('<I', handle):
        raise ValueError("Buried treasure draw and particle registration disagree")
    if image.read(script_pointer, 64).split(b'\0')[0].decode('ascii') != SCRIPT:
        raise ValueError("Unexpected buried treasure particle script")
    script = (source / SCRIPT).read_bytes()
    library = (source / LIBRARY).read_bytes()
    atlas = (source / ATLAS).read_bytes()
    archive = (source / BALANCE).read_bytes()
    settings = dict(line.strip().split('=', 1) for line in script.decode('ascii').splitlines()
                    if '=' in line and not line.lstrip().startswith('#'))
    if settings['PTC'].split('\\')[-1] != 'Misc.ptc' or settings['RANDOM'] != '1':
        raise ValueError("Unsupported buried treasure particle script")
    if library[:4] != b'BIU\x05' or struct.unpack_from('<I', library, 0x13)[0] != 6:
        raise ValueError("Unsupported particle library version")
    toc, = struct.unpack_from('<I', library, 0x1d)
    body, = struct.unpack_from('<I', library, 0x31)
    if not 0x35 <= body < toc < len(library):
        raise ValueError("Missing buried treasure particle directory")
    index = Reader(library, toc, len(library))
    root = directory(index, body, toc)
    group, = [entry for entry in root['children'] if entry['name'] == 'Misc']
    scene, = [entry for entry in group['children'] if entry['name'] == settings['SHOWPTC']]
    child, = scene['children']
    start = child['offset']
    end = min(offset for offset in [*record_offsets(root), toc] if offset > start)
    if index.offset != len(library) or atlas[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
        raise ValueError("Invalid buried treasure atlas or directory")
    atlas_size = struct.unpack_from('>II', atlas, 16)
    texture = Reader(library, 0x3b, body)
    if texture.string() != 'Misc.png':
        raise ValueError("Unexpected buried treasure atlas name")
    # The shipped atlas has half the author's pixel dimensions. Preserve
    # the normalized source UVs so the render samples the correct region.
    authored_size = texture.unpack('<2I')
    if authored_size != tuple(axis * 2 for axis in atlas_size):
        raise ValueError("Unexpected buried treasure atlas resolution")
    emitter = emitter_frames(library, start, end, child['name'], 'Misc.png', authored_size, frame_mode=2)
    if (emitter['birth']['texture_variants'] or not emitter['birth']['random_color_phase']
            or emitter['birth']['frame_count'] != 1 or not emitter['birth']['linked_direction']):
        raise ValueError("Unsupported buried treasure birth mode")
    constants, rng = playback_constants(image)
    curves = emitter['curves']
    fields = {0x1e4, 0x2b8, 0x38c, 0x460, 0x534, 0x608, 0x6dc, 0x948, 0xa14, 0xad4, 0xb94, 0xdd4, 0xe94}
    emitter['scalar_curves'] = compile_emitter_curves(
        [curve for curve in curves if curve['emitter_field'] in fields],
        constants, emitter['curve_cache_resolution'], clamped_fields=(0x2b8,),
    )
    for name, field in (('lifetime', 0x1e4), ('size', 0x38c), ('speed', 0x460),
                        ('vertical_speed', 0x534), ('spin', 0x608), ('yaw_drift', 0x6dc),
                        ('azimuth_degrees', 0xe94)):
        emitter['birth'][name] = sorted(constant_birth_lanes(emitter, field, 3))
    rate_curve = emitter['scalar_curves']['0x2b8']
    size_curve, = [curve for curve in curves if curve['emitter_field'] == 0x948]
    if size_curve['secondary_flags'] != 3:
        raise ValueError("The buried treasure particle requires two size axes")
    emitter['size_axes'] = True
    emitter['rate_samples'] = rates(emitter['clock'], rate_curve)
    color, = [curve for curve in curves if curve['emitter_field'] == 0x64]
    emitter['color_cache'] = color_cache(color['keys'], emitter['curve_cache_resolution'])
    return dict(
        version=1, source=dict(script=SCRIPT, library=LIBRARY, atlas=ATLAS,
                               script_sha256=hashlib.sha256(script).hexdigest(),
                               library_sha256=hashlib.sha256(library).hexdigest(),
                               atlas_sha256=hashlib.sha256(atlas).hexdigest(),
                               executable_sha256=hashlib.sha256(executable).hexdigest(),
                               balance_sha256=hashlib.sha256(archive).hexdigest(),
                               registration=REGISTRATION, draw_load=DRAW_LOAD),
        timing=timing(image, decode_archive(archive)),
        scene=dict(name=scene['name'], offset=scene['offset'], scale=float(settings['SCALE']),
                   offset_xyz=[float(value) for value in settings['OFFSET'].split(',')]),
        atlas_size=atlas_size, curve_constants=constants, emission_rng=rng, emitters=[emitter],
    )


def write(manifest):
    emitter, = manifest['emitters']
    # The runtime consumes the authored frames and lookup tables. Source key
    # decoding and native comparisons are tooling concerns.
    fields = ('birth', 'clock', 'curve_cache_resolution', 'rate_samples', 'size_axes',
              'frames', 'color_cache', 'color_time_scale')
    playback = {key: emitter[key] for key in fields}
    playback['scalar_curves'] = {
        key: {'cache': curve['cache']}
        for key, curve in emitter['scalar_curves'].items()
        if key in ('0x948', '0xa14', '0xad4', '0xb94', '0xdd4')
    }
    result = {key: value for key, value in manifest.items() if key != 'emitters'}
    result['emitter'] = playback
    (ROOT / 'game/assets/original/chest_glint.json').write_text(json.dumps(result, separators=(',', ':')) + '\n')


if __name__ == '__main__':
    write(extract(ROOT / 'data/godus2_4'))
    print("Recovered the original buried treasure particle and surface cue")
