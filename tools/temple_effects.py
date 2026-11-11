"""Recover shrine effect operations and native numeric column bindings."""
import json
import math
import struct

from tools.current_cards import ROOT,decode_archive,rows
from tools.native_scenery_oracle import NativeImage
from tools.temple_modifiers import extract as modifiers_content
from tools.house_values import native_fields
from tools.reward_dispatch import key


def extract():
    content=modifiers_content();raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
    # Read the displacement in the actual column-registration instructions.
    # CSV column order is not the native memory order (notably StaminaDecay).
    bindings={}
    for table,column,address,length,offset_at in [
        ('race','RouteSpeed',0x10030a6d,22,9),
        ('race','StaminaDecay',0x10030c2b,23,10),
        ('jobs','StaminaDecay',0x100308da,22,9)]:
        code=image.read(address,length)
        if code[offset_at-2]!=0x83 or code[offset_at-1] not in [0xc0,0xc1]:raise ValueError('Unexpected native effect column displacement')
        displacement=code[offset_at]
        name_at=offset_at+2
        if code[name_at]!=0x68:raise ValueError('Unexpected native effect column registration')
        name=image.read(struct.unpack_from('<I',code,name_at+1)[0],64).split(b'\0')[0].decode()
        if name!=column or displacement%4:raise ValueError('Mismatched native effect column')
        bindings.setdefault(table,{})[column]=dict(index=displacement//4,address=hex(address),bytes=code.hex())
    capacity=native_fields(raw)['fields']['capacity']
    bindings['House Values']={'Capacity':dict(index=capacity['offset']//4,address=capacity['registration'],bytes=image.read(int(capacity['registration'],16),16).hex())}
    files=decode_archive((ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes())
    table=rows(files,'balance/templeupgrades.csv');source_rows=[row for row in table[1:] if row and row[0] and not row[0].startswith('#')]
    records=[]
    for record,row in zip(content['records'],source_rows,strict=True):
        tokens=[token.lstrip(' \t') for token in record['effect'].split(',')]
        _,name,column,operation=tokens
        prefix=operation[:1];multiply=prefix in ['x','m']
        number=operation[1:] if prefix in ['x','m','+','p'] else operation
        value=struct.unpack('<f',struct.pack('<f',float(number)))[0]
        if not math.isfinite(value):raise ValueError('Invalid source effect value')
        flags={field:int(row[table[0].index(field)] or 0) if field in table[0] else 0 for field in ['abode','monastery','farm','mine']}
        records.append(dict(record,table=name,column=column,index=bindings[name][column]['index'],operation=int(multiply),value=value,**flags))
    monastery_types=[]
    for address in [0x104bb36c,0x104bb358,0x104bb344,0x104bb330,0x104bb31c,0x104bb308]:
        name=image.read(address,64).split(b'\0')[0].decode()
        monastery_types.append(dict(name=name,id=key(name),address=hex(address)))
    routines=[(0x10171610,0x1017173d),(0x100340d0,0x10034158),(0x100342a0,0x100343a4),
              (0x100343b0,0x100344ab),(0x100b6d60,0x100b6e0f),(0x100b6e10,0x100b6e2d),(0x100b6e90,0x100b7012),
              (0x100b7580,0x100b78e6),(0x1013efa0,0x1013f07b),(0x1013f080,0x1013f169),(0x10153d80,0x10153dc9),
              (0x1006d050,0x1006d203)]
    selector=image.read(0x1006d134,5)
    if selector[0]!=0x68:raise ValueError('Unexpected original shrine spatial query')
    propagation=dict(query_tag=struct.unpack_from('<I',selector,1)[0],query_flags=[0,0,0,0,1,1],max_candidates=(0x10c64e68-0x10c58e68)//12)
    return dict(version=1,executable_sha256=content['executable_sha256'],source_sha256=content['source_sha256'],
                tables_sha256=content['tables_sha256'],bindings=bindings,records=records,monastery_types=monastery_types,
                row_words={'race':41,'jobs':16,'House Values':76},
                propagation_rules=propagation,
                native_routines=dict(content['native_routines'],**{hex(a):image.read(a,b-a).hex() for a,b in routines}),
                scope='Original parsed shrine effects, follower/house mask collection, inherited area, ordered follower/job stat application and shrine-only house stat application. Resolved base rows, unrelated global modifiers, bulk spatial updates and full actor dispatch remain caller responsibilities.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/temple-effects.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original shrine stat effects:',len(content['records']))
