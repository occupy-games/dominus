"""Recover original building-selection fields and enumeration registrations.

This converts source rows to plain decisions; it does not create art or enable
unported construction. Optional native comparisons live in a separate tool.
"""
import hashlib
import json
from pathlib import Path
import re
import struct

from tools.house_values import ROOT, native_fields, resolve
from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage


def enumeration(image, start, end, base, count):
    code = image.read(start, end-start)
    names = [image.read(struct.unpack('<I', m[1])[0], 64).split(b'\0')[0].decode('ascii')
             for m in re.finditer(rb'\x68(.{4})\x8d\x4d\xfc', code, re.S)]
    slots = [struct.unpack('<I', m[1])[0] for m in re.finditer(rb'\xa3(.{4})', code, re.S)
             if base <= struct.unpack('<I', m[1])[0] < base+count*4]
    if len(names) != count or slots != list(range(base, base+count*4, 4)):
        raise ValueError('Unknown native house enumeration initializer')
    return dict(zip(names, range(count)))


def extract(source=ROOT/'data/godus2_4', output=None):
    raw = (source/'godus.s86').read_bytes()
    archive = (source/'received/godussteamrel/balance.datz').read_bytes()
    files = decode_archive(archive)
    image = NativeImage(raw)
    registrations = {}
    code = image.read(0x10030ed5, 0x10030fca-0x10030ed5)
    for m in re.finditer(rb'\x68(.{4})\x68(.{4})\x56\xe8(.{4})', code, re.S):
        slot, name, relative = struct.unpack('<IIi', b''.join(m.groups()))
        if 0x10030ed5+m.start()+16+relative != 0x10170c10:
            raise ValueError('Unknown native house column registration')
        registrations[image.read(name,64).split(b'\0')[0].decode('ascii').strip()] = slot-0x10fc701c
    expected = {'Base size':4,'Model Name':12,'Unlock':48,'Loc Avalaible':52,'Biome Available':56,'Order':60}
    if any(registrations.get(key) != value for key,value in expected.items()):
        raise ValueError('Unknown native selection fields')
    locations = enumeration(image,0x1039e530,0x1039e624,0x107ce174,8)
    biomes = enumeration(image,0x1039e630,0x1039e80c,0x107ce3c0,16)
    special_models = {}
    for kind,start in [(1,0x1039f880),(2,0x1039f8b0)]:
        code = image.read(start,0x29)
        if code[4] != 0x68: raise ValueError('Unknown original production model initializer')
        special_models[image.read(struct.unpack_from('<I',code,5)[0],64).split(b'\0')[0].decode('ascii')] = kind
    records = resolve(rows(files,'balance/housevalues.csv'),native_fields(raw))
    configuration = {row[0]:row[1] for path in ['config.csv','balance/config.csv'] for row in rows(files,path) if len(row)>1}
    entries = []
    for index,(name,record) in enumerate(records.items()):
        row = record['raw']
        entries.append({'index':index,'id':name,'size':record['values']['base size'],
                        'order':int(row['Order']),'unlock':row['Unlock'],
                        'locations':locations[row['Loc Avalaible']],'biomes':biomes[row['Biome Available']],
                        'kind':special_models.get(row['Model Name'],0)})
    result = {'source':'received/godussteamrel/balance.datz','source_sha256':hashlib.sha256(archive).hexdigest(),
              'table':'balance/housevalues.csv','table_sha256':hashlib.sha256(files['balance/housevalues.csv']).hexdigest(),
              'executable_sha256':hashlib.sha256(raw).hexdigest(),'fields':expected,
              'configuration':{key:float(configuration[key]) for key in ['biome1Index','biome2Index','biome3Index']},
              'locations':locations,'biomes':biomes,'special_models':special_models,'rows':entries,
              'native_routines':{hex(a):image.read(a,b-a).hex() for a,b in [
                  (0x100b72c0,0x100b739b),(0x100b7540,0x100b7574),(0x100b6750,0x100b67d2),
                  (0x1025b610,0x1025b66c),(0x10026a10,0x10026a66),
                  (0x10030ed5,0x10030fca),(0x1039e530,0x1039e624),(0x1039e630,0x1039e80c),
                  (0x1039f880,0x1039f8d9)]}}
    if output is not None:
        Path(output).write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__ == '__main__':
    data = extract(output=ROOT/'game/assets/original/campaign/house-selection.json')
    print('Original building selection:',len(data['rows']),'source records')
