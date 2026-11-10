"""Recover original sticker-selector configuration, symbols and instruction bytes."""
import hashlib
import json
import struct

from tools.current_cards import decode_archive, rows
from tools.native_config import recover
from tools.native_scenery_oracle import NativeImage, ROOT

CONFIG = {
    0x105a1560:'StickerChance_TotallyRandomPcnt',0x105a1564:'StickerChance_PackBeads',
    0x105a1568:'StickerChance_OldBeads',0x105a156c:'StickerChance_CurrentBeads',
    0x105a1570:'StickerChance_NewBeads',0x105a1574:'StickerChance_OldBeads_Event',
    0x105a1578:'StickerChance_CurrentBeads_Event',0x105a157c:'StickerChance_NewBeads_Event',
    0x105a1580:'StickerChance_RareBeads',0x105a1584:'StickerChance_GemBeads'}


def extract():
    raw=(ROOT/'data/godus2_4/godus.s86').read_bytes()
    archive=(ROOT/'data/godus2_4/received/godussteamrel/balance.datz').read_bytes()
    image=NativeImage(raw)
    native={name:entry for name,entry in recover(raw,['sticker']).items() if name in CONFIG.values()}
    for address,name in CONFIG.items():
        if native[name]['data']!=hex(address):raise ValueError('Sticker configuration source moved')
    configuration={name:entry['value'] for name,entry in native.items()}
    files=decode_archive(archive)
    used={}
    for path in ['config.csv','balance/config.csv']:
        used[path]=hashlib.sha256(files[path]).hexdigest()
        for row in rows(files,path):
            if len(row)>1 and row[0] in configuration:configuration[row[0]]=float(row[1])
    symbols={}
    initializers={}
    code=image.read(0x103adf00,0x480)
    for at in range(len(code)-37):
        if code[at:at+5]!=b'\x55\x8b\xec\x51\x68' or code[at+32]!=0xa3:continue
        pointer=struct.unpack_from('<I',code,at+5)[0]
        destination=struct.unpack_from('<I',code,at+33)[0]
        name=image.read(pointer,80).split(b'\0')[0].decode()
        symbols[hex(destination)]=name
        initializers[name]=dict(address=hex(0x103adf00+at),bytes=code[at:at+41].hex(),string=hex(pointer))
    rare=[symbols[hex(address)] for address in [0x107ded30,0x107ded24,0x107ded28,0x107ded20,0x107ded38]]
    constant=image.read(0x104a7518,8)
    rules=dict(configuration=configuration,rare_rewards=rare,gem_reward=symbols['0x107ded34'],
               chance_scale=struct.unpack('<d',constant)[0],rare_threshold=struct.unpack('<I',image.read(0x10026731,4))[0])
    routines=[(0x1004de10,0x1004ed0d),(0x1004da90,0x1004daf4),(0x1004d2d0,0x1004d338),
              (0x10026730,0x1002673d),(0x100267d0,0x100267da),(0x10026800,0x10026809),
              (0x10026880,0x1002689c)]
    return dict(version=1,executable_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=hashlib.sha256(archive).hexdigest(),
                native_configuration=native,tables_sha256=used,symbols=symbols,initializers=initializers,rules=rules,
                constants=dict(chance_scale=dict(address='0x104a7518',bytes=constant.hex())),
                native_routines={hex(a):image.read(a,b-a).hex() for a,b in routines})


if __name__=='__main__':
    content=extract()
    (ROOT/'game/assets/original/campaign/sticker-selection.json').write_text(json.dumps(content,indent=2)+'\n')
    print('Original sticker selector:',len(content['rules']['configuration']),'configuration values')
