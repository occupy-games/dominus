"""Recover original temple upgrade identities and their modifier-mask families."""
import hashlib
import json

from tools.current_cards import ROOT,decode_archive,rows
from tools.native_scenery_oracle import NativeImage
from tools.reward_dispatch import key


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    balance=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw);files=decode_archive(balance);path='balance/templeupgrades.csv'
    groups={}
    for name,address,family in [('race',0x104a8efc,0),('jobs',0x104a900c,0),('House Values',0x104a98f0,1)]:
        text=image.read(address,80).split(b'\0')[0]
        if text.decode()!=name:raise ValueError('Unexpected original modifier family')
        groups[name]=dict(address=hex(address),bytes=(text+b'\0').hex(),family=family)
    records=[]
    for row in rows(files,path)[1:]:
        if not row or not row[0] or row[0].startswith('#'):continue
        tokens=[token.strip() for token in row[2].split(',')]
        if len(tokens)!=4 or tokens[0]!='table' or tokens[1] not in groups:raise ValueError('Unsupported original temple modifier '+row[2])
        records.append(dict(type=key(row[0]),unlock=key(row[1]),family=groups[tokens[1]]['family'],
                            name=row[0],unlock_name=row[1],effect=row[2]))
    counts=[sum(r['family']==family for r in records) for family in [0,1]]
    if len(records)>128 or max(counts)>64:raise ValueError('Original temple modifier capacity exceeded')
    routines=[(0x1013dd90,0x1013df86),(0x1013d580,0x1013d5f0),(0x1015c130,0x1015c16c),(0x10175216,0x1017544e)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(balance).hexdigest(),
                tables_sha256={path:hashlib.sha256(files[path]).hexdigest()},families=groups,records=records,
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in routines},
                scope='Original upgrade-mask refresh, source row ordering and unlock identities. Effect evaluation on followers/houses and spatial invalidation internals remain separate simulation services.')


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/temple-modifiers.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original temple upgrade modifiers:',len(content['records']))
