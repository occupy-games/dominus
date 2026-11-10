"""Recover original construction-start actions and footprint radius constant."""
import hashlib
import json
import struct

from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    image=NativeImage(raw)
    instructions={hex(a):image.read(a,n).hex() for a,n in [
        (0x1006b5ca,5),(0x1006b5e1,5),(0x1006b5dc,3),(0x1006b59b,5)]}
    for address,prefix in [(0x1006b5ca,b'\xb8'),(0x1006b5e1,b'\xb8'),(0x1006b5dc,b'\x8d\x41'),(0x1006b59b,b'\x68')]:
        if image.read(address,len(prefix))!=prefix:raise ValueError('Unknown native construction action instruction')
    rules=dict(builder_action=struct.unpack('<I',image.read(0x1006b5cb,4))[0],
               farmer_action=struct.unpack('<I',image.read(0x1006b5e2,4))[0],
               miner_action=image.read(0x1006b5de,1)[0],
               target_action=struct.unpack('<I',image.read(0x1006b59c,4))[0],
               half=struct.unpack('<d',image.read(0x104a0c30,8))[0])
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),rules=rules,
                instructions=instructions,constants={'0x104a0c30':image.read(0x104a0c30,8).hex()},
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x1006b4d0,0x1006b687),(0x1016b360,0x1016b3ae),(0x1016adb0,0x1016aeff)]})


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/build-start.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original construction-start rules:',data['rules'])
