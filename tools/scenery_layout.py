"""Recover original Homeworld6 placements with source provenance.

Setup translates the source placement kernel to plain data. The offline
native oracle can independently produce the same records for comparison.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import struct

from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage, SOURCE_EXECUTABLE_SHA256
from tools.original_assets import iw_hash

ROOT = Path(__file__).resolve().parents[1]
RECORD = struct.Struct('<IffffIBBH')
DIRECTORY = ROOT / 'game/assets/original/campaign'
MAP_WIDTH = 1024
FIELDS = ('terrain', 'tree', 'rock')


def float32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def coordinate_hash(coordinate, salt):
    # 0x10276500 hashes the two float32 coordinates followed by the uint32 salt.
    value = 0
    for byte in coordinate + struct.pack('<I', salt):
        value = ((value + byte) * 0x401) & 0xffffffff
        value ^= value >> 6
    value = (value * 9) & 0xffffffff
    return ((value ^ (value >> 11)) * 0x8001) & 0xffff


def terrain_step(terrain, x, z):
    # 0x1025b8f0 uses the nearest corner outside the central diamond.
    # Inside, its median omits the diagonally opposite corner.
    ix, iz = int(x), int(z)
    if not (0 <= ix < MAP_WIDTH - 1 and 0 <= iz < MAP_WIDTH - 1):
        return 0
    fx, fz = float32(x - ix), float32(z - iz)
    rx, rz = float32(1 - fx), float32(1 - fz)
    index = iz * MAP_WIDTH + ix
    a, b = terrain[index:index + 2]
    c, d = terrain[index + MAP_WIDTH:index + MAP_WIDTH + 2]
    if fx + fz < .5:
        return a
    if fx + rz < .5:
        return c
    if rx + fz < .5:
        return b
    if rx + rz < .5:
        return d
    if fx < .5:
        corners = (a, b, c) if fz < .5 else (c, a, d)
    else:
        corners = (b, a, d) if fz < .5 else (d, b, c)
    return sum(corners) - min(corners) - max(corners)


def footprint(x, z, width, depth):
    return [(z + dz) * MAP_WIDTH + x + dx for dz in range(depth) for dx in range(width)]


def generate_records(image, fields, types, configuration, authored_rows):
    terrain, tree, rock = (fields[name] for name in FIELDS)
    dimensions = [(types[str(kind)]['size_x'], types[str(kind)]['size_z']) for kind in range(27)]
    if any(size != (1, 1) for size in dimensions[:20]):
        raise ValueError('Unsupported Homeworld6 tree footprint')

    def constant(address, encoding='<f'):
        return struct.unpack(encoding, image.read(address, struct.calcsize(encoding)))[0]

    offset_min = constant(0x104f06f0)
    offset_range = float32(constant(0x104a3310) - offset_min)
    height_scale = constant(0x104a0c78, '<d')
    sea_height = constant(0x104ad010)
    rock_minimum = constant(0x104acfb8)
    rock_rotation = constant(0x104a0d24)
    tree_rotation = constant(0x104db5f8)
    fraction_scale = constant(0x104aae48, '<d')
    midland = float32(float(configuration['loc2Start']))
    highland = float32(float(configuration['loc3Start']))
    occupied = set()
    records = []

    def place(root_x, root_z, x, z, height, rotation, kind, cells, authored=False):
        if occupied.intersection(cells):
            raise ValueError('Overlapping original scenery placements')
        occupied.update(cells)
        records.append({'root_x': root_x, 'root_z': root_z, 'x': x, 'z': z, 'height': height,
                        'rotation': rotation, 'type': kind, 'cells': cells, 'authored': authored})

    # 0x1025f770 truncates the authored origins before the constructor applies
    # the half-footprint offset. Homeworld6 supplies these six named types.
    authored_types = {'rock1': 25, **{f'godseed{index}': 14 + index for index in range(1, 6)}}
    for row in authored_rows:
        if not row or not row[0]:
            continue
        if row[0] not in authored_types or len(row) < 4 or any(row[4:]):
            raise ValueError('Unsupported Homeworld6 authored scenery row')
        kind = authored_types[row[0]]
        width, depth = dimensions[kind]
        ix, iz = (int(float32(float(value))) for value in row[1:3])
        x, z = ix + width * .5, iz + depth * .5
        place(int(x), int(z), x, z, float32(terrain_step(terrain, x, z) * height_scale),
              float32(float(row[3] or 0)), kind, footprint(ix, iz, width, depth), authored=True)

    # The native scan tries a rock first, then tries a tree if no rock fits.
    # The hashes are coordinate-only, so a zero-density pair has no effect.
    for cell, (trees, rocks) in enumerate(zip(tree, rock)):
        if not (trees or rocks) or cell in occupied:
            continue
        iz, ix = divmod(cell, MAP_WIDTH)
        coordinate = struct.pack('<ff', ix, iz)
        rock_candidate = rocks and (coordinate_hash(coordinate, 0x47) * 255 >> 16) < rocks
        tree_candidate = trees and (coordinate_hash(coordinate, 0x1e5) * 255 >> 16) < trees
        if not (rock_candidate or tree_candidate):
            continue
        offset_x = float32(offset_min + coordinate_hash(coordinate, 0xb4868) * fraction_scale * offset_range)
        offset_z = float32(offset_min + coordinate_hash(coordinate, 0x4b17fef) * fraction_scale * offset_range)
        if rock_candidate:
            kind = 20 + (coordinate_hash(coordinate, 0x1e61) * 7 >> 16)
            width, depth = dimensions[kind]
            x, z = float32(ix + width * .5 + offset_x), float32(iz + depth * .5 + offset_z)
            height = float32(terrain_step(terrain, x, z) * height_scale)
            if height > sea_height and ix + width <= MAP_WIDTH and iz + depth <= MAP_WIDTH:
                cells = footprint(ix, iz, width, depth)
                if all(terrain[index] > rock_minimum and index not in occupied for index in cells):
                    rotation = float32(coordinate_hash(coordinate, 0x1ed3) * fraction_scale * rock_rotation)
                    place(ix, iz, x, z, height, rotation, kind, cells)
                    continue
        if tree_candidate:
            x, z = float32(ix + .5 + offset_x), float32(iz + .5 + offset_z)
            height = float32(terrain_step(terrain, x, z) * height_scale)
            if height > sea_height:
                step = int(height / height_scale)
                band = 2 if step >= highland else int(step >= midland)
                kind = band * 5 + (coordinate_hash(coordinate, 0x704) * 5 >> 16)
                rotation = float32(coordinate_hash(coordinate, 0x268f) * fraction_scale * tree_rotation)
                place(ix, iz, x, z, height, rotation, kind, [cell])
    return records


def source_types(source, files, image):
    models = list(csv.DictReader((source/'GeneratedDataFiles/Models.csv').read_text().splitlines()))
    groups = list(csv.reader((source/'GeneratedDataFiles/Groups.csv').read_text().splitlines()))[1:]
    by_enum = {int(row[' EnumId']):row for row in models}
    values = rows(files,'assets/map_object_values.csv')
    by_type = {int(row[0]):dict(zip(values[0],row)) for row in values[1:] if row and row[0].isdigit()}
    result = {}
    for kind in range(27):
        case = 0x10155c40 if kind==0 else struct.unpack('<I',image.read(0x10155e40+(kind-1)*4,4))[0]
        code = image.read(case,13)
        if code[0]!=0xb9: raise ValueError('Unknown native primary scenery model')
        model_enum = struct.unpack_from('<I',code,1)[0]
        model = by_enum[model_enum]
        name = model['FileName']
        group = groups[int(model[' GroupId'])][0]+'.group.bin'
        value = by_type[kind]
        result[str(kind)] = {'model_id':group+':%08x'%iw_hash(name),'model_name':name,
                             'model_enum':model_enum,'source':group,
                             'size_x':int(value['xSize']),'size_z':int(value['ySize']),
                             'belief':int(value['belief']),'dispatch':hex(case),'dispatch_bytes':code.hex()}
    return result


def read_fields(directory):
    fields = {name: (directory / ('homeworld6-' + name + '.bin')).read_bytes() for name in FIELDS}
    if any(len(field) != MAP_WIDTH * MAP_WIDTH for field in fields.values()):
        raise ValueError('Incomplete Homeworld6 scenery fields')
    return fields


def generate_layout(source=ROOT/'data/godus2_4', output=DIRECTORY, *, field_directory=DIRECTORY):
    raw = (source / 'godus.s86').read_bytes()
    executable = hashlib.sha256(raw).hexdigest()
    if executable != SOURCE_EXECUTABLE_SHA256:
        raise ValueError('Unsupported source executable for Homeworld6 scenery')
    image = NativeImage(raw)
    files = decode_archive((source / 'received/godussteamrel/balance.datz').read_bytes())
    config = {row[0]: row[1] for path in ['config.csv', 'balance/config.csv']
              for row in rows(files, path) if len(row) > 1}
    scheme = float(config.get('TreeTypeOverride', '-1'))
    if scheme not in (-1, 0) or ['Colours', '0'] not in rows(files, 'initialworldsetup6/info.csv'):
        raise ValueError('Unsupported Homeworld6 scenery scheme')
    fields = read_fields(field_directory)
    records = generate_records(image, fields, source_types(source, files, image), config,
                               rows(files, 'initialworldsetup6/initialmapobjects.csv')[1:])
    layout = {'executable_sha256': executable, 'routine': '0x1025fcd0', 'bounds': [0, 0, MAP_WIDTH, MAP_WIDTH],
              'configuration': {name: config[name] for name in ['loc2Start', 'loc3Start']},
              'records': records, 'method': 'source placement translation', 'skip_zero_density': True}
    return compile_layout(layout, source, output, field_directory=field_directory)


def compile_layout(capture, source=ROOT/'data/godus2_4', output=DIRECTORY, *, field_directory=DIRECTORY):
    raw = (source/'godus.s86').read_bytes()
    image = NativeImage(raw)
    archive = (source/'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    if capture['executable_sha256']!=hashlib.sha256(raw).hexdigest() or capture['routine']!='0x1025fcd0':
        raise ValueError('Scenery capture has a different original executable')
    if capture['bounds']!=[0,0,MAP_WIDTH,MAP_WIDTH]: raise ValueError('Scenery capture is not the complete map')
    config = {row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(files,path) if len(row)>1}
    for name in ['loc2Start','loc3Start']:
        if float(capture['configuration'][name])!=float(config[name]): raise ValueError('Stale scenery balance: '+name)
    types = source_types(source,files,image)
    payload = bytearray(b'DSCN'+struct.pack('<II',1,len(capture['records'])))
    occupied, roots = set(), set()
    counts = {'trees':0,'rocks':0,'authored':0}
    for item in capture['records']:
        kind = int(item['type'])
        value = types[str(kind)]
        x,z = int(item['root_x']),int(item['root_z'])
        if not (0<=x<MAP_WIDTH and 0<=z<MAP_WIDTH): raise ValueError('Native scenery root outside the map')
        root = z*MAP_WIDTH+x
        if root in roots: raise ValueError('Duplicate native scenery root')
        roots.add(root)
        floats = [item[key] for key in ['x','z','height','rotation']]
        if any(not math.isfinite(v) for v in floats): raise ValueError('Invalid native scenery transform')
        # Original occupancy uses floor(center - half-size + 0.5), not floor.
        origin_x=math.floor(item['x']-value['size_x']*.5+.5)
        origin_z=math.floor(item['z']-value['size_z']*.5+.5)
        cells = footprint(origin_x,origin_z,value['size_x'],value['size_z'])
        if item['cells']!=cells or occupied.intersection(cells): raise ValueError('Conflicting native scenery footprint')
        occupied.update(cells)
        payload.extend(RECORD.pack(root,*floats,cells[0],kind,int(item['authored']),0))
        counts['rocks' if kind>=20 else 'trees']+=1
        counts['authored']+=int(item['authored'])
    paths = ['initialworldsetup6/initialmapobjects.csv','initialworldsetup6/info.csv',
             'assets/map_object_values.csv','config.csv','balance/config.csv']
    fields = read_fields(field_directory)
    routines = [(0x1025f770,0x1025f7eb),(0x1025fcd0,0x102604d0),
                (0x1022d97f,0x1022d998),
                (0x10276500,0x10276617),(0x101b5220,0x101b5273),
                (0x1025b8f0,0x1025c120),(0x10156ae0,0x10156dd4),(0x1025c880,0x1025c911),
                (0x101539c0,0x10153a0f),(0x1025ef6d,0x1025ef80)]
    metadata = {'version':1,'map':'Homeworld6','width':MAP_WIDTH,'record_bytes':RECORD.size,
                'path':'campaign/homeworld6-scenery.bin','sha256':hashlib.sha256(payload).hexdigest(),
                'counts':counts,'occupied_cells':len(occupied),'types':types,
                'source_sha256':hashlib.sha256(archive).hexdigest(),
                'source_files':{name:hashlib.sha256(files[name]).hexdigest() for name in paths},
                'source_fields':{name:hashlib.sha256(data).hexdigest() for name,data in fields.items()},
                'executable_sha256':hashlib.sha256(raw).hexdigest(),
                'model_names_sha256':hashlib.sha256((source/'GeneratedDataFiles/Models.csv').read_bytes()).hexdigest(),
                'groups_sha256':hashlib.sha256((source/'GeneratedDataFiles/Groups.csv').read_bytes()).hexdigest(),
                'native_routines':{hex(start):image.read(start,end-start).hex() for start,end in routines},
                'method':capture.get('method','native comparison'),'zero_density_fast_forward':capture.get('skip_zero_density',False),
                'configuration':capture['configuration'],'native_sea_height':struct.unpack('<f',image.read(0x104ad010,4))[0],
                'scope':'Original authored and generated initial placements.'}
    if 'adapters' in capture:
        metadata['oracle_adapters'] = capture['adapters']
        metadata['oracle_environment'] = {'engine':'Unicorn','version':'2.1.4','architecture':'x86_32','initial_x87_control':0x037f,
                                          'terrain_loaded':'All requested cells; zero-density cells may fast-forward without allocating.'}
    output.mkdir(parents=True,exist_ok=True)
    (output/'homeworld6-scenery.bin').write_bytes(payload)
    (output/'homeworld6-scenery.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path,nargs='?')
    args=parser.parse_args()
    data=generate_layout() if args.capture is None else compile_layout(json.loads(args.capture.read_text()))
    print('Original Homeworld6 placements:',data['counts'],len(data['types']),'native object types')
