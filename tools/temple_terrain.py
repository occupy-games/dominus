"""Recover the original temple obstruction/decay state block and its constants."""
import hashlib
import json
import struct

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    image=NativeImage(raw)
    constants={}
    for name,address in [('ordinary_seconds',0x105d4c50),('special_seconds',0x105d4cac),('audio_fade',0x104a3320)]:
        value=image.read(address,4)
        constants[name]=dict(address=hex(address),bytes=value.hex(),value=struct.unpack('<f',value)[0])
    kinds=[]
    for address,initializer,slot in [(0x104c0430,0x104147c0,0x10c77620),(0x104c03fc,0x10414760,0x10c77630),(0x104c8d70,0x10414790,0x10c7762c)]:
        name=image.read(address,100).split(b'\0')[0].decode()
        kinds.append(dict(name=name,id=key(name),address=hex(address),initializer=hex(initializer),slot=hex(slot)))
    ranges=[(0x10140ded,0x101410c8)]+[(int(k['initializer'],16),int(k['initializer'],16)+0x29) for k in kinds]
    rules={name:entry['value'] for name,entry in constants.items()}
    rules.update(special_types=[k['id'] for k in kinds],revive_effect=0x2a4d979f,decay_effect=0xf1e56e0d,revive_sound=0x1e9bc797,decay_sound=0x15d2656c)
    footprint={}
    for name,address in [('height_scale',0x104a0c78),('half',0x104a0c30),('inset',0x104a0d60),('clearance',0x104a0d10)]:
        value=image.read(address,8)
        constants['footprint_'+name]=dict(address=hex(address),bytes=value.hex(),value=struct.unpack('<d',value)[0])
        footprint[name]=constants['footprint_'+name]['value']
    ranges.extend([(0x1003b550,0x1003b68b),(0x10357040,0x10357062)])
    frame={}
    for name,address,format in [('forced_decay_rate',0x104ad750,'<d'),('presence_rate',0x104a0d10,'<d'),
                                ('passive_work_rate',0x104a6d08,'<d'),('ground_offset',0x104a3328,'<d'),
                                ('boat_height',0x104ad010,'<f'),('rise_speed',0x104a0c78,'<d'),
                                ('motion_default',0x104a0c28,'<f')]:
        value=image.read(address,struct.calcsize(format))
        constants['frame_'+name]=dict(address=hex(address),bytes=value.hex(),value=struct.unpack(format,value)[0])
        frame[name]=constants['frame_'+name]['value']
    ranges.extend([(0x10140d1e,0x10140ded),(0x101410c8,0x10141204)])
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),rules=rules,constants=constants,special_types=kinds,
                footprint_rules=footprint,frame_rules=frame,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original pre-work worker-presence ramp, passive work, forced decay, phase normalization, blocked/restored transition, removal request, discrete footprint scan, cooldown and vertical targeting. Terrain reads, timed affiliation refresh, spatial registration, downward motion and final removal remain explicit caller services or separate ports.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/temple-terrain.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original temple terrain types:',', '.join(k['name'] for k in content['special_types']))
