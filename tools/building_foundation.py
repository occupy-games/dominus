"""Recover original building foundation scan constants and instruction evidence."""
import hashlib
import json
import struct

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes();image=NativeImage(raw)
    constants={}
    for name,address in [('half',0x104a0c30),('inset',0x104a0d60),('tolerance',0x104a0d10)]:
        code=image.read(address,8)
        constants[name]=dict(address=hex(address),bytes=code.hex(),value=struct.unpack('<d',code)[0])
    ranges=[(0x1003b690,0x1003b7e8),(0x10357040,0x10357062),(0x102d5a80,0x102d5a87)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),constants=constants,
                rules={name:entry['value'] for name,entry in constants.items()},
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original inclusive foundation sample bounds, integer anchor conversion, overlay-first/fallback terrain queries, strict absolute mismatch count and float32 stores. Terrain override ownership, actor lifetime responses and navigation consequences remain caller responsibilities.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/building-foundation.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original building foundation scan constants recovered')
