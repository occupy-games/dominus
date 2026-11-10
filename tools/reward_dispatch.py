"""Recover original reward dispatch, recursive packs and story selection inputs."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows, ROOT
from tools.native_config import recover
from tools.native_scenery_oracle import NativeImage
from tools.sticker_selection import extract as sticker_content


def key(name):
    # Original 0x101b51e0 + 0x101b5260, case-sensitive bytes.
    value=0
    for byte in name.encode():
        value=((value+byte)*0x401)&0xffffffff
        value^=value>>6
    value=(value*9)&0xffffffff
    return ((value^(value>>11))*0x8001)&0xffffffff


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    files=decode_archive(archive)
    native=recover(raw,['storyessentialodds'])
    chance=native['StoryEssentialOdds']['value']
    used={}
    for path in ['config.csv','balance/config.csv']:
        used[path]=hashlib.sha256(files[path]).hexdigest()
        for row in rows(files,path):
            if len(row)>1 and row[0]=='StoryEssentialOdds':chance=float(row[1])
    symbols={}
    for name,address in [('next_story',0x104ac148),('random_side_story',0x104ac130),('random_story',0x104ac154),('fallback',0x104ac920),('discovery_type',0x104aadc4)]:
        text=image.read(address,100).split(b'\0')[0].decode()
        symbols[name]=dict(name=text,id=key(text),address=hex(address))
    shared=sticker_content()
    selection_addresses=[0x107ded3c,0x107ded14,0x107ded48,0x107ded00,0x107ded1c,0x107ded10,0x107ded44,0x107ded4c,0x107ded54,0x107ded40,0x107ded08]
    selectors=[dict(name=shared['symbols'][hex(a)],id=key(shared['symbols'][hex(a)]),address=hex(a)) for a in selection_addresses]
    event=shared['symbols']['0x107ded2c']
    symbols['event_reward']=dict(name=event,id=key(event),address='0x107ded2c')
    tables={}
    for path in files:
        if path.endswith(('/packdata.csv','/storypieces.csv')):
            tables[path]=rows(files,path)
            used[path]=hashlib.sha256(files[path]).hexdigest()
    rules=dict(story_chance=chance,story_priority_limit=1000000,random_divisor=struct.unpack('<d',image.read(0x104a0c10,8))[0],
               next_story=symbols['next_story']['id'],random_side_story=symbols['random_side_story']['id'],
               random_story=symbols['random_story']['id'],fallback=symbols['fallback']['id'],
               event_reward=symbols['event_reward']['id'],sticker_selectors=[s['id'] for s in selectors],
               chest_reason=7,temple_reason=8,discovery_type=symbols['discovery_type']['id'])
    ranges=[(0x10050930,0x1005107c),(0x100514f0,0x10051546),
            (0x10140b9c,0x10140c0f),(0x1003af00,0x1003af7c),
            (0x101b51e0,0x101b5213),(0x101b5260,0x101b5273),
            (0x100267b0,0x100267ba),(0x10352ed0,0x10352f39)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                rules=rules,symbols=symbols,selectors=selectors,native_configuration=native,tables=tables,tables_sha256=used,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Full source reward dispatcher and chest/temple wrappers, plus deferred discovery-temple dispatch. Final credit service, event-reward selector and story display remain explicit services.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/reward-dispatch.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original reward dispatch:',len(content['tables']),'source tables')
