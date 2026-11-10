"""Recover source card research fields, hashes, messages and instruction provenance."""
import hashlib
import json

from tools.current_cards import decode_archive,rows,ROOT
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


def pair_key(card,sticker):
    value=0
    for byte in card.to_bytes(4,'little')+sticker.to_bytes(4,'little'):
        value=((value+byte)*0x401)&0xffffffff
        value^=value>>6
    value=(value*9)&0xffffffff
    return ((value^(value>>11))*0x8001)&0xffffffff


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    files=decode_archive(archive)
    string=lambda address:image.read(address,400).split(b'\0')[0].decode()
    types=[string(a) for a in [0x104aa00c,0x104aa004,0x104a9ffc,0x104a9ff4]]
    categories=['']+[string(a) for a in [0x104a0a74,0x104a0a6c,0x104a0a64,0x104a0a5c,0x104a0a54]]
    rules=dict(research_suffixes=['']+[string(a) for a in [0x104a0714,0x104a0708,0x104a06fc,0x104a06f0,0x104a06e4]],
               completion_suffix=string(0x104a0738),research_limit=99999,combination_limit=0x0fffffff,
               strings={hex(a):string(a) for a in [0x104a6510,0x104a64b8,0x104a6768,0x104a6700,0x104a6680,0x104a6644,0x104a65f8]},
               happiness={str(i):string(a) for i,a in [(-3,0x104a6580),(-2,0x104a6594),(-1,0x104a65a8),(1,0x104a65e4),(2,0x104a65d0),(3,0x104a65bc)]})
    tables={}
    scopes={}
    unavailable={}
    for scope in ['initialworldsetup']+[f'initialworldsetup{i}' for i in range(2,8)]:
        path=scope+'/carddata.csv'
        table=rows(files,path)
        tables[path]=hashlib.sha256(files[path]).hexdigest()
        cards=[]
        unavailable[scope]=[]
        for row in table[1:]:
            if not row or not row[0].startswith('Card_'):continue
            entry=dict(zip(table[0],row))
            if entry['Type ID'] not in types:
                unavailable[scope].append(dict(source_id=entry['Unlock'],source_type=entry['Type ID'],reason='Type absent from the supplied executable enum'))
                continue
            cards.append(dict(id=key(entry['Unlock']),name=entry['Unlock Name'],type=types.index(entry['Type ID']),
                              category=categories.index(entry['Research Type']),research_needed=int(entry['Research Needed'] or 0),
                              slot_20=int(entry.get('Era Available') or 0),
                              max_collectable=int(entry.get('Max Collectable') or 0),
                              happiness=int(entry.get('Happiness Boost') or 0),silent=int(entry.get('Silent Type') or 0),source_id=entry['Unlock']))
        scopes[scope]=cards
    path='initialworldsetup/stickerdata.csv'
    table=rows(files,path)
    tables[path]=hashlib.sha256(files[path]).hexdigest()
    stickers=[]
    for row in table[1:]:
        if not row or not row[0].startswith('Sticker_'):continue
        entry=dict(zip(table[0],row))
        stickers.append(dict(id=key(entry['Unlock']),internal=entry['Is Internal']=='1',
                             categories=[categories.index(entry['Element '+str(i)]) for i in [1,2]],
                             counts=[int(entry['Element Count '+str(i)] or 0) for i in [1,2]],source_id=entry['Unlock'],
                             category=categories.index(entry['Element 1']),count=int(entry['Element Count 1'] or 0),
                             era=int(entry.get('Era Available') or 0)&0xffffffff,slot_08=1))
    ranges=[(0x10001360,0x100013da),(0x10001480,0x1000153c),(0x100015b0,0x100018de),
            (0x10026700,0x10026775),(0x100268a0,0x10026a03),(0x10026f40,0x1002700a),
            (0x10027330,0x10027644),(0x100281e0,0x100282dc),(0x10028420,0x10028563),
            (0x101b51e0,0x101b5273),(0x1039dd10,0x1039ddb3),(0x1039f070,0x1039f100),
            (0x1002dfaf,0x1002e04e),(0x10032471,0x100324ee),(0x101ab4d0,0x101ab4d9),
            (0x101ab5c6,0x101ab5e4),(0x101ab6b0,0x101ab725)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                rules=rules,scopes=scopes,unavailable=unavailable,stickers=stickers,types=types,categories=categories,tables_sha256=tables,
                selection_fields=dict(card_slot_20='Era Available',sticker_slot_08='Non-null source detail link. Original binder initializes a fallback at 0x101ab4d2 before looking up supplied details; the selector only tests non-null. Plain data records retain this as 1, never a native pointer.'),
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original research registration, remaining/progress, eligibility, one-sticker assignment and completion. Ordered failed writes are not rolled back. Notifications and happiness effects remain explicit services.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/card-research.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original card research:',sum(map(len,content['scopes'].values())),'card rows,',len(content['stickers']),'stickers')
