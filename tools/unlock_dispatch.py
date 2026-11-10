"""Recover authored unlock dependencies and native claim/timer constants."""
import hashlib
import json
import struct

from tools.current_cards import ROOT,decode_archive,rows
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw);files=decode_archive(archive)
    scopes={};used={}
    for scope in ['initialworldsetup']+[f'initialworldsetup{i}' for i in range(2,8)]:
        path=scope+'/unlocks.csv';used[path]=hashlib.sha256(files[path]).hexdigest()
        dependencies=[];bindings=[]
        for row in rows(files,path):
            if not row or row[0].startswith('#'):continue
            # Original callback discards empty and leading-whitespace fields.
            tokens=[v for v in row if v and ord(v[0])>32]
            if len(tokens)<=1:continue
            if len(tokens) not in (2,4):raise ValueError('Unported unlock CSV shape: '+repr(tokens))
            dependencies.append(dict(unlock=key(tokens[0]),condition=key(tokens[1]),phase=1))
            bindings.append(dict(unlock=tokens[0],condition=tokens[1],achievement=tokens[2:] if len(tokens)>2 else []))
        scopes[scope]=dict(dependencies=dependencies,bindings=bindings)
    path='balance/dynamicclaims.csv';used[path]=hashlib.sha256(files[path]).hexdigest()
    dynamic=[]
    for row in rows(files,path)[1:]:
        if len(row)>1 and row[0] and not row[0].startswith('#'):
            dynamic.append(dict(id=key(row[0]),seconds=int(row[1])))
    if len(dynamic)>50:raise ValueError('Original dynamic claim capacity exceeded')
    dynamic.extend(dict(id=0,seconds=0) for _ in range(50-len(dynamic)))
    ranges=[(0x1015bcb0,0x1015bd1b),(0x1015c0d0,0x1015c12e),(0x1015c130,0x1015c1d5),
            (0x1015c270,0x1015c356),(0x1015c640,0x1015c702),(0x1015c710,0x1015c7e1),
            (0x1015c7f0,0x1015c975),(0x1015c9e0,0x1015ca32),(0x1015cc90,0x1015cca9),
            (0x1015cd60,0x1015cda1),
            (0x1015cdb0,0x1015cea2),(0x1015cf20,0x1015cfbe),
            (0x1035f840,0x1035f8eb)]
    strings={hex(a):image.read(a,100).split(b'\0')[0].decode() for a in [0x104cc9dc,0x104cc9c0]}
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                tables_sha256=used,rules=dict(capacity=16384,dynamic_claims=dynamic,strings=strings,
                                             ordinary_duration=struct.unpack('<f',image.read(0x104a0c28,4))[0],
                                             milliseconds_per_second=struct.unpack('<d',image.read(0x104a7518,8))[0]),scopes=scopes,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original raw/string dependency registration, recursive propagation, immediate claim, remaining-time query, persistent replay and expiry. Authored first two columns are dependency pairs; extra columns are achievement bindings. Startup registration, CSV/achievement callbacks, effect/configuration reset internals and notification effects remain separate ports; native timer-tree allocation/removal is a storage adapter.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/unlock-dispatch.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original unlock dependencies:',sum(len(v['dependencies']) for v in content['scopes'].values()))
