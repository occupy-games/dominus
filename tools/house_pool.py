"""Recover original world house-pool allocation and header initialization."""
import hashlib
import json
import struct

from tools.native_scenery_oracle import NativeImage, ROOT


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    image=NativeImage(raw)
    for address,prefix in [(0x10435d70,b'\xb9'),(0x101b1347,b'\x68'),(0x101b136f,b'\x68'),
                           (0x101b137d,b'\x68'),(0x101b1392,b'\x8d\x8e')]:
        if image.read(address,len(prefix))!=prefix:raise ValueError('Unknown original house-pool initializer')
    root=struct.unpack('<I',image.read(0x10435d71,4))[0]
    offset=struct.unpack('<I',image.read(0x101b1394,4))[0]
    allocated=struct.unpack('<I',image.read(0x101b1348,4))[0]
    capacity=struct.unpack('<I',image.read(0x101b1370,4))[0]
    stride=struct.unpack('<I',image.read(0x101b137e,4))[0]
    if root+offset!=0x10fcd474 or allocated!=capacity*stride+4:
        raise ValueError('Mismatched native pool allocation/header')
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),
                rules=dict(capacity=capacity),world_root=hex(root),header_offset=offset,header=hex(root+offset),
                stride=stride,allocation_bytes=allocated,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in [
                    (0x10435d70,0x10435d7a),(0x101b1347,0x101b13a7),(0x1019fbc0,0x1019fc38),
                    (0x100441c0,0x1004424c),(0x10044250,0x1004430c)]})


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/house-pool.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original house-pool capacity:',data['rules']['capacity'])
