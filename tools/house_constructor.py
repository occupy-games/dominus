"""Recover original constructor constants and resolved core-state inputs."""
import hashlib
import json
import struct

from tools.house_selection import extract as selection
from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    selected=selection()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    image=NativeImage(raw)
    houses=json.loads((ROOT/'game/assets/original/campaign/house-rules.json').read_text())
    if houses['native']['executable_sha256']!=selected['executable_sha256'] or houses['table_sha256']!=selected['table_sha256']:
        raise ValueError('Stale source constructor units')
    addresses=dict(half=(0x104a0c30,'d'),rank_divisor=(0x104aaf18,'d'),rank_bias=(0x104a0c40,'d'),
                   pi=(0x104a0c68,'d'),negative_pi=(0x104a0c88,'d'),two_pi=(0x104a0c90,'d'),
                   update_delay=(0x104aaef0,'d'),beauty_threshold=(0x105b2d40,'f'),
                   rotation_override=(0x105b2d1c,'f'))
    constants={key:dict(address=hex(address),bytes=image.read(address,struct.calcsize(fmt)).hex(),
                        value=struct.unpack('<'+fmt,image.read(address,struct.calcsize(fmt)))[0])
               for key,(address,fmt) in addresses.items()}
    rules={key:constant['value'] for key,constant in constants.items()}
    rules['rotation_override_id']=image.read(0x104bb2d8,64).split(b'\0')[0].decode('ascii')
    rules['mine_ranges']=[list(struct.unpack('<2f',image.read(0x105b2cd8+i*8,8))) for i in range(6)]
    rules['ordinary_event']=struct.unpack('<I',image.read(0x100bca90,4))[0]
    rules['special_event']=(rules['ordinary_event']+struct.unpack('<I',image.read(0x100bca8b,4))[0])&0xffffffff
    fields=['base size','capacity','build capacity','buildbuildingpriority','visionradius']
    records=[]
    for index,(key,record) in enumerate(houses['records'].items()):
        records.append(dict(index=index,id=key,rank=int(record['raw']['Rank']),
                            values={field:record['values'][field] for field in fields}))
    return dict(version=1,source_sha256=selected['source_sha256'],table_sha256=selected['table_sha256'],
                executable_sha256=hashlib.sha256(raw).hexdigest(),rules=rules,constants=constants,records=records,
                fields={key:houses['native']['fields'][key] for key in fields},
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x100bc660,0x100bcb72),(0x1003f610,0x1003f945),(0x100b7460,0x100b7536),
                    (0x100b7900,0x100b79fb),(0x10153dd0,0x10153dff),(0x1003e400,0x1003e505),(0x10357040,0x10357062)]})


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/house-constructor.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original house constructor inputs:',len(data['records']),'rows')
