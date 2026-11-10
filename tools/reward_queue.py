"""Recover original reward admission, collection and inventory-consumption rules."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive,rows,ROOT
from tools.native_config import recover
from tools.native_scenery_oracle import NativeImage
from tools.original_assets import iw_hash
from tools.reward_dispatch import key


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    files=decode_archive(archive)
    native=recover(raw,['totemupgrade'])
    for address,name_address,initializer,slot in [(0x105a1534,0x104acae8,0x103adef0,0x105a15c0),(0x105a158c,0x104ace20,0x103ae800,0x105a1700)]:
        name=image.read(name_address,100).split(b'\0')[0].decode()
        native[name]=dict(value=struct.unpack('<f',image.read(address,4))[0],initializer=hex(initializer),data=hex(address),name=hex(name_address),slot=hex(slot))
    names={value['data']:name for name,value in native.items()}
    selected={}
    for address in ['0x105a1534','0x105a158c','0x105e30fc']:
        name=names[address];selected[name]=native[name]
    configuration={name:row['value'] for name,row in selected.items()}
    tables={path:rows(files,path) for path in ['config.csv','balance/config.csv','balance/specialcards.csv','balance/dynamicclaims.csv']}
    for path in ['config.csv','balance/config.csv']:
        for row in tables[path]:
            if len(row)>1 and row[0] in configuration:configuration[row[0]]=float(row[1])
    strings={hex(a):image.read(a,200).split(b'\0')[0].decode() for a in
             [0x104ac880,0x104ac864,0x104ac844,0x104ac814,0x104ac7ec,0x104ac7b8,0x104ac770,0x104ac740,0x104ac728,0x104ac6fc,0x104ac95c,0x104ac94c,0x104ac93c]}
    actions=[]
    for address in [0x104acb2c,0x104acb14,0x104acb04]:
        name=image.read(address,80).split(b'\0')[0].decode()
        actions.append(dict(name=name,id=iw_hash(name),address=hex(address)))
    internal=[]
    for category in range(6):
        target=struct.unpack('<I',image.read(0x1004d400+4*category,4))[0]
        code=image.read(target,5)
        if code[0]==0x68:
            pointer=struct.unpack('<I',code[1:])[0]
            internal.append(key(image.read(pointer,100).split(b'\0')[0].decode()))
        else:internal.append(0)
    special=[]
    for row in tables['balance/specialcards.csv'][1:]:
        if not row or not row[0] or row[0].startswith('#'):continue
        row=row+['']*(8-len(row))
        special.append(dict(id=key(row[0]),name=row[0],gems=int(row[1] or 0),belief=int(row[2] or 0),wheat=int(row[3] or 0),ore=int(row[4] or 0),followers=int(row[5] or 0),role=int(row[6] or 0),extra=iw_hash(row[7]) if row[7] else 0))
    rules=dict(auto_claim=configuration[names['0x105a1534']],delay=configuration[names['0x105a158c']],totem_upgrade=configuration[names['0x105e30fc']],
               gem_sticker=key('Sticker_Gem_1'),actions=[row['id'] for row in actions],internal_stickers=internal,
               exempt=[key(row[0]) for row in tables['balance/dynamicclaims.csv'][1:] if row and row[0] and not row[0].startswith('#')]+[0],
               strings=strings)
    ranges=[(0x10050170,0x1005056d),(0x10051080,0x100512f6),(0x1004eda0,0x1004eeaf),(0x1004eee0,0x1004ef89),
            (0x10001670,0x100016dc),(0x100016e0,0x100017fb),(0x10001800,0x10001861),
            (0x1004cb00,0x1004cb34),(0x1004cb40,0x1004cb53),(0x10026740,0x1002674c),
            (0x100267d0,0x100267da),(0x100242f0,0x100242fe),(0x1019a910,0x1019a92c),
            (0x103adf50,0x103adf81),(0x10031891,0x100318d1),(0x1004d340,0x1004d418),
            (0x10033c90,0x10033cc1),(0x10045d50,0x10045d9c),(0x100281e0,0x1002822c)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                native_configuration=selected,configuration=configuration,tables=tables,
                tables_sha256={path:hashlib.sha256(files[path]).hexdigest() for path in tables},
                rules=rules,actions=actions,special=special,native_routines={hex(a):image.read(a,b-a).hex() for a,b in ranges},
                scope='Original reward admission, collection query/acknowledgement and LIFO consumption with actual inventory arithmetic. Currency helper internals, research completion and special unit/name effects remain explicit simulation services.')


if __name__=='__main__':
    data=extract()
    (ROOT/'game/assets/original/campaign/reward-queue.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Original reward queue:',len(data['special']),'special rows')
