"""Recover authored the original source distance-sprite rectangles without creating new art."""
import hashlib
import json
import struct
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def decode(raw):
    variants, kinds, frame_width, frame_height = struct.unpack_from('<4I', raw)
    if len(raw) != 16 + variants * kinds * 12 or variants != 5 or kinds != 12:
        raise ValueError('Unsupported original tree-imposter metadata')
    entries = []
    for index in range(variants * kinds):
        width, height, trim_x, trim_y, x, y = struct.unpack_from('<6H', raw, 16 + index * 12)
        entries.append({'rect': [x, y, width, height], 'trim': [trim_x, trim_y]})
    return {'variants': variants, 'kinds': kinds, 'frame': [frame_width, frame_height], 'entries': entries}

def main():
    source = ROOT / 'data/godus2_4/sprites/pack_treeImposters_v2.png.dat'
    atlas = ROOT / 'data/godus2_4/sprites/pack_treeImposters_v2.png'
    raw = source.read_bytes()
    result = decode(raw)
    result.update({'source': str(source.relative_to(ROOT / 'data/godus2_4')),
                   'source_sha256': hashlib.sha256(raw).hexdigest(),
                   'atlas': 'res://assets/extracted/sprites/pack_treeImposters_v2.png',
                   'atlas_sha256': hashlib.sha256(atlas.read_bytes()).hexdigest(),
                   'shader_source': 'shaders.group.bin:shdrImpostersWithDiscard',
                   'mapping_note': 'Whole loc1/loc2/loc3 meshes match palm/deciduous/alpine source atlas groups 0/2/10 by variant; original field variant mapping remains unresolved.'})
    target = ROOT / 'game/assets/original/tree_imposters.json'
    target.write_text(json.dumps(result, indent=2) + '\n')
if __name__ == '__main__': main()
