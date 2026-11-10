"""Recover native state-entry parameters and source update-type enumeration."""
import json
import re
import struct

from tools.action_sequences import extract as sequences
from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    source=sequences()
    image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
    start,end=0x1000920b,0x10009b2f
    code=image.read(start,end-start)
    matches=list(re.finditer(rb'\x68(.{4})\x8d\x4d\xcc',code,re.S))
    enumeration={}
    evidence={}
    for i,match in enumerate(matches):
        block=code[match.start():matches[i+1].start() if i+1<len(matches) else len(code)]
        name=image.read(struct.unpack('<I',match[1])[0],80).split(b'\0')[0].decode('ascii')
        value=re.search(rb'\xc7\x00(.{4})',block,re.S)
        if value:number=struct.unpack('<I',value[1])[0]
        elif b'\x89\x18' in block:number=0
        else:raise ValueError('Unknown source update-type registration: '+name)
        enumeration[name]=number
        evidence[hex(start+match.start())]=block.hex()
    rules=dict(missing_clip=struct.unpack('<I',image.read(0x10067682,4))[0],
               missing_update=struct.unpack('<I',image.read(0x1006768b,4))[0],
               orientation_scale=struct.unpack('<d',image.read(0x104a0ce0,8))[0])
    records=[]
    for action in source['actions']:
        for state in action['states']:
            raw=state['source']
            name=raw.get('UpdateType','')
            available=name in enumeration and raw.get('Loop','').strip()!=''
            record=dict(action=action['id'],index=state['index'],name=action['name']+'/'+state['name'],available=available,update_name=name)
            if available:record.update(update_type=enumeration[name],loop=int(raw['Loop'])!=0)
            records.append(record)
    return dict(version=1,executable_sha256=source['executable_sha256'],source_sha256=source['source_sha256'],tables=source['tables'],
                rules=rules,update_types=enumeration,enumeration_evidence=evidence,records=records,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x10067620,0x10067735),(0x1000aa5a,0x1000aa69),(0x1000a70b,0x1000a723)]},
                scope='State-entry timing and presentation intents only. Clip/variant resolution and clip duration are supplied simulation inputs; animation assets, action update, navigation and active work are separate.')


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/action-entry.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original action entry:',len(data['update_types']),'update types;',sum(r['available'] for r in data['records']),'available source records')
