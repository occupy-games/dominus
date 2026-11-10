"""Recover original period/sticker-era cache rules and unlock query provenance."""
import hashlib
import json
import struct

from tools.current_cards import ROOT
from tools.native_scenery_oracle import NativeImage


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    string=lambda a:image.read(a,80).split(b'\0')[0].decode()
    maxima=[struct.unpack('<I',image.read(a,4))[0] for a in [0x100f5cae,0x100f5da7]]
    if maxima!=[12,12]:raise ValueError('Source period/era scan bounds moved')
    ranges=[(0x100f5c30,0x100f5ef6),(0x100f62b0,0x100f62bd),(0x1015c1e0,0x1015c23a),
            (0x101b51e0,0x101b5273)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                rules=dict(maximum=maxima[0],period_template=string(0x104c0f24),era_template=string(0x104c0f14)),
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Full dirty-cache refresh, highest period/sticker-era selection, global-cache reentry and period-change notification timing. Unlock-set population and period-change service internals remain separate ports.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/era-progression.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original era cache:',content['rules'])
