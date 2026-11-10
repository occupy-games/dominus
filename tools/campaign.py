#!/usr/bin/env python3
"""Recover original large maps and desktop campaign tables, with provenance."""
import csv
import hashlib
import io
import json
from pathlib import Path
import struct
try:
    from .assets import pack_entries
except ImportError:
    from assets import pack_entries

ROOT = Path(__file__).resolve().parents[1]
COUNTS = [28, 14, 9, 7, 5, 4, 3, 2, 1]
BITS = [1, 2, 3, 4, 5, 7, 9, 14, 28]


def decode_chunk(data):
    """Source loader 0x10138300; Simple9 decoder 0x10136fa0 in godus.s86.

    0x39: Simple9 packed zigzag deltas, prefix sum, alternate rows reversed.
    0x53: sparse uint16 indices then uint8 values. 0x42: raw 128 x 128.
    The unsupported 0x52 RLE branch is deliberately rejected by the original source itself.
    """
    if not data: raise ValueError('Empty chunk')
    if data[0] == 0x42:
        if len(data) != 16385: raise ValueError('Invalid raw chunk')
        return data[1:]
    if data[0] == 0x53:
        count, = struct.unpack_from('<I', data, 1)
        if len(data) != 5 + count * 3: raise ValueError('Invalid sparse chunk')
        result = bytearray(16384)
        indices = struct.unpack_from('<' + 'H' * count, data, 5)
        if len(set(indices)) != count or any(i >= 16384 for i in indices): raise ValueError('Invalid sparse indices')
        for offset, index in enumerate(indices): result[index] = data[5 + count * 2 + offset]
        return bytes(result)
    if data[0] != 0x39 or len(data) % 4 != 1: raise ValueError('Unsupported terrain chunk')
    result, value = [], 0
    for offset in range(1, len(data), 4):
        word, = struct.unpack_from('<I', data, offset)
        selector = word >> 28
        if selector > 8: raise ValueError('Unsupported Simple9 selector')
        count, bits = COUNTS[selector], BITS[selector]
        for index in range(count):
            encoded = (word >> ((count-index-1)*bits)) & ((1 << bits)-1)
            value += -(encoded+1)//2 if encoded & 1 else encoded//2
            result.append(value & 255)
        if len(result) >= 16384:
            if offset + 4 != len(data): raise ValueError('Trailing Simple9 words')
            break
    if len(result) < 16384: raise ValueError('Truncated Simple9 grid')
    result = result[:16384]
    for row in range(1, 128, 2): result[row*128:(row+1)*128] = reversed(result[row*128:(row+1)*128])
    return bytes(result)


def balance_files(data):
    count, = struct.unpack_from('<I', data)
    cursor, files = 4, {}
    for _ in range(count):
        length, = struct.unpack_from('<I', data, cursor)
        name = data[cursor+4:cursor+260].split(b'\0')[0].decode()
        if not name.startswith('BalanceFiles_') or '..' in Path(name).parts: raise ValueError('Invalid balance path')
        payload = data[cursor+260:cursor+260+length]
        if len(payload) != length: raise ValueError('Truncated balance payload')
        files[name] = payload.rstrip(b'\0').decode('utf-8', errors='replace')
        cursor += 260 + (length+3)//4*4
    if cursor != len(data): raise ValueError('Trailing balance data')
    return files


def stream_hash(name):
    """Case-sensitive Jenkins one-at-a-time name hash in the stream packs."""
    value = 0
    for char in name.encode('ascii'):
        value = (value + char) & 0xffffffff
        value = (value + (value << 10)) & 0xffffffff
        value ^= value >> 6
    value = (value + (value << 3)) & 0xffffffff
    value ^= value >> 11
    return (value + (value << 15)) & 0xffffffff


def packed_map(path):
    body = path.read_bytes()
    records = {int(entry['key'], 16): entry for entry in pack_entries(path)}
    fields, evidence = {}, {}
    for kind in ['terrain', 'tree', 'rock', 'gem', 'plotrot']:
        grid = bytearray(1024 * 1024)
        for z in range(8):
            for x in range(8):
                name = f'{kind}_{x:02x}{z:02x}'
                entry = records.get(stream_hash(name))
                if entry is None or entry['size'] == 0:
                    continue  # The stream format omits empty chunks.
                payload = body[entry['offset']:entry['offset'] + entry['size']]
                chunk = decode_chunk(payload)
                for row in range(128):
                    start = (z * 128 + row) * 1024 + x * 128
                    grid[start:start + 128] = chunk[row * 128:(row + 1) * 128]
                evidence[name] = {**entry, 'sha256': hashlib.sha256(payload).hexdigest()}
        fields[kind] = bytes(grid)
    start_record = records.get(stream_hash('p1Start'))
    starts = body[start_record['offset']:start_record['offset'] + start_record['size']] if start_record else b'\0' * 4
    return fields, starts, evidence, start_record


def player_starts(raw):
    if len(raw) < 4:
        raise ValueError('Truncated player starts')
    count, = struct.unpack_from('<I', raw)
    if len(raw) != 4 + count * 4:
        raise ValueError('Invalid player starts')
    indices = struct.unpack_from('<' + 'I' * count, raw, 4)
    if any(index >= 1024 * 1024 for index in indices):
        raise ValueError('Player start outside map')
    return [{'x': index % 1024, 'z': index // 1024} for index in indices]


def extract_maps(source, output):
    homeworld = extract(source, output)
    target = output / 'campaign'
    homeworld['id'] = 'homeworld'
    homeworld['family'] = 'Homeworld'
    (target / 'homeworld.json').write_text(json.dumps(homeworld, separators=(',', ':')))
    catalog = []
    packs = sorted((source / 'stream').glob('*.pack'), key=lambda path: (0 if path.stem.startswith('Homeworld') else 1 if path.stem.startswith('Hubworld') else 2, path.stem.lower()))
    for path in packs:
        name = path.stem
        if not (name.startswith(('Homeworld', 'Hubworld')) or name.lower().startswith('eventmap')):
            continue
        if name == 'HomeworldBlankWorld':
            continue
        fields, raw_starts, evidence, start_record = packed_map(path)
        terrain = fields['terrain']
        # Small event/tutorial fragments are not campaign-sized maps.
        land_cells = sum(height > 19 for height in terrain)
        if sum(key.startswith('terrain_') for key in evidence) < 50:
            continue
        family = 'Homeworld' if name.startswith('Homeworld') else 'Hubworld' if name.startswith('Hubworld') else 'Event maps'
        starts = player_starts(raw_starts)
        start_source = f'{path.relative_to(source).as_posix()}#p1Start'
        notes = []
        # The authored loose Homeworld7 start record survives in the supplied
        # editor directory; the packed revision has an empty p1Start. Never
        # generate followers for maps with no supplied start record.
        if name == 'Homeworld7' and not starts:
            loose = source / 'stream/homeworld7/p1start'
            if loose.is_file():
                raw_starts = loose.read_bytes()
                starts = player_starts(raw_starts)
                start_source = loose.relative_to(source).as_posix()
                notes.append('Packed terrain with the supplied loose player-start record; the packed p1Start is empty.')
        reason = ''
        if family == 'Event maps':
            reason = 'Original event rules and waterline are not yet supported.'
        elif not starts:
            reason = 'Original Lua-spawned opening and story integration are incomplete.' if name=='Homeworld6' else 'No player starting positions in the supplied map.'
        elif any(terrain[start['z'] * 1024 + start['x']] <= 19 for start in starts):
            reason = 'Player starting positions are below the supported waterline.'
        map_id = name.lower()
        entry = {'id': map_id, 'name': name, 'family': family, 'width': 1024,
                 'available': not reason, 'unavailable_reason': reason,
                 'land_cells': land_cells, 'height_sha256': hashlib.sha256(terrain).hexdigest(),
                 'pack_source': path.relative_to(source).as_posix(), 'pack_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                 'notes': notes}
        if not reason:
            entry['definition'] = f'campaign/{map_id}.json'
            if name != 'Homeworld':
                height_name = f'campaign/{map_id}-heights.bin'
                (output / height_name).write_bytes(terrain)
                objects = {kind: [{'x': index % 1024, 'z': index // 1024, 'value': value}
                                  for index, value in enumerate(grid) if value]
                           for kind, grid in fields.items() if kind != 'terrain'}
                manifest = {'id': map_id, 'name': name, 'family': family, 'width': 1024,
                            'sea_level': 19, 'layer_height': 0.3, 'height_data': height_name,
                            'height_sha256': entry['height_sha256'], 'followers': starts, 'objects': objects,
                            'balance_definition': 'campaign/homeworld.json', 'sources': evidence,
                            'pack_source': entry['pack_source'], 'pack_sha256': entry['pack_sha256'],
                            'start_source': start_source, 'start_sha256': hashlib.sha256(raw_starts).hexdigest(),
                            'start_record': start_record, 'notes': notes,
                            'scenario_rules': 'Shared supplied desktop opening rules registered to this map start; original map-specific campaigns are not recovered.'}
                (target / f'{map_id}.json').write_text(json.dumps(manifest, separators=(',', ':')))
        catalog.append(entry)
    compact_runtime_maps(output, catalog)
    (target / 'maps.json').write_text(json.dumps({'version': 1, 'maps': catalog}, indent=2) + '\n')
    print(f"Large source maps: {len(catalog)} found, {sum(entry['available'] for entry in catalog)} playable starts")
    return catalog


def compact_runtime_maps(output, catalog):
    """Runtime needs byte fields, not a million JSON plot-rotation objects."""
    target = output / 'campaign'
    base = json.loads((target / 'homeworld.json').read_text())
    opening = {key: base[key] for key in ['tables', 'configuration', 'balance_source', 'balance_sha256']}
    (target / 'opening-rules.json').write_text(json.dumps(opening, separators=(',', ':')))
    del base
    for entry in catalog:
        if not entry['available']: continue
        name = entry['id']
        full = json.loads((target / f'{name}.json').read_text())
        fields = {}
        for kind in ['tree', 'rock']:
            raw = bytearray(1024 * 1024)
            for cell in full['objects'][kind]: raw[cell['z'] * 1024 + cell['x']] = cell['value']
            relative = f'campaign/{name}-{kind}.bin'
            (output / relative).write_bytes(raw)
            fields[kind] = {'path': relative, 'sha256': hashlib.sha256(raw).hexdigest()}
        runtime = {key: value for key, value in full.items() if key not in ['objects', 'tables', 'configuration']}
        runtime['balance_definition'] = 'campaign/opening-rules.json'
        runtime['fields'] = fields
        relative = f'campaign/{name}-runtime.json'
        (output / relative).write_text(json.dumps(runtime, separators=(',', ':')))
        entry['definition'] = relative


def extract(source, output):
    target = output / 'campaign'
    target.mkdir(exist_ok=True)
    folder = source / 'stream/Homeworld'
    hashes, grids = {}, {}
    for kind in ['terrain', 'tree', 'rock', 'gem', 'plotrot']:
        grid = bytearray(1024*1024)
        for path in sorted(folder.glob(kind + '_*')):
            body = path.read_bytes()
            chunk = decode_chunk(body)
            x, y = int(path.name[-4:-2], 16), int(path.name[-2:], 16)
            for row in range(128):
                start = (y*128+row)*1024+x*128
                grid[start:start+128] = chunk[row*128:(row+1)*128]
            hashes[path.relative_to(source).as_posix()] = hashlib.sha256(body).hexdigest()
        if kind == 'terrain':
            (target / 'homeworld-heights.bin').write_bytes(grid)
        else:
            grids[kind] = [{'x': index%1024, 'z': index//1024, 'value': value} for index, value in enumerate(grid) if value]
    starts = (folder / 'p1Start').read_bytes()
    count, = struct.unpack_from('<I', starts)
    if len(starts) != 4+count*4: raise ValueError('Invalid player starts')
    followers = [{'x': index%1024, 'z': index//1024} for index in struct.unpack_from('<'+'I'*count, starts, 4)]
    balance = source / 'initialBalance.dat'
    files = balance_files(balance.read_bytes())
    tables = {}
    for name, text in files.items():
        if '/desktop/initialworldsetup/' in name or '/desktop/balance/' in name or '/desktop/gui/' in name or '/desktop/assets/' in name:
            tables[name.split('/desktop/', 1)[1]] = list(csv.reader(io.StringIO(text)))
    configuration = {row[0]: row[1] for row in csv.reader(io.StringIO(files['BalanceFiles_b1.6/config.csv'])) if len(row)>1 and row[0] and not row[0].startswith('#')}
    manifest = {'name': 'Homeworld', 'width': 1024, 'sea_level': 19, 'layer_height': 0.3,
        'height_data': 'campaign/homeworld-heights.bin', 'height_sha256': hashlib.sha256((target/'homeworld-heights.bin').read_bytes()).hexdigest(),
        'followers': followers, 'objects': grids, 'tables': tables, 'configuration': configuration,
        'sources': hashes, 'start_source': 'stream/Homeworld/p1Start', 'start_sha256': hashlib.sha256(starts).hexdigest(),
        'balance_source': 'initialBalance.dat', 'balance_sha256': hashlib.sha256(balance.read_bytes()).hexdigest(),
        'decoder_evidence': {'loader': 'godus.s86:0x10138300', 'simple9': 'godus.s86:0x10136fa0', 'sparse': 'godus.s86:0x101384ba'}}
    (target / 'homeworld.json').write_text(json.dumps(manifest, separators=(',', ':')))
    print(f"Original Homeworld: 1024 x 1024, {count} starts, {len(grids['tree'])} tree cells, {len(grids['rock'])} rock cells")
    return manifest


if __name__ == '__main__': extract_maps(ROOT/'data/godus2_4', ROOT/'game/assets/original')
