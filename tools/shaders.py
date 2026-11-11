"""Extract original Marmalade GLSL text with exact group/member provenance."""
import csv
import hashlib
import json
from pathlib import Path
import struct

from tools.original_assets import iw_hash, resource_group
from tools.native_scenery_oracle import NativeImage

ROOT = Path(__file__).resolve().parents[1]


def decode_shader(payload):
    cursor, result = 0, {}
    for stage in ('vertex', 'fragment'):
        if cursor + 4 > len(payload): raise ValueError('Truncated shader length')
        length, = struct.unpack_from('<I', payload, cursor)
        cursor += 4
        if length > len(payload) - cursor - 1 or payload[cursor + length] != 0:
            raise ValueError('Invalid shader text extent/terminator')
        result[stage] = payload[cursor:cursor + length].decode('utf-8')
        cursor += length + 1
    result['parameters'] = payload[cursor:]
    if len(result['parameters']) < 4: raise ValueError('Missing shader parameters')
    result['parameter_count'], = struct.unpack_from('<I', result['parameters'])
    return result


def terrain_beautify_texture(source):
    image = NativeImage((source / 'godus.s86').read_bytes())
    binding_address = 0x101a2fd7
    record_address = 0x105e3fb0
    binding = image.read(binding_address, 14)
    name, _, _, _, _, _, texture = struct.unpack('<7I', image.read(record_address, 28))
    relative_call, = struct.unpack_from('<i', binding, 10)
    if (binding[:10] != b'\x8b\x15' + struct.pack('<I', texture) + b'\x6a\x03\x52\xe8'
            or binding_address + len(binding) + relative_call != 0x1017b2f0):
        raise ValueError('Unexpected terrain sampler 3 binding')
    path = image.read(name, 64).split(b'\0', 1)[0].decode()
    if path != 'sprites/GemDiffuse.tga':
        raise ValueError('Unexpected terrain sampler 3 texture')
    return {'source': path, 'sha256': hashlib.sha256((source / path).read_bytes()).hexdigest(), 'sampler': 3,
            'binding': hex(binding_address), 'texture_record': hex(record_address)}


def extract(source=ROOT / 'data/godus2_4', output=ROOT / 'game/assets/original/shaders'):
    names_file = source / 'GeneratedDataFiles/Shaders.csv'
    names = {iw_hash(row[0]): row[0] for row in csv.reader(names_file.read_text().splitlines()) if row and row[0].startswith('shdr')}
    records = []
    for group in ['shaders.group.bin', 'hiend_high_shaders.group.bin', 'spriteshaders.group.bin']:
        raw = (source / group).read_bytes()
        for kind, members in resource_group(raw).items():
            for resource_id, payload in members.items():
                parsed = decode_shader(payload)
                name = names.get(resource_id, f'{resource_id:08x}')
                folder = output / group.removesuffix('.group.bin')
                folder.mkdir(parents=True, exist_ok=True)
                entry = {'name': name, 'resource_id': resource_id, 'resource_type': kind,
                         'source': group, 'group_sha256': hashlib.sha256(raw).hexdigest(),
                         'member_sha256': hashlib.sha256(payload).hexdigest(), 'parameter_count': parsed['parameter_count']}
                for stage in ['vertex', 'fragment', 'parameters']:
                    path = folder / (name + ('.' + stage + '.txt' if stage != 'parameters' else '.parameters.bin'))
                    value = parsed[stage].encode('utf-8') if stage != 'parameters' else parsed[stage]
                    path.write_bytes(value)
                    entry[stage] = {'path': path.relative_to(output).as_posix(), 'sha256': hashlib.sha256(value).hexdigest()}
                records.append(entry)
    crop = next(record for record in records if record['source'] == 'shaders.group.bin' and record['name'] == 'shdrCropsGrain')
    terrain = next(record for record in records if record['source'] == 'hiend_high_shaders.group.bin' and record['name'] == 'shdrTerrain50')
    result = {'version': 1, 'name_source': 'GeneratedDataFiles/Shaders.csv',
              'name_source_sha256': hashlib.sha256(names_file.read_bytes()).hexdigest(), 'shaders': records,
              'runtime_ports': [{'path': 'res://presentation/world/godus_crops.gdshader',
                                'source': crop['source'], 'resource_id': crop['resource_id'], 'member_sha256': crop['member_sha256'],
                                'scope': 'Healthy crop tint mask, original grain/pumpkin colors, ripeness curve and direct diffuse/ambient lighting. Blight, beautify, fog and source vertex deformation remain unported.'},
                               {'path': 'res://presentation/world/source_land.gdshader', 'source': terrain['source'],
                                'resource_id': terrain['resource_id'], 'member_sha256': terrain['member_sha256'],
                                'textures': [terrain_beautify_texture(source)],
                                'scope': 'Beautify mask, moving UVs, normal weighting, saturation and highlight over the smooth campaign palette.'}]}
    (output / 'catalog.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    result = extract()
    print(f"Original shader text: {len(result['shaders'])} records with source parameters retained")
