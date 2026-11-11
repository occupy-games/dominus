"""Recover the original standalone and attached settlement stat-row selectors."""
import json
import re
import struct

from tools.current_cards import ROOT, decode_archive, rows
from tools.house_selection import extract as house_selection
from tools.house_values import native_fields, resolve
from tools.native_scenery_oracle import NativeImage


def extract():
    source = ROOT / 'data/godus2_4'
    raw = (source / 'godus.s86').read_bytes()
    image = NativeImage(raw)
    selection = house_selection()
    fields = native_fields(raw)
    archive = decode_archive((source / selection['source']).read_bytes())
    records = resolve(rows(archive, selection['table']), fields)

    def result_at(address):
        code = image.read(address, 6)
        if code[:2] == b'\x33\xc0':
            return 0
        if code[0] == 0xb8 and code[5] == 0x5d:
            return struct.unpack_from('<I', code, 1)[0]
        raise ValueError('Unknown attached settlement kind branch')

    kind_slots = [result_at(address) for address in struct.unpack('<10I', image.read(0x1013cadc, 40))]
    default_slot = result_at(0x1013cad2)
    initializer = image.read(0x10407a70, 0x9d)
    names = [image.read(struct.unpack('<I', match[1])[0], 64).split(b'\0')[0].decode()
             for match in re.finditer(rb'\x68(.{4})\x8d\x4d\xfc', initializer, re.S)]
    if len(names) != 5:
        raise ValueError('Unknown attached settlement model initializer')
    templates = []
    for name in names:
        matches = [row['index'] for row in selection['rows']
                   if records[row['id']]['raw']['Model Name For Tex'] == name]
        if len(matches) != 1:
            raise ValueError(f'Expected one original settlement row for {name}')
        templates.append(matches[0])
    templates.append(-1)  # The original source initializer only populates five slots.

    getter = image.read(0x100b6750, 0x82)
    value_names = {row['offset']: name for name, row in fields['fields'].items()}
    overrides = []
    for match in re.finditer(rb'\xd9\x86(.{4})(?:(?!\xd9\x86).)*?\xd9\x98(.{4})', getter, re.S):
        source_offset, target_address = struct.unpack('<II', b''.join(match.groups()))
        overrides.append(dict(name=value_names[target_address - 0x10bc4670], offset=source_offset))
    if len(overrides) != 4 or image.read(0x10026cf3, 6) != bytes.fromhex('d94508d9596c'):
        raise ValueError('Unknown attached house stat override writes')
    overrides.append(dict(name=value_names[0x6c], offset=0x12c))
    return dict(
        version=1, executable_sha256=selection['executable_sha256'],
        source_sha256=selection['source_sha256'], table_sha256=selection['table_sha256'],
        rules=dict(kind_slots=kind_slots, default_slot=default_slot, settlement_rows=templates,
                   models=names, overrides=overrides),
        native_routines={hex(start): image.read(start, end - start).hex() for start, end in [
            (0x100b6750, 0x100b67d2), (0x10026cf0, 0x10026cfd),
            (0x1013caa0, 0x1013cb04), (0x10407a70, 0x10407b0d),
            (0x10120ec2, 0x10120f0e),
        ]},
    )


if __name__ == '__main__':
    path = ROOT / 'game/assets/original/campaign/house-base-stats.json'
    path.write_text(json.dumps(extract(), indent=2) + '\n')
    print('Recovered original standalone and settlement stat-row selectors')
