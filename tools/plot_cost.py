"""Recover original plot food-cost values, currency gates and instruction evidence."""
import json
import struct

from tools.house_selection import extract as selection
from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    source=selection()
    houses=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
    if houses['table_sha256']!=source['table_sha256'] or houses['native']['executable_sha256']!=source['executable_sha256']:
        raise ValueError('Stale resolved house cost values')
    field=houses['native']['fields']['wheat consumed']
    if field['offset']!=0x108 or field['arithmetic']!='float32':
        raise ValueError('Unknown native plot cost column')
    image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
    constants={key:dict(address=hex(address),bytes=image.read(address,8).hex(),value=struct.unpack('<d',image.read(address,8))[0])
               for key,address in [('half',0x104a0c30),('height_scale',0x104a0c78),('ore_minimum',0x104a0c48)]}
    first_state=struct.unpack('<I',image.read(0x100476bb,4))[0]
    if image.read(0x100476ba,1)!=b'\xb9' or image.read(0x1004779c,2)!=b'\x2b\xc1' or image.read(0x100477a0,2)!=b'\x83\xe8':
        raise ValueError('Unknown original counted-house state predicate')
    return dict(version=1,source_sha256=source['source_sha256'],table_sha256=source['table_sha256'],
                executable_sha256=source['executable_sha256'],field=field,constants=constants,
                rules={key:row['value'] for key,row in constants.items()},
                costs=[dict(index=i,id=key,food=row['values']['wheat consumed']) for i,(key,row) in enumerate(houses['records'].items())],
                counted_house_states=[first_state,first_state+image.read(0x100477a2,1)[0]],
                counted_house_evidence={hex(a):image.read(a,b-a).hex() for a,b in [(0x100476b3,0x100476c5),(0x10047791,0x100477b3)]},
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x10235bd0,0x10235c88),(0x10235c90,0x10235cea),(0x10235cf0,0x10235d42),
                    (0x100b7540,0x100b7574),(0x101539c0,0x10153a0f),(0x10043d10,0x10043d16)]})


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/plot-cost.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original plot costs:',len(data['costs']),'rows')
