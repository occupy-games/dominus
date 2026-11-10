"""Recover original reward registry bindings and authored collection limits."""
import hashlib
import json
import struct

from tools.card_research import extract as research_content
from tools.current_cards import decode_archive,rows,ROOT
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


def extract():
    research=research_content()
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    files=decode_archive(archive)
    tables=dict(research['tables_sha256'])
    details={}
    for group,prefix in [('packs','Pack_'),('stickers','Sticker_'),('cards','Card_')]:
        path='gui/'+dict(packs='packdetails',stickers='stickerdetails',cards='carddetails')[group]+'.csv'
        tables[path]=hashlib.sha256(files[path]).hexdigest()
        details[group]=[key(row[0]) for row in rows(files,path)[1:] if row and row[0].startswith(prefix)]
    path='initialworldsetup/packdata.csv'
    table=rows(files,path)
    tables[path]=hashlib.sha256(files[path]).hexdigest()
    packs=[]
    for row in table[1:]:
        if not row or not row[0].startswith('Pack_'):continue
        packs.append(dict(id=key(row[0]),name=row[1],slots=[dict(count=int(row[4+2*i] or 0),reward=key(row[5+2*i])) for i in range(5)]))
    ranges=[(0x101ab265,0x101ab7d2),(0x10001360,0x100013da),(0x10001870,0x100018de),
            (0x10026690,0x100266c1),(0x100266d0,0x100266f3),(0x10026780,0x1002679d),
            (0x101b51e0,0x101b5273)]
    # Both original constant-limit calls use the same immediate value.
    limits=[struct.unpack('<I',image.read(a,4))[0] for a in [0x101ab369,0x101ab533]]
    if limits[0]!=limits[1]:raise ValueError('Source pack/sticker capacity differs')
    return dict(version=1,executable_sha256=research['executable_sha256'],source_sha256=research['source_sha256'],
                rules=dict(standard_limit=limits[0],capacity=256),details=details,packs=packs,stickers=research['stickers'],
                scopes={scope:dict(cards=cards,available=not research['unavailable'][scope],unavailable=research['unavailable'][scope]) for scope,cards in research['scopes'].items()},
                tables_sha256=tables,native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original fresh reward registration: pack/sticker/card registries, detail links, zero-row resets and capacity registration. Outer startup, other registries, source era and downstream advance effects remain separate ports.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/reward-catalog.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original reward catalog:',len(content['packs']),'packs,',len(content['stickers']),'stickers,',len(content['scopes']),'source scopes')
