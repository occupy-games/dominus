"""Recover source action identities and state-selection controls, without enabling jobs."""
import hashlib
import json
import re
import struct

from tools.current_cards import decode_archive, rows
from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    files=decode_archive(archive)
    image=NativeImage(raw)
    start,end=0x1000b36a,0x1000c667
    code=image.read(start,end-start)
    matches=list(re.finditer(rb'\x68(.{4})\x8d\x4d\xf0',code,re.S))
    identities={}
    for i,match in enumerate(matches):
        block=code[match.start():matches[i+1].start() if i+1<len(matches) else len(code)]
        name=image.read(struct.unpack('<I',match[1])[0],80).split(b'\0')[0].decode('ascii')
        value=re.search(rb'\xc7\x00(.{4})',block,re.S)
        if value:identity=struct.unpack('<I',value[1])[0]
        elif b'\x89\x18' in block:identity=0
        else:raise ValueError('Unknown native action registration: '+name)
        if name in identities:raise ValueError('Duplicate original action identity')
        identities[name]=dict(id=identity,address=hex(start+match.start()),bytes=block.hex())
    if {key:identities[key]['id'] for key in ['BuildPlot','BuildHouse','BuildFarm','BuildMine']}!={'BuildPlot':102,'BuildHouse':103,'BuildFarm':108,'BuildMine':111}:
        raise ValueError('Changed original construction actions')
    capacity=image.read(0x10065a40,1)[0]
    guard=image.read(0x10065a56,1)[0]+1
    if capacity!=20 or guard!=21:raise ValueError('Unknown native state-selection bounds')
    constants=dict(random_divisor=struct.unpack('<d',image.read(0x104a0c10,8))[0],
                   rng_multiplier=struct.unpack('<I',image.read(0x1035f808,4))[0],
                   rng_increment=struct.unpack('<I',image.read(0x1035f80e,4))[0],
                   rng_shift=image.read(0x1035f823,1)[0],rng_mask=struct.unpack('<I',image.read(0x1035f825,4))[0])
    action_rows=rows(files,'balance/actions.csv')
    descriptions={row[0]:dict(zip(action_rows[0],row)) for row in action_rows[1:] if row and row[0]}
    records={name:dict(id=value['id'],name=name,description=descriptions.get(name,{}),states=[]) for name,value in identities.items()}
    state_rows=rows(files,'balance/actionstates.csv')
    headers=state_rows[0]
    for row in state_rows[1:]:
        if not row or not row[0]:continue
        source=dict(zip(headers,row))
        if source['ActionName'] not in records:raise ValueError('Unregistered source action')
        index=int(source['Index'])
        if not 0<=index<capacity:raise ValueError('Original action-state index out of range')
        complete=all(source.get(key,'').strip() for key in ['NextState','SkipProbability','SkipToState'])
        record=dict(index=index,name=source['Name'],source=source,available=complete)
        if complete:
            record.update(next=int(source['NextState']),skip_to=int(source['SkipToState']),
                          skip_probability=struct.unpack('<f',struct.pack('<f',float(source['SkipProbability'])))[0])
        records[source['ActionName']]['states'].append(record)
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                tables={key:hashlib.sha256(files[key]).hexdigest() for key in ['balance/actions.csv','balance/actionstates.csv']},
                rules=dict(capacity=capacity,iteration_limit=guard,**constants),
                default_state=dict(name='',next=-1,skip_to=-1,skip_probability=0.),
                actions=list(records.values()),identities=identities,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x10065a10,0x10065b41),(0x10001c50,0x10001d50),(0x1035f7f0,0x1035f82d),
                    (0x1000a766,0x1000a77e),(0x10031b2e,0x10031b78)]},
                scope='Original action identity and state-choice controls only. Blank numeric controls remain unavailable pending native CSV default recovery. State validity, entry, movement, work and lifetime are separate services.')


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/action-sequences.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original action sequences:',len(data['actions']),'identities;',sum(len(a['states']) for a in data['actions']),'source states')
