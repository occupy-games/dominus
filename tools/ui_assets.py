#!/usr/bin/env python3
"""Read exact Scaleform bitmap atlas regions and retain source provenance."""
import hashlib
import json
from pathlib import Path
import struct

try:
    from .original_assets import png
except ImportError:
    from original_assets import png

ROOT = Path(__file__).resolve().parents[1]
NATIVE_REGIONS = {
    'sculpt_circle': [173,755,74,74], 'sculpt_hand': [84,1037,62,68],
    'info_circle': [423,2,85,85],
    'happiness_gradient': [72,3,11,165], 'happiness_player': [261,1219,49,45],
    'happiness_astari': [3,1117,47,40],
}


def tags(data):
    if data[:3] not in (b'GFX', b'FWS'): raise ValueError('Unsupported Scaleform stream')
    cursor = 8 + (5+4*(data[8] >> 3)+7)//8 + 4
    while cursor+2 <= len(data):
        header, = struct.unpack_from('<H', data, cursor)
        cursor += 2
        kind, length = header >> 6, header & 63
        if length == 63:
            length, = struct.unpack_from('<I', data, cursor)
            cursor += 4
        body = data[cursor:cursor+length]
        if len(body) != length: raise ValueError('Truncated Scaleform tag')
        cursor += length
        yield kind, body
        if kind == 0: return


def extract(source, output):
    folder = source/'Scaleform_Compiled'
    raw = (folder/'Textures.gfx').read_bytes()
    images, regions, names = {}, {}, {}
    for kind, data in tags(raw):
        if kind == 1009:
            key, _, _, width, height = struct.unpack_from('<5H', data)
            cursor = 10
            export = data[cursor+1:cursor+1+data[cursor]].decode()
            cursor += data[cursor]+1
            filename = data[cursor+1:cursor+1+data[cursor]].decode()
            if Path(filename).name != filename: raise ValueError('External image path')
            images[key] = {'source': 'Scaleform_Compiled/'+filename, 'size': [width,height], 'file': filename, 'name': export}
        elif kind == 1008:
            key, atlas, x0, y0, x1, y1 = struct.unpack('<6H', data)
            regions[key] = {'atlas': atlas, 'rect': [x0,y0,x1-x0,y1-y0]}
        elif kind == 76:
            count, = struct.unpack_from('<H', data)
            cursor = 2
            for _ in range(count):
                key, = struct.unpack_from('<H', data, cursor)
                end = data.index(0,cursor+2)
                names[key] = data[cursor+2:end].decode()
                cursor = end+1
    target = output/'ui'
    target.mkdir(exist_ok=True)
    for image in images.values():
        body = (source/image['source']).read_bytes()
        image['sha256'] = hashlib.sha256(body).hexdigest()
        if body[:4] != b'DDS ' or struct.unpack_from('<I',body,4)[0] != 124: raise ValueError('Unsupported DDS header')
        height, width, pitch = struct.unpack_from('<3I',body,12)
        bits, = struct.unpack_from('<I',body,88)
        masks = struct.unpack_from('<4I',body,92)
        if bits != 32 or pitch != width*4 or len(body) != 128+pitch*height: raise ValueError('Unsupported DDS pixels')
        if any(mask.bit_count()!=8 for mask in masks): raise ValueError('Unsupported DDS channel masks')
        shifts = [(mask & -mask).bit_length()-1 for mask in masks]
        pixels = bytearray()
        for value, in struct.iter_unpack('<I',body[128:]):
            pixels.extend((value>>shift)&255 for shift in shifts)
        png(target/image['name'],width,height,4,pixels)
    result = {'source': 'Scaleform_Compiled/Textures.gfx', 'sha256': hashlib.sha256(raw).hexdigest(),
              'images': images, 'regions': {names[k]:v for k,v in regions.items() if k in names},
              'native_atlas': {'source': 'sprites/Atlas_AutoGUI.png',
                               'sha256': hashlib.sha256((source/'sprites/Atlas_AutoGUI.png').read_bytes()).hexdigest(),
                               'regions': NATIVE_REGIONS}}
    (target/'catalog.json').write_text(json.dumps(result,indent=2))
    print(f"Original Scaleform UI: {len(result['regions'])} named bitmap regions, {len(images)} source atlases")
    return result


if __name__ == '__main__': extract(ROOT/'data/godus2_4',ROOT/'game/assets/original')
