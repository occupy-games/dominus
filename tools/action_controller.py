"""Recover original action advancement flags and end-of-sequence branch rules."""
import json
import struct

from tools.action_sequences import extract as sequences
from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    source=sequences()
    image=NativeImage((ROOT/'data/godus2_4/godus.s86').read_bytes())
    first_action=-struct.unpack('<b',image.read(0x1006af33,1))[0]
    branches=list(image.read(0x1006b090,image.read(0x1006af36,1)[0]+1))
    actions=[]
    for action in source['actions']:
        states=[]
        available=True
        for state in action['states']:
            row=state['source']
            complete=state['available'] and all(row.get(key,'').strip() for key in ['Terminable','EndSkipState','FaceTargetEnd'])
            available=available and bool(complete)
            record=dict(index=state['index'],available=bool(complete))
            if complete:record.update(terminable=int(row['Terminable'])!=0,end_skip=int(row['EndSkipState']),face_end=int(row['FaceTargetEnd'])!=0)
            states.append(record)
        description=action['description']
        actions.append(dict(id=action['id'],name=action['name'],available=available,
                            looping=bool(int(description.get('Looping','0'))),states=states))
    return dict(version=1,source_sha256=source['source_sha256'],executable_sha256=source['executable_sha256'],tables=source['tables'],
                rules=dict(house_actions=[first_action+i for i,value in enumerate(branches) if value==0],
                           temple_actions=[first_action+i for i,value in enumerate(branches) if value==1],
                           temple_state=image.read(0x1006af6a,1)[0],decision_phase=struct.unpack('<I',image.read(0x1006af06,4))[0],native_slot=image.read(0x1006afa4,1)[0]),
                default_state=dict(terminable=False,end_skip=-1,face_end=True,update_type=200,loop=False),actions=actions,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x1006ae00,0x1006b09d),(0x1016acd0,0x1016ad67),(0x100702f0,0x10070367),
                    (0x10065a10,0x10065b41),(0x10067620,0x10067735),(0x1035f7f0,0x1035f82d),
                    (0x1016af00,0x1016b133),(0x10001c50,0x10001d50),
                    (0x1000a70b,0x1000a723),(0x1000a766,0x1000a77e),(0x1000a7ab,0x1000a7c3),
                    (0x1039830a,0x10398328)]},
                scope='Original action advancement and composition of state selection/entry. Validity, clip resolution/duration, target position, decision queuing and presentation delivery remain explicit services. No full movement, work update, settlement lifetime or campaign completion is claimed.')


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/action-controller.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original action controller:',len(data['actions']),'action records')
