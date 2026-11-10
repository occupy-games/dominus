"""Package original CPU-recovered Homeworld6 placements with source provenance.

The optional native oracle produces these records by executing the supplied
placement kernel. Runtime loads compact initial state, never an emulator.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import struct

from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage
from tools.original_assets import iw_hash

ROOT = Path(__file__).resolve().parents[1]
RECORD = struct.Struct('<IffffIBBH')


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


def compile_layout(capture, source=ROOT/'data/godus2_4', output=ROOT/'game/assets/original/campaign'):
    raw = (source/'godus.s86').read_bytes()
    image = NativeImage(raw)
    archive = (source/'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    if capture['executable_sha256']!=hashlib.sha256(raw).hexdigest() or capture['routine']!='0x1025fcd0':
        raise ValueError('Scenery capture has a different original executable')
    if capture['bounds']!=[0,0,1024,1024]: raise ValueError('Scenery capture is not the complete map')
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
        if not (0<=x<1024 and 0<=z<1024): raise ValueError('Native scenery root outside the map')
        root = z*1024+x
        if root in roots: raise ValueError('Duplicate native scenery root')
        roots.add(root)
        floats = [item[key] for key in ['x','z','height','rotation']]
        if any(not math.isfinite(v) for v in floats): raise ValueError('Invalid native scenery transform')
        # Original occupancy uses floor(center - half-size + 0.5), not floor.
        origin_x=math.floor(item['x']-value['size_x']*.5+.5)
        origin_z=math.floor(item['z']-value['size_z']*.5+.5)
        cells = [(origin_z+dz)*1024+origin_x+dx for dz in range(value['size_z']) for dx in range(value['size_x'])]
        if item['cells']!=cells or occupied.intersection(cells): raise ValueError('Conflicting native scenery footprint')
        occupied.update(cells)
        payload.extend(RECORD.pack(root,*floats,cells[0],kind,int(item['authored']),0))
        counts['rocks' if kind>=20 else 'trees']+=1
        counts['authored']+=int(item['authored'])
    paths = ['initialworldsetup6/initialmapobjects.csv','initialworldsetup6/info.csv',
             'assets/map_object_values.csv','config.csv','balance/config.csv']
    field_paths = {name:ROOT/'game/assets/original/campaign'/('homeworld6-'+name+'.bin') for name in ['terrain','tree','rock']}
    routines = [(0x1025f770,0x1025f7eb),(0x1025fcd0,0x102604d0),
                (0x1022d97f,0x1022d998),
                (0x10276500,0x10276617),(0x101b5220,0x101b5273),
                (0x1025b8f0,0x1025c120),(0x10156ae0,0x10156dd4),(0x1025c880,0x1025c911)]
    metadata = {'version':1,'map':'Homeworld6','width':1024,'record_bytes':RECORD.size,
                'path':'campaign/homeworld6-scenery.bin','sha256':hashlib.sha256(payload).hexdigest(),
                'counts':counts,'occupied_cells':len(occupied),'types':types,
                'source_sha256':hashlib.sha256(archive).hexdigest(),
                'source_files':{name:hashlib.sha256(files[name]).hexdigest() for name in paths},
                'source_fields':{name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in field_paths.items()},
                'executable_sha256':hashlib.sha256(raw).hexdigest(),
                'model_names_sha256':hashlib.sha256((source/'GeneratedDataFiles/Models.csv').read_bytes()).hexdigest(),
                'groups_sha256':hashlib.sha256((source/'GeneratedDataFiles/Groups.csv').read_bytes()).hexdigest(),
                'native_routines':{hex(start):image.read(start,end-start).hex() for start,end in routines},
                'oracle_adapters':capture['adapters'],'zero_density_fast_forward':capture.get('skip_zero_density',False),
                'oracle_environment':{'engine':'Unicorn','version':'2.1.4','architecture':'x86_32','initial_x87_control':0x037f,
                                      'terrain_loaded':'All requested cells; zero-density cells may fast-forward without allocating.'},
                'configuration':capture['configuration'],'native_sea_height':struct.unpack('<f',image.read(0x104ad010,4))[0],
                'scope':'Initial placement kernel only; runtime regeneration and renderer/event registration are not emulated.'}
    output.mkdir(parents=True,exist_ok=True)
    (output/'homeworld6-scenery.bin').write_bytes(payload)
    (output/'homeworld6-scenery.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path)
    args=parser.parse_args()
    data=compile_layout(json.loads(args.capture.read_text()))
    print('Original Homeworld6 placements:',data['counts'],len(data['types']),'native object types')
