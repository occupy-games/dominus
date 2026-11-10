"""Recover authored rock types, dimensions and model dispatch from the original source.

Packed rock bytes are generation inputs, not the authored CSV object identity.
This decoder handles the latter independently and retains the native evidence.
"""
import csv
import hashlib
import io
import struct

from tools.current_cards import rows


def native_rocks(raw):
    pe = struct.unpack_from('<I', raw, 60)[0]
    if raw[pe:pe+4] != b'PE\0\0': raise ValueError('Not the supplied PE executable')
    optional = pe+24
    base = struct.unpack_from('<I', raw, optional+28)[0]
    sections = []
    for i in range(struct.unpack_from('<H', raw, pe+6)[0]):
        entry = optional+struct.unpack_from('<H', raw, pe+20)[0]+i*40
        _, virtual, length, start = struct.unpack_from('<IIII', raw, entry+8)
        sections.append((base+virtual, start, length))

    def offset(address):
        return next(start+address-virtual for virtual, start, length in sections if virtual <= address < virtual+length)

    def block(start, end): return raw[offset(start):offset(end)]

    # The loader's name table is indexed from zero. Entries 0..4 select biome
    # trees, 5..9 add 10, and entries >=10 add 15 (rock1 is type 25, not 20).
    enumeration = block(0x1025ef6d, 0x1025ef80)
    if enumeration.hex() != '83fb0a730583c30aeb0383c30f899d2cfeffff':
        raise ValueError('Unknown authored map-object enumeration')
    names = {}
    for index in range(10, 17):
        slot = 0x110d64c0+index*4
        store = b'\xa3'+struct.pack('<I', slot)
        start, end = offset(0x1025eab4), offset(0x1025edac)
        positions = [p for p in range(start, end) if raw[p:p+5] == store]
        if len(positions) != 1: raise ValueError('Ambiguous map-object name slot')
        stop = positions[0]+5
        name = 'rock'+str(index-9)
        name_start = raw.index(name.encode()+b'\0')
        pointer = next(virtual+name_start-start for virtual, start, length in sections if start <= name_start < start+length)
        needle = b'\x68'+struct.pack('<I', pointer)
        matches = [p for p in range(start, stop) if raw[p:p+5] == needle]
        if len(matches) != 1: raise ValueError('Ambiguous original rock name')
        begin = matches[0]
        code = raw[begin:stop]
        if len(code) not in [43, 49, 54] or code[5:11] != bytes.fromhex('8d8d60feffff'):
            raise ValueError('Unknown map-object name registration')
        names[name] = {'type': index+15, 'slot': hex(slot), 'registration_bytes': code.hex()}

    # Both world/theme dispatch branches use the same seven original boulders.
    dispatch = {}
    for kind in range(20, 27):
        targets = [struct.unpack_from('<I', raw, offset(table)+(kind-1)*4)[0]
                   for table in [0x10155e40, 0x10155ea8]]
        if targets[0] != targets[1]: raise ValueError('Conflicting original rock model dispatch')
        code = block(targets[0], targets[0]+13)
        if code[0] != 0xb9 or code[5:7] != b'\x8d\x86' or code[11] != 0xeb:
            raise ValueError('Unknown original rock model case')
        model, shadow = struct.unpack_from('<I', code, 1)[0], struct.unpack_from('<I', code, 7)[0]
        if model != 347+kind-20 or shadow != model+7:
            raise ValueError('Unknown original boulder model indices')
        dispatch[str(kind)] = {'model_enum': model, 'shadow_enum': shadow,
                               'routine': hex(targets[0]), 'bytes': code.hex()}
    return {'executable_sha256': hashlib.sha256(raw).hexdigest(), 'names': names, 'models': dispatch,
            'enumeration': {'routine': '0x1025ef6d', 'bytes': enumeration.hex()},
            'position': {'routine': '0x1025f11c', 'bytes': block(0x1025f11c, 0x1025f161).hex()},
            'footprint': {'routine': '0x10156ae0', 'bytes': block(0x10156ae0, 0x10156c47).hex()}}


def authored_rocks(files, raw, model_csv, scope):
    native = native_rocks(raw)
    table_path = scope+'/initialmapobjects.csv'
    values_path = 'assets/map_object_values.csv'
    values = {int(row[0]): dict(zip(rows(files, values_path)[0], row))
              for row in rows(files, values_path)[1:] if row and row[0].isdigit()}
    models = {int(row[' EnumId']): row['FileName'] for row in csv.DictReader(io.StringIO(model_csv.decode('utf-8-sig')))}
    entries, unsupported = [], []
    for line, row in enumerate(rows(files, table_path)[1:], 2):
        if not row or not row[0].startswith('rock'): continue
        name = row[0]
        kind = native['names'].get(name, {}).get('type')
        if kind not in values or str(kind) not in native['models']:
            unsupported.append({'line': line, 'type': name, 'reason': 'Original values or model dispatch unavailable'})
            continue
        value = values[kind]
        x, z = int(float(row[1])), int(float(row[2]))
        size_x, size_z = int(value['xSize']), int(value['ySize'])
        dispatch = native['models'][str(kind)]
        entries.append({'source_line': line, 'source_type': name, 'type': kind,
                        'origin_x': x, 'origin_z': z, 'size_x': size_x, 'size_z': size_z,
                        'x': x+size_x*.5, 'z': z+size_z*.5,
                        'rotation': float(row[3] or 0), 'belief': int(value['belief']),
                        'model_name': models[dispatch['model_enum']],
                        'shadow_name': models[dispatch['shadow_enum']]})
    return {'entries': entries, 'unsupported': unsupported, 'native': native,
            'table': table_path, 'table_sha256': hashlib.sha256(files[table_path]).hexdigest(),
            'values_table': values_path, 'values_sha256': hashlib.sha256(files[values_path]).hexdigest(),
            'models_table': 'GeneratedDataFiles/Models.csv', 'models_sha256': hashlib.sha256(model_csv).hexdigest()}
