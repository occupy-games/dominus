"""Generate the finite original plot resize rules from the supplied source."""

import hashlib
import json
from pathlib import Path
import struct

from tools.native_scenery_oracle import NativeImage, ROOT, SOURCE_EXECUTABLE_SHA256


GROW = ['left', 'right', 'bottom', 'top', 'bottom_left', 'bottom_right', 'top_left', 'top_right']
GROW_SLOTS = [-0x80, -0x7c, -0x78, -0x74, -0x70, -0x6c, -0x68, -0x64]
REPAIR = ['inner_bottom', 'inner_top', 'inner_left', 'inner_right',
          'bottom_left', 'bottom_right', 'top_left', 'top_right',
          'outer_left', 'outer_right', 'outer_bottom', 'outer_top']
REPAIR_SLOTS = [-0x60, -0x40, -0x4c, -0x38, -0x58, -0x50, -0x24, -0x54, -0xc4, -0xc0, -0xbc, -0xb8]


def growth_action(mask, room):
    left, right, bottom, top, bottom_left, bottom_right, top_left, top_right = (
        bool(mask & (1 << bit)) for bit in range(len(GROW))
    )
    if not room:
        return 0, 0, 0
    if room > 1 and all((left, right, bottom, top, bottom_left, bottom_right, top_left, top_right)):
        return -1, -1, 2
    if left and bottom and bottom_left:
        return -1, 0, 1
    if right and bottom and bottom_right:
        return 0, 0, 1
    if right and top and top_right:
        return 0, -1, 1
    if left and top and top_left:
        return -1, -1, 1
    return 0, 0, 0


def repair_action(mask):
    (bottom, top, left, right, bottom_left, bottom_right, top_left, top_right,
     outer_left, outer_right, outer_bottom, outer_top) = (
        bool(mask & (1 << bit)) for bit in range(len(REPAIR))
    )
    if not (bottom or top) or not (left or right):
        return 1, 1, -2

    # Native 0x10239339 tries to move a damaged footprint before shrinking it.
    bottom_edge = bottom and bottom_left and bottom_right
    top_edge = top and top_left and top_right
    left_edge = left and top_left and bottom_left
    right_edge = right and top_right and bottom_right
    if not bottom_edge and outer_top and top_edge and left and right:
        return 0, -1, 0
    if not top_edge and outer_bottom and bottom_edge and left and right:
        return 0, 1, 0
    if not left_edge and outer_right and right_edge and bottom and top:
        return 1, 0, 0
    if not right_edge and outer_left and left_edge and bottom and top:
        return -1, 0, 0

    if not top_left and not outer_bottom and not outer_right:
        return 1, 1, -1
    if not top_right and not outer_left and not outer_bottom:
        return 0, 1, -1
    if not bottom_left and not outer_top and not outer_right:
        return 1, 0, -1
    if not outer_top and (not bottom or (not bottom_right and not outer_left)):
        return 0, 0, -1
    if not top and not outer_bottom:
        return 0, 1, -1
    if not right and not outer_left:
        return 0, 0, -1
    if not left and not outer_right:
        return 1, 0, -1
    return 0, 0, -4  # Remove the plot.


def encode(action, deltas):
    x, z, delta = action
    return (x + 1) | ((z + 1) << 2) | (deltas.index(delta) << 4)


def write_tables(image, output, growth, repair, adapters=None):
    rate = image.read(0x104ec570, 8)
    data = {
        'version': 1,
        'executable_sha256': hashlib.sha256(image.raw).hexdigest(),
        'progress_rate': struct.unpack('<d', rate)[0],
        'progress_rate_native': {'address': '0x104ec570', 'bytes': rate.hex()},
        'growth': {
            'path': 'campaign/plot-growth-decisions.bin', 'sha256': hashlib.sha256(growth).hexdigest(),
            'inputs': GROW, 'slots': GROW_SLOTS, 'count': len(growth),
            'maximum_regimes': ['at_or_below_size', 'size_plus_one', 'size_plus_two_or_more'],
        },
        'repair': {
            'path': 'campaign/plot-repair-decisions.bin', 'sha256': hashlib.sha256(repair).hexdigest(),
            'inputs': REPAIR, 'slots': REPAIR_SLOTS, 'count': len(repair),
        },
        'native_routines': {
            hex(start): image.read(start, end - start).hex()
            for start, end in [(0x102383b4, 0x10238b0d), (0x10239302, 0x1023971b)]
        },
        'scope': 'Original plot growth and repair decisions over the finite footprint predicates.',
        'method': 'source branch translation' if adapters is None else 'native comparison',
    }
    if adapters is not None:
        data['adapters'] = [hex(address) for address in sorted(adapters)]
    output.mkdir(parents=True, exist_ok=True)
    (output / 'plot-growth-decisions.bin').write_bytes(growth)
    (output / 'plot-repair-decisions.bin').write_bytes(repair)
    (output / 'plot-resize-rules.json').write_text(json.dumps(data, indent=2) + '\n')
    return data


def extract(source=ROOT / 'data/godus2_4', output=ROOT / 'game/assets/original/campaign'):
    raw = (source / 'godus.s86').read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_EXECUTABLE_SHA256:
        raise ValueError('Unsupported source executable for plot resizing')
    growth = bytes(encode(growth_action(mask, room), (0, 1, 2))
                   for room in range(3) for mask in range(256))
    repair = bytes(encode(repair_action(mask), (-2, -1, 0, -4)) for mask in range(4096))
    return write_tables(NativeImage(raw), output, growth, repair)


if __name__ == '__main__':
    data = extract()
    print('Original plot resize decisions:', data['growth']['count'], 'growth,', data['repair']['count'], 'repair')
