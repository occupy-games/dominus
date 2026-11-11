"""Recover house stat modifiers from the original Environment Buffs table."""
import hashlib
import json
import struct

from tools.current_cards import ROOT, decode_archive, rows
from tools.house_selection import enumeration
from tools.house_values import native_fields
from tools.native_scenery_oracle import NativeImage


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def extract():
    source = ROOT / 'data/godus2_4'
    raw = (source / 'godus.s86').read_bytes()
    archive = (source / 'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    image = NativeImage(raw)
    name = 'balance/environmentbuffs.csv'
    registered_name = image.read(0x104a7890, 64).split(b'\0')[0].decode().lower()
    if registered_name != name:
        raise ValueError('Unexpected environment table registration')
    kinds = enumeration(image, 0x1039dea0, 0x1039df20, 0x107ce194, 4)
    query_tag = image.read(0x100b74ad, 2)
    if query_tag[0] != 0x6a:
        raise ValueError('Unexpected original house surroundings query')
    surroundings = dict(
        query_tag=query_tag[1], query_flags=[0, 0, 0, 0, 1, 1],
        beauty_threshold=struct.unpack('<f', image.read(0x105b2d40, 4))[0],
        area_padding=struct.unpack('<d', image.read(0x104a0d00, 8))[0],
    )
    fields = native_fields(raw)['fields']
    table = rows(files, name)
    records = []
    for raw_row in table[1:]:
        if not raw_row or not raw_row[0] or raw_row[0].startswith('#'):
            continue
        row = dict(zip(table[0], raw_row))
        scope, table_name, column, operation = [item.strip() for item in row['Effect'].split(',')]
        field = column.casefold()
        if (scope.casefold(), table_name) != ('table', 'House Values') or field not in fields:
            raise ValueError('Unexpected environment stat binding')
        prefix = operation[:1]
        value = f32(float(operation[1:] if prefix in 'xmp+' else operation))
        records.append(dict(
            kind=kinds[row['Buff Type']], unlock=row['Unlock'], field=field,
            index=fields[field]['offset'] // 4, operation=int(prefix in 'xm'),
            value=value, cap=f32(float(row['Cap'])),
            **{flag: int(row.get(flag, 0)) for flag in ['abode', 'monastery', 'farm', 'mine']},
        ))
    return dict(
        version=1, executable_sha256=hashlib.sha256(raw).hexdigest(),
        source_sha256=hashlib.sha256(archive).hexdigest(),
        table=name, table_sha256=hashlib.sha256(files[name]).hexdigest(),
        kinds=kinds, records=records, surroundings=surroundings,
        native_routines={hex(start): image.read(start, end - start).hex() for start, end in [
            (0x10032f75, 0x10033056), (0x1039dea0, 0x1039df20),
            (0x100b7210, 0x100b729f), (0x100b50f0, 0x100b52e0), (0x100b7744, 0x100b78e6),
        ]},
        surroundings_routines={hex(start): image.read(start, end - start).hex() for start, end in [
            (0x100b7460, 0x100b7536), (0x100b7900, 0x100b79fb), (0x10153dd0, 0x10153dff),
            (0x100444c0, 0x10044663), (0x10044670, 0x1004470a),
        ]},
        field_scale=dict(
            encode=struct.unpack('<d', image.read(0x104acff0, 8))[0],
            decode=struct.unpack('<d', image.read(0x104bd430, 8))[0],
        ),
        field_routines={hex(start): image.read(start, end - start).hex() for start, end in [
            (0x10092070, 0x100920e5), (0x100cf4b0, 0x100cf5ae),
            (0x100cfc60, 0x100cfd0d), (0x100cfd10, 0x100cfe21),
            (0x100cfe30, 0x100cff32),
        ]},
    )


if __name__ == '__main__':
    result = extract()
    path = ROOT / 'game/assets/original/campaign/house-environment.json'
    path.write_text(json.dumps(result, indent=2) + '\n')
    print('Original environment buffs:', len(result['records']))
