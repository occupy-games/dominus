"""Recover the original rock-motion configuration and instruction provenance."""
import hashlib
import json
from pathlib import Path
import struct

from tools.current_cards import decode_archive, rows
from tools.native_config import recover
from tools.native_scenery_oracle import ROOT, NativeImage


def extract(output=None):
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    evidence=recover(raw,['rock'])['TreeRockRaiseAnimationTime']
    if evidence['data']!='0x105da89c': raise ValueError('Unknown rock-motion duration slot')
    files=decode_archive(archive)
    config={r[0]:r[1] for path in ['config.csv','balance/config.csv'] for r in rows(files,path) if len(r)>1}
    if image.read(0x102613b8,7)!=b'\x83\x3d\x0c\xe8\xf2\x10\x0c': raise ValueError('Unknown original rock-motion budget')
    result={'source_sha256':hashlib.sha256(archive).hexdigest(),'executable_sha256':hashlib.sha256(raw).hexdigest(),
            'duration':float(config.get('TreeRockRaiseAnimationTime',evidence['value'])),
            'sea_height':struct.unpack('<f',image.read(0x104ad010,4))[0],'capacity':12,'duration_evidence':evidence,
            'native_routines':{hex(a):image.read(a,b-a).hex() for a,b in [(0x10260e90,0x10261557),(0x1015da0e,0x1015db18),
                                                                       (0x1024ab80,0x1024ac18),(0x10422950,0x104229a4)]}}
    if output: Path(output).write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__=='__main__':
    print('Original rock motion:',extract(ROOT/'game/assets/original/campaign/rock-motion.json')['duration'],'seconds')
