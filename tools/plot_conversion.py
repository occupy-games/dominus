"""Recover constants/provenance for the original plot-to-building factory."""
import hashlib
import json
import struct

from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    image=NativeImage(raw)
    constants={key:dict(address=hex(address),bytes=image.read(address,8).hex(),value=struct.unpack('<d',image.read(address,8))[0])
               for key,address in [('height_offset',0x104aaed0),('pi',0x104a0c68)]}
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),constants=constants,
                rules={key:value['value'] for key,value in constants.items()},
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x10044c30,0x10044ca6),(0x10044cb0,0x10044f97),
                    (0x10044110,0x100441b8),(0x10235750,0x1023576b)]})


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/plot-conversion.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original plot-conversion constants:',data['rules'])
