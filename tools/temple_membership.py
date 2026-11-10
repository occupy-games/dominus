"""Recover temple affiliation cadence and the original type-radius mapping."""
import hashlib
import json
import struct

from tools.current_cards import ROOT,decode_archive,rows
from tools.native_scenery_oracle import NativeImage


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    balance=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw);files=decode_archive(balance)
    constants={}
    for name,address in [('interval_half',0x104ad750),('random_divisor',0x104a0c10)]:
        data=image.read(address,8)
        constants[name]=dict(address=hex(address),bytes=data.hex(),value=struct.unpack('<d',data)[0])
    path='balance/templetypes.csv';table=rows(files,path)
    name_column=table[0].index('name');radius_column=table[0].index('radius outside settlement')
    radii={row[name_column]:float(row[radius_column] or 0) for row in table[1:] if len(row)>radius_column and row[0] and not row[0].startswith('#')}
    # The source table registration binds this column to row +0x10. The
    # containment routines read that same slot; vision radius is +0x14.
    loader=image.read(0x100329e1,16)
    if loader[:1]!=b'\x68' or struct.unpack('<I',loader[1:5])[0]!=0x10f1bb5c:raise ValueError('Unexpected temple radius binding')
    routines=[(0x10140c0f,0x10140d1e),(0x1013f080,0x1013f169),(0x10153d80,0x10153dc9)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(balance).hexdigest(),
                rules={name:entry['value'] for name,entry in constants.items()},constants=constants,radii=radii,
                tables_sha256={path:hashlib.sha256(files[path]).hexdigest()},
                radius_binding=dict(address=hex(0x100329e1),bytes=loader.hex(),column='radius outside settlement',record_offset=0x10),
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in routines},
                scope='Original timed affiliation scan, all-candidate ordering, owner inheritance, direct circular and inherited spherical containment, and deadline arithmetic. Modifier refresh, active collection ownership and explicit clock/RNG services remain caller responsibilities.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/temple-membership.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original temple membership radii:',len(content['radii']))
