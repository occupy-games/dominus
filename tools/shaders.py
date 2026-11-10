"""Extract original Marmalade GLSL text with exact group/member provenance."""
import csv
import hashlib
import json
from pathlib import Path
import struct

from tools.original_assets import iw_hash, resource_group

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
    result = {'version': 1, 'name_source': 'GeneratedDataFiles/Shaders.csv',
              'name_source_sha256': hashlib.sha256(names_file.read_bytes()).hexdigest(), 'shaders': records,
              'runtime_ports': [{'path': 'res://presentation/world/godus_crops.gdshader',
                                'source': crop['source'], 'resource_id': crop['resource_id'], 'member_sha256': crop['member_sha256'],
                                'scope': 'Healthy crop tint mask, original grain/pumpkin colors, ripeness curve and direct diffuse/ambient lighting. Blight, beautify, fog and source vertex deformation remain unported.'}]}
    (output / 'catalog.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    result = extract()
    print(f"Original shader text: {len(result['shaders'])} records with source parameters retained")
